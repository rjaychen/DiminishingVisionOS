/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The view shown inside the immersive space.
*/

import RealityKit
import ARKit
import SwiftUI
import RealityKitContent

@MainActor
struct ObjectTrackingRealityView: View {
    @Environment(AppState.self) var appState: AppState
    
    var root = Entity()
    
    @State private var objectVisualizations: [UUID: ObjectAnchorVisualization] = [:]

    var body: some View {
        RealityView { content, attachments in
            content.add(root)
            Task {
                await appState.startTracking(with: root)
            }
            
            if let objectUI = attachments.entity(for: "Charmander") {
                // gets here, but not to the next one...
                objectUI.position = [-0.1, 0, 0]
                if let charmanderEntity = root.findEntity(named: "charmander") {
                    print("here")
                    charmanderEntity.addChild(objectUI)
                }
            }
            
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
        }
        .onDisappear() {
            print("Leaving immersive space.")
            
            for (_, visualization) in appState.objectVisualizations {
                root.removeChild(visualization.entity)
            }
            objectVisualizations.removeAll()
            
            appState.didLeaveImmersiveSpace()
        }
    }
}
