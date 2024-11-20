//
//  ImmersiveView.swift
//  AVPHttpServer
//
//  Created by I3T Duke on 6/27/24.
//

import SwiftUI
import RealityKit
import RealityKitContent
import Combine

struct StreamImmersiveView: View {
    @State var appState: StreamAppState
    @State private var model = AppModel()
    
    let drawableQueue = try! TextureResource.DrawableQueue(.init(pixelFormat: .bgra8Unorm, width: 1920, height: 1080, usage: [.renderTarget, .shaderRead, .shaderWrite], mipmapsMode: .none))
    let context = CIContext()
    @State private var cancellables = Set<AnyCancellable>()
    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            content.add(appState.setupContentEntity())
            do {
                var dynamicMaterial = try await ShaderGraphMaterial(named: "/Root/DynamicMaterial", from: "Fresnel", in: realityKitContentBundle)
                            
                let color = CIImage(color: .red).cropped(to: CGRect(origin: .zero, size: .init(width: 1920, height: 1080)))
                let image = context.createCGImage(color, from: color.extent)!
                            
                let resource = try await TextureResource(image: image, options: .init(semantic: .color))
                                            
                resource.replace(withDrawables: drawableQueue)
                            
                try dynamicMaterial.setParameter(name: "DiffuseColorImageInput", value: .textureResource(resource))
                            
                let plane = Entity()
                let planeResource = MeshResource.generatePlane(width: 1.92, height: 1.08)
                plane.components.set(ModelComponent(mesh: planeResource, materials: [dynamicMaterial]))
                plane.transform.translation = [0, 1.6, -1]
                content.add(plane)
                            
            } catch {
                fatalError(error.localizedDescription)
            }
        }.onAppear() {
            appState.client.setupConnection()
            Task {
                Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { output in
                    do {
                        let nextDrawable = try drawableQueue.nextDrawable()
                        
                        let ciImage = CIImage(cgImage: appState.client.receivedImage!)
                        let transform = CGAffineTransform.identity.scaledBy(x: 1, y: -1).translatedBy(x: 0, y: ciImage.extent.height)
                        let image = ciImage.transformed(by: transform)
                        context.render(image, to: nextDrawable.texture, commandBuffer: nil, bounds: image.extent, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
                                        
                        nextDrawable.present()
                    } catch {
                        print("Failed to update image.")
                        print(error.localizedDescription)
                    }
                }.store(in: &cancellables)
            }
        }
        .onDisappear() {
            appState.client.connection?.cancel()
            appState.contentEntity.removeFromParent()
            for cancellable in cancellables {
                cancellable.cancel()
            }
        }
    }
}

#Preview(immersionStyle: .mixed) {
    let appState = StreamAppState()
    StreamImmersiveView(
        appState: appState
    ).environment(AppModel())
}
