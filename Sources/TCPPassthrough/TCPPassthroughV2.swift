//
//  TCPPassthrough.swift
//
//  Created by David Corbin on 12/30/19.
//

import os
import Foundation
import Socket

let TCP_PASSTHROUGH_RETRY_DELAY_SECONDS_V2 = 1
let TCP_PASSTHROUGH_QUEUE_LABEL = "com.davidcorbin.TCPPassthroughV2"

public class TCPPassthroughV2 {
    public static let shared = TCPPassthroughV2()
    private init() {} // Don't allow manual initialization; this a singleton
    
    var cloudData: TCPPassthroughCloudModel? = nil
    var cloudAPIConnection: URL? = nil
    var robotAPIConnection: URL? = nil
    
    let dispatchQueue = DispatchQueue(label: TCP_PASSTHROUGH_QUEUE_LABEL, attributes: .concurrent)
    let connectionDispatchGroup = DispatchGroup()
    let passthroughDispatchGroup = DispatchGroup()
    
    var cloudSocketConn: Socket? = nil
    var robotSocketConn: Socket? = nil
    
    public func start(cloudData: TCPPassthroughCloudModel, cloudAPIConnection: URL, robotAPIConnection: URL) {
        os_log("Starting TCPPassthrough", type: .info)
        self.cloudData = cloudData
        self.cloudAPIConnection = cloudAPIConnection
        self.robotAPIConnection = robotAPIConnection

        connectToRobotAsync()
        connectToCloudAsync()
        
        connectionDispatchGroup.notify(queue: dispatchQueue) {
            os_log("All connections completed", type: .info)
            self.readRobotAndForwardToCloudAsync()
            self.readCloudAndForwardToRobotAsync()
        }
    }
    
    private func readRobotAndForwardToCloudAsync() {
        self.dispatchQueue.async {
            self.readRobotAndForwardToCloudSync()
            self.robotSocketConn?.close()
            self.cloudSocketConn?.close()
            
            DispatchQueue.main.async {
                self.connectToRobotAsync()
                self.connectionDispatchGroup.notify(queue: self.dispatchQueue) {
                    os_log("All connections completed again", type: .info)
                    self.readRobotAndForwardToCloudAsync()
                    self.readCloudAndForwardToRobotAsync()
                }
            }
        }
    }
    
    private func readCloudAndForwardToRobotAsync() {
        self.dispatchQueue.async {
            self.readCloudAndForwardToRobotSync()
            self.cloudSocketConn?.close()
            DispatchQueue.main.async {
                self.connectToCloudAsync()
                self.connectionDispatchGroup.notify(queue: self.dispatchQueue) {
                    os_log("All connections completed again", type: .info)
                    self.readCloudAndForwardToRobotAsync()
                }
            }
        }
    }
    
    private func readRobotAndForwardToCloudSync() {
        while let robotSocket = self.robotSocketConn, robotSocket.isConnected {
            var readData = Data(capacity: robotSocket.readBufferSize)
            
            // Try to read data
            do {
                let bytesRead = try robotSocket.read(into: &readData)
                guard bytesRead > 0 else {
                    os_log("Disconnected from Robot Connection: Zero bytes read", type: .info)
                    return
                }
            } catch {
                os_log("Socket read error: %s", type: .error, error.localizedDescription)
                return
            }
            
            // Try to write data
            do {
                try sendDataToCloud(data: readData)
            } catch {
                os_log("Socket write error: %s", type: .error, error.localizedDescription)
                return
            }
        }
    }
    
    private func readCloudAndForwardToRobotSync() {
        while let cloudSocket = self.cloudSocketConn, cloudSocket.isConnected {
            var readData = Data(capacity: cloudSocket.readBufferSize)
            
            // Try to read data
            do {
                let bytesRead = try cloudSocket.read(into: &readData)
                guard bytesRead > 0 else {
                    os_log("Disconnected from Cloud Connection: Zero bytes read", type: .info)
                    return
                }
            } catch {
                os_log("Socket read error: %s", type: .error, error.localizedDescription)
                return
            }
            
            // Try to write data
            do {
                try sendDataToRobot(data: readData)
            } catch {
                os_log("Socket write error: %s", type: .error, error.localizedDescription)
                return
            }
        }
    }
    
    private func sendDataToRobot(data: Data) throws {
        try self.robotSocketConn?.write(from: data)
    }
    
    private func sendDataToCloud(data: Data) throws {
        try self.cloudSocketConn?.write(from: data)
    }
    
    
    private func connectToRobotAsync() {
        self.connectionDispatchGroup.enter()
        self.dispatchQueue.async {
            // While not connected, connect to robot
            while self.robotSocketConn == nil || !self.robotSocketConn!.isConnected {
                let socketVal = self.connectToTaurosRobotInterfaceSync()
                if socketVal == nil {
                    sleep(UInt32(TCP_PASSTHROUGH_RETRY_DELAY_SECONDS_V2))
                } else {
                    self.robotSocketConn = socketVal
                    break
                }
            }
            
            self.connectionDispatchGroup.leave()
        }
    }
    
    private func connectToCloudAsync() {
        self.connectionDispatchGroup.enter()
        self.dispatchQueue.async {
            // While not connected, connect to cloud
            while self.cloudSocketConn == nil || !self.cloudSocketConn!.isConnected {
                let socketVal = self.connectToTaurosCloudSync()
                if socketVal == nil {
                    sleep(UInt32(TCP_PASSTHROUGH_RETRY_DELAY_SECONDS_V2))
                } else {
                    self.cloudSocketConn = socketVal
                    break
                }
            }
            
            self.connectionDispatchGroup.leave()
        }
    }
    
    private func getLocalConnectionPortFromCloudSync(json: TCPPassthroughCloudModel) -> Int? {
        var jsonData:Data? = nil
        do {
            jsonData = try JSONEncoder().encode(json)
        } catch {
            os_log("Error encoding JSON: %s", type: .error, error.localizedDescription)
        }
        
        guard let cloudAPIConn = self.cloudAPIConnection else {
             os_log("Error reading cloudAPIConnection")
             return nil
        }
        
        var request = URLRequest(url: cloudAPIConn)
        request.httpMethod = "POST"

        request.httpBody = jsonData
        
        let sem = DispatchSemaphore(value: 0)
        
        var listeningPort: Int?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { sem.signal() }
            
            guard let data = data, error == nil else {
                os_log("Error retreiveing host from Cloud API", type: .info)
                listeningPort = nil
                return
            }
            let responseJSON = try? JSONSerialization.jsonObject(with: data, options: [])
            if let responseJSON = responseJSON as? [String: String] {
                let listeningHostStr = responseJSON["ListeningHost"]
                let listeningHostPort = listeningHostStr?.dropFirst(5)
                listeningPort = Int(listeningHostPort!) ?? 0
            }
        }

        task.resume()
        
        _ = sem.wait(timeout: .distantFuture)
        
        return listeningPort
    }
    
    private func connectToTaurosCloudSync() -> Socket? {
        guard let cloudData = self.cloudData, let host = self.cloudAPIConnection?.host, let listeningPort = getLocalConnectionPortFromCloudSync(json: cloudData) else {
            return nil
        }

        do {
            let taurosCloudConn = try Socket.create(family: .inet)
            try taurosCloudConn.connect(to: host, port: Int32(listeningPort))
            os_log("Connected to: %s:%i as Cloud Connection", type: .info, taurosCloudConn.remoteHostname, taurosCloudConn.remotePort)
            return taurosCloudConn
        } catch {
            os_log("Socket error when connecting to Cloud Connection - Host: %s, listeningPort: %i, Error: %s", type: .error, String(host), listeningPort, error.localizedDescription)
            return nil
        }
    }
    
    private func connectToTaurosRobotInterfaceSync() -> Socket? {
        guard let host = self.robotAPIConnection?.host, let port = self.robotAPIConnection?.port else {
            return nil
        }

        do {
            let taurosRobotConn = try Socket.create(family: .inet)
            try taurosRobotConn.connect(to: host, port: Int32(port))
            os_log("Connected to: %s:%i as Robot Connection", type: .info, taurosRobotConn.remoteHostname, taurosRobotConn.remotePort)
            return taurosRobotConn
        } catch {
            os_log("Socket error when connection to Robot Connection - Host: %s, listeningPort: %i, Error: %s", type: .error, host, port, error.localizedDescription)
            return nil
        }
    }
}
