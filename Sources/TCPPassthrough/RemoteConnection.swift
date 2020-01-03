//
//  File.swift
//  
//
//  Created by David Corbin on 1/3/20.
//

import Foundation
import Logging
import Socket

class RemoteConnection: TCPConnection {
    let cloudData: TCPPassthroughCloudModel
    let cloudAPIConnection: URL
    
    init(cloudData: TCPPassthroughCloudModel, cloudAPIConnection: URL) {
        self.cloudData = cloudData
        self.cloudAPIConnection = cloudAPIConnection
    }
    
    private func getLocalConnectionPortFromCloudSync(cloudConnectionModel: TCPPassthroughCloudModel, cloudAPIEndpoint: URL) -> Int? {
        var jsonData:Data? = nil
        do {
            jsonData = try JSONEncoder().encode(cloudConnectionModel)
        } catch {
            self.logger.error("Error encoding JSON: \(error)")
        }
        
        var request = URLRequest(url: cloudAPIEndpoint)
        request.httpMethod = "POST"

        request.httpBody = jsonData
        
        let sem = DispatchSemaphore(value: 0)
        
        var listeningPort: Int?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { sem.signal() }
            
            guard let data = data, error == nil else {
                self.logger.info("Error retreiveing host from Cloud API")
                listeningPort = nil
                return
            }
            let responseJSON = try? JSONSerialization.jsonObject(with: data, options: [])
            if let responseJSON = responseJSON as? [String: String] {
                let listeningHostStr = responseJSON["ListeningHost"]
                let listeningHostPort = listeningHostStr?.dropFirst(5)
                listeningPort = Int(listeningHostPort!) ?? 0
            }
        }

        task.resume()
        
        _ = sem.wait(timeout: .distantFuture)
        
        return listeningPort
    }
    
    func connectToTaurosCloudSync() -> Socket? {
        guard let host = self.cloudAPIConnection.host, let listeningPort = self.getLocalConnectionPortFromCloudSync(cloudConnectionModel: cloudData, cloudAPIEndpoint: self.cloudAPIConnection), let socketURL = URL(string: "http://" + host + ":" + String(listeningPort)) else {
            self.logger.critical("Error casting data")
            return nil
        }
        return getSocketConnection(url: socketURL)
    }
}
