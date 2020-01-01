//
//  TCPPassthroughCloudModel.swift
//  
//
//  Created by David Corbin on 12/31/19.
//

import Foundation

public struct TCPPassthroughCloudModel: Codable {
    var local_user_uid: String
    var local_username: String
    var local_user_lat: Float
    var local_user_lon: Float
    var signal_strength: Int
    
    init(local_user_uid: String, local_username: String, local_user_lat: Float, local_user_lon: Float, signal_strength: Int) {
        self.local_user_uid = local_user_uid
        self.local_username = local_username
        self.local_user_lat = local_user_lat
        self.local_user_lon = local_user_lon
        self.signal_strength = signal_strength
    }
}
