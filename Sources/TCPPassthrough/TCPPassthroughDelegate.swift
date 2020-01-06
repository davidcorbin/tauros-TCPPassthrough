//
//  TCPPassthroughDelegate.swift
//  
//
//  Created by David Corbin on 1/2/20.
//

import Foundation

public protocol TCPPassthroughDelegate: class {
    func didConnectToLocal()
    func didDisconnectFromLocal()
    
    func didConnectToRemote()
    func didDisconnectFromRemote()
}

extension TCPPassthroughDelegate {
    func didConnectToLocal() {}
    func didDisconnectFromLocal() {}
    
    func didConnectToRemote() {}
    func didDisconnectFromRemote() {}
}
