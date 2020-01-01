//
//  TCPPassthroughCloudModel.swift
//  
//
//  Created by David Corbin on 12/31/19.
//

import Foundation

struct TCPPassthroughCloudModel: Codable {
    var local_user_uid: String
    var local_username: String
    var local_user_lat: Float
    var local_user_lon: Float
    var signal_strength: Int
}
