//
//  File.swift
//  
//
//  Created by David Corbin on 1/3/20.
//

import Foundation
import Socket

class LocalConnection: TCPConnection {
    let robotSocketURL: URL
    
    init(robotSocketURL: URL) {
        self.robotSocketURL = robotSocketURL
    }
    
    func connectToTaurosRobotInterfaceSync() -> Socket? {
        return getSocketConnection(url: self.robotSocketURL)
    }
}
