import XCTest
import Socket

@testable import TCPPassthrough

final class TCPPassthroughTests: XCTestCase {
    let dispatchQueue = DispatchQueue(label: TCP_PASSTHROUGH_QUEUE_LABEL + "TESTS", attributes: .concurrent)
    
    func testRemoteSendToLocalAndLocalSendToRemote() {
        var localSocketServer: Socket? = nil
        var remoteSocketServer: Socket? = nil
        
        // Create local connection
        dispatchQueue.async {
            do {
                let listenSocket = try Socket.create(family: .inet)
                try listenSocket.listen(on: 12345)
                            
                localSocketServer = try listenSocket.acceptClientConnection()
                                    
                self.dispatchQueue.async {
                    var readData = Data(capacity: listenSocket.readBufferSize)
                    
                    do {
                        let bytesRead = try localSocketServer?.read(into: &readData)
                        if bytesRead! > 0 {
                            guard let response = String(data: readData, encoding: .utf8) else {
                                print("Error decoding response...")
                                localSocketServer?.close()
                                return
                            }
                            
                            if response != "message1" {
                                XCTFail("expected to recevive 'message1'")
                            } else {
                                print("Correct message received from remote")
                            }
                            
                            try localSocketServer?.write(from: "message2")
                        } else {
                            XCTFail("No data received")
                        }
                        localSocketServer?.close()
                    }
                    catch {
                        XCTFail("Error reading data")
                    }
                }
            }
            catch {
                XCTFail("Error listening")
            }
        }
        
        // Create remote connection
        dispatchQueue.async {
            do {
                let listenSocket = try Socket.create(family: .inet)
                try listenSocket.listen(on: 12346)
                            
                remoteSocketServer = try listenSocket.acceptClientConnection()
                                    
                self.dispatchQueue.async {
                    var readData = Data(capacity: listenSocket.readBufferSize)
                    
                    do {
                        let bytesRead = try remoteSocketServer?.read(into: &readData)
                        if bytesRead! > 0 {
                            guard let response = String(data: readData, encoding: .utf8) else {
                                print("Error decoding response...")
                                remoteSocketServer?.close()
                                return
                            }
                            
                            if response != "message2" {
                                XCTFail("expected to receive 'message2'")
                            } else {
                                print("Correct message received from local")
                            }
                        } else {
                            XCTFail("No data received")
                        }
                        remoteSocketServer?.close()
                    }
                    catch {
                        XCTFail("Error reading data")
                    }
                }
            }
            catch {
                XCTFail("Error listening")
            }
        }
        
        sleep(1)

        let localConn = TestConnection(robotSocketURL: URL(string: "http://localhost:12345")!)
        let remoteConn = TestConnection(robotSocketURL: URL(string: "http://localhost:12346")!)
        
        TCPPassthroughV2.shared.start(localSocketConn: localConn, remoteSocketConn: remoteConn)
                
        sleep(1)
        
        try! remoteSocketServer?.write(from: "message1")
        
        sleep(1)
        
        TCPPassthroughV2.shared.stop()
        
        localSocketServer?.close()
        remoteSocketServer?.close()
    }

    func testRemoteSendWhileLocalClosed() {
        var localSocketServer: Socket? = nil
        var remoteSocketServer: Socket? = nil
        
        // Create local connection
        dispatchQueue.async {
            do {
                let listenSocket = try Socket.create(family: .inet)
                try listenSocket.listen(on: 12345)
                            
                localSocketServer = try listenSocket.acceptClientConnection()
                                    
                self.dispatchQueue.async {
                    var readData = Data(capacity: listenSocket.readBufferSize)
                    
                    do {
                        let bytesRead = try localSocketServer?.read(into: &readData)
                        if bytesRead! > 0 {
                            guard let response = String(data: readData, encoding: .utf8) else {
                                print("Error decoding response...")
                                localSocketServer?.close()
                                return
                            }
                            
                            if response != "message1" {
                                XCTFail("expected to recevive 'message1'")
                            } else {
                                print("Correct message received by from remote")
                            }
                            
                            try localSocketServer?.write(from: "message2")
                        } else {
                            XCTFail("No data received")
                        }
                        localSocketServer?.close()
                    } catch {
                        
                    }
                }
            }
            catch {
                XCTFail("Error listening")
            }
        }
        
        // Create remote connection
        dispatchQueue.async {
            do {
                let listenSocket = try Socket.create(family: .inet)
                try listenSocket.listen(on: 12346)
                            
                remoteSocketServer = try listenSocket.acceptClientConnection()
                                    
                self.dispatchQueue.async {
                    var readData = Data(capacity: listenSocket.readBufferSize)
                    
                    do {
                        let bytesRead = try remoteSocketServer?.read(into: &readData)
                        if bytesRead! != 0 {
                            XCTFail("Expected remote server disconnect")
                        }
                        if bytesRead! > 0 {
                            guard let response = String(data: readData, encoding: .utf8) else {
                                print("Error decoding response...")
                                remoteSocketServer?.close()
                                return
                            }
                            
                            if response != "message2" {
                                XCTFail("expected to receive 'message2'")
                            } else {
                                print("Correct message received from local")
                            }
                        }
                        remoteSocketServer?.close()
                    }
                    catch {
                        XCTFail("Error reading data")
                    }
                }
            }
            catch {
                XCTFail("Error listening")
            }
        }

        sleep(1)

        let localConn = TestConnection(robotSocketURL: URL(string: "http://localhost:12345")!)
        let remoteConn = TestConnection(robotSocketURL: URL(string: "http://localhost:12346")!)
        
        TCPPassthroughV2.shared.start(localSocketConn: localConn, remoteSocketConn: remoteConn)
                
        sleep(1)
        
        localSocketServer?.close()
        
        sleep(1)
        
        do {
            try remoteSocketServer?.write(from: "message1")
            XCTFail("write should fail because remote connection was closed")
        } catch { }
        
        sleep(1)
        
        TCPPassthroughV2.shared.stop()

        remoteSocketServer?.close()
    }
    
    func testLocalSendWhileRemoteClosed() {
        var localSocketServer: Socket? = nil
        var remoteSocketServer: Socket? = nil
        
        // Create local connection
        dispatchQueue.async {
            do {
                let listenSocket = try Socket.create(family: .inet)
                try listenSocket.listen(on: 12345)
                            
                localSocketServer = try listenSocket.acceptClientConnection()
                                    
                self.dispatchQueue.async {
                    var readData = Data(capacity: listenSocket.readBufferSize)
                    
                    do {
                        let bytesRead = try localSocketServer?.read(into: &readData)
                        if bytesRead! > 0 {
                            guard let response = String(data: readData, encoding: .utf8) else {
                                print("Error decoding response...")
                                localSocketServer?.close()
                                return
                            }
                            
                            if response != "message1" {
                                XCTFail("expected to recevive 'message1'")
                            } else {
                                print("Correct message received by from remote")
                            }
                            
                            try localSocketServer?.write(from: "message2")
                        } else { }
                        localSocketServer?.close()
                    } catch {
                        
                    }
                }
            }
            catch {
                XCTFail("Error listening")
            }
        }
        
        // Create remote connection
        dispatchQueue.async {
            do {
                let listenSocket = try Socket.create(family: .inet)
                try listenSocket.listen(on: 12346)
                            
                remoteSocketServer = try listenSocket.acceptClientConnection()
                                    
                self.dispatchQueue.async {
                    var readData = Data(capacity: listenSocket.readBufferSize)
                    
                    do {
                        let bytesRead = try remoteSocketServer?.read(into: &readData)
                        if bytesRead! != 0 {
                            XCTFail("Expected remote server disconnect")
                        }
                        if bytesRead! > 0 {
                            guard let response = String(data: readData, encoding: .utf8) else {
                                print("Error decoding response...")
                                remoteSocketServer?.close()
                                return
                            }
                            
                            if response != "message2" {
                                XCTFail("expected to receive 'message2'")
                            } else {
                                print("Correct message received from local")
                            }
                        }
                        remoteSocketServer?.close()
                    }
                    catch { }
                }
            }
            catch {
                XCTFail("Error listening")
            }
        }

        sleep(1)

        let localConn = TestConnection(robotSocketURL: URL(string: "http://localhost:12345")!)
        let remoteConn = TestConnection(robotSocketURL: URL(string: "http://localhost:12346")!)
        
        TCPPassthroughV2.shared.start(localSocketConn: localConn, remoteSocketConn: remoteConn)
                
        sleep(1)
        
        remoteSocketServer?.close()
        
        sleep(1)
        
        do {
            try localSocketServer?.write(from: "message1")
            XCTFail("write should fail because remote connection was closed")
        } catch { }
        
        sleep(1)
        
        TCPPassthroughV2.shared.stop()

        localSocketServer?.close()
    }
    
    
    static var allTests = [
        ("testRemoteSendToLocalAndLocalSendToRemote", testRemoteSendToLocalAndLocalSendToRemote),
        ("testRemoteSendWhileLocalClosed", testRemoteSendWhileLocalClosed),
        ("testLocalSendWhileRemoteClosed", testLocalSendWhileRemoteClosed),
    ]
}
