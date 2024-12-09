import RealityKit
import ARKit
import SwiftUI
import RealityKitContent
import Combine

@MainActor
struct ObjectTrackingRealityView: View {
    @Environment(AppState.self) var appState: AppState
    
    var root = Entity()
    
    @State private var objectVisualizations: [UUID: ObjectAnchorVisualization] = [:]

    let drawableQueue = try! TextureResource.DrawableQueue(.init(pixelFormat: .bgra8Unorm, width: 1920, height: 1080, usage: [.renderTarget, .shaderRead, .shaderWrite], mipmapsMode: .none))
    let context = CIContext()
    @State private var cancellables = Set<AnyCancellable>()
    @State private var plane = Entity()
    
    var body: some View {
        RealityView { content, attachments in
            content.add(root)
            Task {
                await appState.startTracking(with: root)
            }
            // MARK: TODO, Check to see if TCP Connection has been started in the first place
//            if let objectUI = attachments.entity(for: "Charmander") {
//                // gets here, but not to the next one...
//                objectUI.position = [-0.1, 0, 0]
//                if let charmanderEntity = root.findEntity(named: "charmander") {
//                    print("here")
//                    charmanderEntity.addChild(objectUI)
//                }
//            }
            
        } placeholder: {
            ProgressView()
        } attachments: {
            Attachment(id: "Charmander") {
                Text("Charmander")
                    .font(.extraLargeTitle)
                    .padding()
                    .glassBackgroundEffect()
            }
        }
        .onAppear() {
            print("Entering immersive space.")
            appState.isImmersiveSpaceOpened = true
            appState.client.setupConnection()
//            Task {
//                // Update CIImage given to plane every 100 ms
//                Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { output in
//                    do {
//                        let nextDrawable = try drawableQueue.nextDrawable()
//                        
//                        if let cgImage = appState.client.receivedImage {
//                            let ciImage = CIImage(cgImage: cgImage)
//                            let transform = CGAffineTransform.identity.scaledBy(x: 1, y: -1).translatedBy(x: 0, y: ciImage.extent.height)
//                            let image = ciImage.transformed(by: transform)
//                            context.render(image, to: nextDrawable.texture, commandBuffer: nil, bounds: image.extent, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
//                            
//                            nextDrawable.present()
//                        }
//                    } catch {
//                        print("Failed to update image.")
//                        print(error.localizedDescription)
//                    }
//                }.store(in: &cancellables)
//            }
        }
        
        .onDisappear() {
            print("Leaving immersive space.")
            
            appState.client.connection?.cancel()
            for cancellable in cancellables {
                cancellable.cancel()
            }
            
//            for (_, visualization) in appState.objectVisualizations {
//                root.removeChild(visualization.entity)
//            }
            for child in root.children {
                root.removeChild(child)
            }
            objectVisualizations.removeAll()
            
            
            appState.didLeaveImmersiveSpace()
        }
    }
}
