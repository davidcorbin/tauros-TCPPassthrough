//
//  File.swift
//  
//
//  Created by David Corbin on 1/3/20.
//

import Foundation
import Logging
import Socket

public protocol TCPConnection {
    func getSocketConnection() -> Socket?
    func writeSocket(data: Data) throws
    func closeSocket()
}
