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
    // Shared singleton
    public static let shared = TCPPassthroughV2()
    private init() {} // Don't allow manual initialization; this a singleton
    
    var logger = Logger(label: "com.davidcorbin.TCPPassthroughV2")
    
    public var delegate: TCPPassthroughDelegate?
    
    var cloudData: TCPPassthroughCloudModel? = nil
    var cloudAPIConnection: URL? = nil
    var robotAPIConnection: URL? = nil
    
    let dispatchQueue = DispatchQueue(label: TCP_PASSTHROUGH_QUEUE_LABEL, attributes: .concurrent)
    let connectionDispatchGroup = DispatchGroup()
    let passthroughDispatchGroup = DispatchGroup()
    
    var cloudSocketConn: Socket? = nil
    var robotSocketConn: Socket? = nil
    
    public func start(cloudData: TCPPassthroughCloudModel, cloudAPIConnection: URL, robotAPIConnection: URL) {        
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
    
    // - MARK: Read and Forward Data Async
    
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
    
    // - MARK: Read and Forward Data Sync
    
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
    
    // - MARK: Establish Connection Async
    
    private func connectToRobotAsync() {
        self.connectionDispatchGroup.enter()
        self.dispatchQueue.async {
            // While not connected, connect to robot
            while self.robotSocketConn == nil || !self.robotSocketConn!.isConnected {
                guard let url = self.robotAPIConnection else {
                    self.logger.critical("Could not cast URL")
                    return
                }

                let lc = LocalConnection(robotSocketURL: url)
                let socketVal = lc.connectToTaurosRobotInterfaceSync()
                
                // If connection failed, wait and try again
                if socketVal == nil {
                    sleep(UInt32(TCP_PASSTHROUGH_RETRY_DELAY_SECONDS_V2))
                } else {
                    self.robotSocketConn = socketVal
                    break
                }
            }
            
            self.delegate?.didConnectToRobot()
            
            self.connectionDispatchGroup.leave()
        }
    }
    
    private func connectToCloudAsync() {
        self.connectionDispatchGroup.enter()
        self.dispatchQueue.async {
            // While not connected, connect to cloud
            while self.cloudSocketConn == nil || !self.cloudSocketConn!.isConnected {
                guard let url = self.cloudAPIConnection else {
                    self.logger.critical("Could not cast URL")
                    return
                }
                
                guard let cloudData = self.cloudData else {
                    self.logger.critical("Could not cast cloud data object")
                    return
                }

                let rc = RemoteConnection(cloudData: cloudData, cloudAPIConnection: url)
                let socketVal = rc.connectToTaurosCloudSync()
                
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
}
