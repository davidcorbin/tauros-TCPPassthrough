//
//  TCPPassthrough.swift
//
//  Created by David Corbin on 12/30/19.
//

import Foundation
import Socket
import Logging

let TCP_PASSTHROUGH_RETRY_DELAY_SECONDS_V2 = 1
let TCP_PASSTHROUGH_QUEUE_LABEL = "com.davidcorbin.TCPPassthroughV2"

public class TCPPassthroughV2 {
    public static let shared = TCPPassthroughV2()
    private init() {} // Don't allow manual initialization; this a singleton
    
    var logger = Logger(label: "com.davidcorbin.TCPPassthroughV2")
    
    var cloudData: TCPPassthroughCloudModel? = nil
    var cloudAPIConnection: URL? = nil
    var robotAPIConnection: URL? = nil
    
    let dispatchQueue = DispatchQueue(label: TCP_PASSTHROUGH_QUEUE_LABEL, attributes: .concurrent)
    let connectionDispatchGroup = DispatchGroup()
    let passthroughDispatchGroup = DispatchGroup()
    
    var cloudSocketConn: Socket? = nil
    var robotSocketConn: Socket? = nil
    
    public func start(cloudData: TCPPassthroughCloudModel, cloudAPIConnection: URL, robotAPIConnection: URL) {
        self.logger[metadataKey: "Package"] = "TCPPassthroughV2"
        
        self.logger.info("Starting TCPPassthrough")
        self.cloudData = cloudData
        self.cloudAPIConnection = cloudAPIConnection
        self.robotAPIConnection = robotAPIConnection

        connectToRobotAsync()
        connectToCloudAsync()
        
        connectionDispatchGroup.notify(queue: dispatchQueue) {
            self.logger.info("All connections completed")
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
                    self.logger.info("All connections completed again")
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
                    self.logger.info("All connections completed again")
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
                    self.logger.info("Disconnected from Robot Connection: Zero bytes read")
                    return
                }
            } catch {
                logger.error("Socket read error: \(error)")
                return
            }
            
            // Try to write data
            do {
                try sendDataToCloud(data: readData)
            } catch {
                self.logger.error("Socket write error: \(error)")
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
                    self.logger.info("Disconnected from Cloud Connection: Zero bytes read")
                    return
                }
            } catch {
                self.logger.error("Socket read error: \(error)")
                return
            }
            
            // Try to write data
            do {
                try sendDataToRobot(data: readData)
            } catch {
                self.logger.error("Socket write error: \(error)")
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
            self.logger.error("Error encoding JSON: \(error)")
        }
        
        guard let cloudAPIConn = self.cloudAPIConnection else {
            self.logger.error("Error reading cloudAPIConnection")
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
                self.logger.info("Error retreiveing host from Cloud API")
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
            self.logger.info("Connected to: \(taurosCloudConn.remoteHostname):\(taurosCloudConn.remotePort) as Cloud Connection")
            return taurosCloudConn
        } catch {
            self.logger.error("Socket error when connecting to Cloud Connection - Host: \(host), listeningPort: \(listeningPort), Error: \(error)")
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
            self.logger.info("Connected to: \(taurosRobotConn.remoteHostname):\(taurosRobotConn.remotePort) as Robot Connection")
            return taurosRobotConn
        } catch {
            self.logger.error("Socket error when connection to Robot Connection - Host: \(host), listeningPort: \(port), Error: \(error)")
            return nil
        }
    }
}
