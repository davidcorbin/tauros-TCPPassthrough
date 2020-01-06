//
//  TCPPassthroughV2.swift
//
//
//  Created by David Corbin on 12/30/19.
//

import Foundation
import Socket
import Logging

public let TCP_PASSTHROUGH_RETRY_DELAY_SECONDS_V2 = 1
public let TCP_PASSTHROUGH_QUEUE_LABEL = "com.davidcorbin.TCPPassthroughV2"

public class TCPPassthroughV2 {
    // Shared singleton
    public static let shared = TCPPassthroughV2()
    private init() {} // Don't allow manual initialization; this a singleton
    
    var logger = Logger(label: TCP_PASSTHROUGH_QUEUE_LABEL)
    
    public weak var delegate: TCPPassthroughDelegate?
    
    let dispatchQueue = DispatchQueue(label: TCP_PASSTHROUGH_QUEUE_LABEL, attributes: .concurrent)
    let connectionDispatchGroup = DispatchGroup()
    let passthroughDispatchGroup = DispatchGroup()
    
    var localSocketConn: TCPConnection? = nil
    var remoteSocketConn: TCPConnection? = nil
    
    var isStopped = true
    var wasConnectedToRemote = false
    var wasConnectedToLocal = false

    public func start(localSocketConn: TCPConnection, remoteSocketConn: TCPConnection) {
        self.logger.info("Starting TCPPassthrough")
        
        self.isStopped = false
        
        self.localSocketConn = localSocketConn
        self.remoteSocketConn = remoteSocketConn

        self.readLocalAndForwardToRemoteAsync()
        self.readRemoteAndForwardToLocalAsync()
    }
    
    // - MARK: Read and Forward Data Async

    private func readLocalAndForwardToRemoteAsync() {
        self.dispatchQueue.async {
            // Try to build connection forever
            while !self.isStopped {
                // Start read loop
                // When this exists
                self.logger.info("Starting Local -> Remote connection")
                self.readLocalAndForwardToRemoteSync()
                
                // If local disconnection, close both local and remote
                self.localSocketConn?.closeSocket()
                self.remoteSocketConn?.closeSocket()
                
                // Call delegates if was connected previously
                if self.wasConnectedToLocal {
                    self.delegate?.didDisconnectFromLocal()
                    self.wasConnectedToLocal = false
                }
                
                if self.wasConnectedToRemote {
                    self.delegate?.didDisconnectFromRemote()
                    self.wasConnectedToRemote = false
                }
                
                // Sleep before trying to reconnect
                if !self.isStopped {
                    sleep(UInt32(TCP_PASSTHROUGH_RETRY_DELAY_SECONDS_V2))
                }
            }
        }
    }
    
    private func readRemoteAndForwardToLocalAsync() {
        self.dispatchQueue.async {
            while !self.isStopped {
                self.logger.info("Starting Remote -> Local connection")
                self.readRemoteAndForwardToLocalSync()

                // If remote disconnection, close both local and remote
                self.localSocketConn?.closeSocket()
                self.remoteSocketConn?.closeSocket()

                // Call delegates if just disconnected
                if self.wasConnectedToLocal {
                    self.delegate?.didDisconnectFromLocal()
                    self.wasConnectedToLocal = false
                }

                if self.wasConnectedToRemote {
                    self.delegate?.didDisconnectFromRemote()
                    self.wasConnectedToRemote = false
                }

                // Sleep before trying to reconnect
                if !self.isStopped {
                    sleep(UInt32(TCP_PASSTHROUGH_RETRY_DELAY_SECONDS_V2))
                }
            }
        }
    }
    
    // - MARK: Read and Forward Data Sync
    
    private func readLocalAndForwardToRemoteSync() {
        while let localSocket = self.localSocketConn?.getSocketConnection(), localSocket.isConnected {

            // Notify that local connection is complete
            if !self.wasConnectedToLocal {
                self.delegate?.didConnectToLocal()
            }
            self.wasConnectedToLocal = true
            
            var readData = Data(capacity: localSocket.readBufferSize)
            
            // Try to read data
            do {
                let bytesRead = try localSocket.read(into: &readData)
                guard bytesRead > 0 else {
                    self.logger.info("disconnected from Local Connection")
                    return
                }
            } catch {
                logger.error("Local socket read error: \(error)")
                return
            }
            
            // Try to write data
            do {
                try sendDataToRemote(data: readData)
            } catch {
                self.logger.error("Local socket write error: \(error)")
                return
            }
        }
    }
    
    private func readRemoteAndForwardToLocalSync() {
        while let remoteSocket = self.remoteSocketConn?.getSocketConnection(), remoteSocket.isConnected {

            // Notify that remote connection is complete
            if !self.wasConnectedToRemote {
                self.delegate?.didConnectToRemote()
            }
            self.wasConnectedToRemote = true
            
            var readData = Data(capacity: remoteSocket.readBufferSize)
            
            // Try to read data
            do {
                let bytesRead = try remoteSocket.read(into: &readData)
                guard bytesRead > 0 else {
                    self.logger.info("disconnected from Remote Connection")
                    return
                }
            } catch {
                self.logger.error("Remote socket read error: \(error)")
                return
            }
            
            // Try to write data
            do {
                try sendDataToLocal(data: readData)
            } catch {
                self.logger.error("Remote socket write error: \(error)")
                return
            }
        }
    }
    
    private func sendDataToLocal(data: Data) throws {
        try self.localSocketConn?.writeSocket(data: data)
    }

    private func sendDataToRemote(data: Data) throws {
        try self.remoteSocketConn?.writeSocket(data: data)
    }
    
    public func stop() {
        self.isStopped = true
        self.localSocketConn?.closeSocket()
        self.remoteSocketConn?.closeSocket()
    }
}
