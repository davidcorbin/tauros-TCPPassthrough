//
//  File.swift
//  
//
//  Created by David Corbin on 1/3/20.
//

import Foundation
import Logging
import Socket

class TCPConnection {
    var logger = Logger(label: "com.davidcorbin.TCPPassthroughV2")
    
    func getSocketConnection(url: URL) -> Socket? {
        guard let host = url.host, let port = url.port else {
            return nil
        }

        do {
            let socket = try Socket.create(family: .inet)
            try socket.connect(to: host, port: Int32(port))
            self.logger.info("Connected to: \(socket.remoteHostname):\(socket.remotePort)")
            return socket
        } catch {
            self.logger.error("Socket error when connection to Robot Connection - Host: \(host), listeningPort: \(port), Error: \(error)")
            return nil
        }
    }
}
