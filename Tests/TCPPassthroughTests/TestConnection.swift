//
//  TestConnection.swift
//
//
//  Created by David Corbin on 1/6/20.
//

import TCPPassthrough
import Foundation
import Socket
import Logging

class TestConnection: TCPConnection {
    private var logger = Logger(label: TCP_PASSTHROUGH_QUEUE_LABEL)

    private var socket: Socket? = nil

    let robotSocketURL: URL

    init(robotSocketURL: URL) {
        self.robotSocketURL = robotSocketURL
    }

    func getSocketConnection() -> Socket? {
        if let sock = self.socket {
            if sock.isConnected {
                return self.socket
            }
            else {
                self.socket?.close()
                self.socket = nil
            }
        }

        guard let host = self.robotSocketURL.host, let listeningPort = self.robotSocketURL.port else {
            self.logger.critical("Error casting data")
            return nil
        }

        do {
            self.socket = try Socket.create(family: .inet)
            try self.socket?.connect(to: host, port: Int32(listeningPort))
            self.logger.info("Connected to \(self.socket!.remoteHostname):\(self.socket!.remotePort)")
            return socket
        } catch {
            self.logger.error("Socket error when connection to Robot Connection - Host: \(host), listeningPort: \(listeningPort), Error: \(error)")
            return nil
        }
    }

    func writeSocket(data: Data) throws {
        try self.socket?.write(from: data)
    }

    func closeSocket() {
        guard let sock = self.socket else {
            return
        }
        sock.close()
    }
}
