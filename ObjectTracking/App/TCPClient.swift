import Foundation
import RealityFoundation
import Network
import SwiftUI
import CoreGraphics

class TCPClient {
    @Published var receivedImage: CGImage? = nil // MARK: Published vars are strong, this should not be a @State var
    
    var connection: NWConnection?
    let host: NWEndpoint.Host
    let port: NWEndpoint.Port
    
    init(host: String, port: Int) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: UInt16(port))!
    }
    
    func setupConnection() {
        connection = NWConnection(host: host, port: port, using: .tcp)
        
        connection?.stateUpdateHandler = { (newState) in
            switch newState {
            case .ready:
                print("Connected to \(self.host)")
                self.receiveData()
            case .failed(let error):
                print("Failed to connect: \(error)")
                self.connection?.cancel()
            default:
                break
            }
        }
        connection?.start(queue: .main)
    }
    
    func receiveData() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, isComplete, error in
            guard let self = self, error == nil, let content = content else {
                print("Error receiving data: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            // Read the data length
            let dataLength = content.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            print("Expecting array of size: \(dataLength) bytes")
            
            // Now receive the actual array data
            self.connection?.receive(minimumIncompleteLength: Int(dataLength), maximumLength: Int(dataLength)) { dataContent, _, _, dataError in
                guard let dataContent = dataContent, dataError == nil else {
                    print("Error receiving array data: \(dataError?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                // Process received array data
                let intArray = dataContent.withUnsafeBytes {
                    $0.bindMemory(to: UInt8.self).map { $0 }
                }
                //let cgImage = self.texture(bytes: intArray, width: 1920, height: 1080)
//                let width = 1920
//                let height = 1080
//                let pixelData = [UInt8](repeating: 255, count: width * height * 4) // Sample RGBA data
//                
                if let cgImage = self.texture(bytes: intArray, width: 1920, height: 1080) {
                    DispatchQueue.main.async {
                        self.receivedImage = cgImage
                    }
                } else {
                    print("Failed to create CGImage")
                }
                self.receiveData()
            }
        }
    }
    
    ///Creates a CGImage from a byte array: [UInt8] -> CGImage
    func texture(bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 3 // RGB + Alpha
        let rgbaData = CFDataCreate(nil, bytes, bytes.count)!
        let provider = CGDataProvider(data: rgbaData)!
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 24,
                       bytesPerRow: bytesPerRow,
                       space: colorSpace,
                       bitmapInfo: bitmapInfo,
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: .defaultIntent)
    }
    
}
