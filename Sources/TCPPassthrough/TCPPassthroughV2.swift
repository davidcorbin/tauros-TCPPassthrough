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
    
    // Logger
    private var logger = Logger(label: TCP_PASSTHROUGH_QUEUE_LABEL)
    
    // Delegate
    public weak var delegate: TCPPassthroughDelegate?
    
    private let dispatchQueue = DispatchQueue(label: TCP_PASSTHROUGH_QUEUE_LABEL, attributes: .concurrent)
    
    private var localSocketConn: TCPConnection? = nil
    private var remoteSocketConn: TCPConnection? = nil
    
    private var isStopped = true
    private var wasConnectedToRemote = false
    private var wasConnectedToLocal = false
    
    private var remoteToLocalByteCounter = 0
    private var localToRemoteByteCounter = 0
    private var isRtoLTimerRunning = false
    private var isLtoRTimerRunning = false

    /**
     Start full duplex connection between two TCP servers.
     
     - Parameter localSocketConn: TCP server to connect to first
     - Parameter remoteSocketConn: TCP server to connect to second
     */
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
                                
                readData = readData.subdata(in: 0..<bytesRead)
                                
                updateLocalToRemoteByteCounter(numOfBytes: bytesRead)
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
                
                readData = readData.subdata(in: 0..<bytesRead)
                
                updateRemoteToLocalByteCounter(numOfBytes: bytesRead)
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
    
    /**
     Close connection between two TCP servers.
     */
    public func stop() {
        self.isStopped = true
        self.localSocketConn?.closeSocket()
        self.remoteSocketConn?.closeSocket()
    }
    
    // - MARK: Data transfer rates
    
    private func updateRemoteToLocalByteCounter(numOfBytes: Int) {
        if self.isRtoLTimerRunning {
            self.remoteToLocalByteCounter += numOfBytes
        } else {
            self.isRtoLTimerRunning = true
            self.dispatchQueue.asyncAfter(deadline: .now() + .seconds(1), execute: {
                self.delegate?.bytesTransferredRtoL(numOfBytes: self.remoteToLocalByteCounter)
                self.isRtoLTimerRunning = false
            })
        }
    }
    
    private func updateLocalToRemoteByteCounter(numOfBytes: Int) {
        if self.isLtoRTimerRunning {
            self.localToRemoteByteCounter += numOfBytes
        } else {
            self.isLtoRTimerRunning = true
            self.dispatchQueue.asyncAfter(deadline: .now() + .seconds(1), execute: {
                self.delegate?.bytesTransferredLtoR(numOfBytes: self.localToRemoteByteCounter)
                self.isLtoRTimerRunning = false
            })
        }
    }
}

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let hexDigits = Array((options.contains(.upperCase) ? "0123456789ABCDEF" : "0123456789abcdef").utf16)
        var chars: [unichar] = []
        chars.reserveCapacity(2 * count)
        for byte in self {
            chars.append(hexDigits[Int(byte / 16)])
            chars.append(hexDigits[Int(byte % 16)])
        }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
}
