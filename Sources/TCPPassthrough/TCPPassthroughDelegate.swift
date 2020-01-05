//
//  File.swift
//  
//
//  Created by David Corbin on 1/2/20.
//

import Foundation

public protocol TCPPassthroughDelegate: class {
    func didConnectToRobot()
    func didDisconnectFromRobot()
}
