/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's entry point.
*/

import SwiftUI

private enum UIIdentifier {
    static let immersiveSpace = "Object tracking"
}

@main
@MainActor
struct ObjectTrackingApp: App {
    @State private var appState = AppState()
    //@State private var streamAppState = StreamAppState()
    @State private var appModel = AppModel()
    var body: some Scene {
///--------------------------------------------------------------------------------------------
        WindowGroup {
            HomeView(
                appState: appState,
                immersiveSpaceIdentifier: UIIdentifier.immersiveSpace
            )
            
            .task {
                if appState.allRequiredProvidersAreSupported {
                    await appState.referenceObjectLoader.loadBuiltInReferenceObjects()
                }
                await appState.loadShaderGraphMaterials()
            }
        }
        .defaultSize(CGSize(width: 480, height: 480))
        .windowStyle(.plain)
        
        ImmersiveSpace(id: UIIdentifier.immersiveSpace) {
            ObjectTrackingRealityView()
                .environment(appState)
        }
///--------------------------------------------------------------------------------------------
//        WindowGroup {
//            StreamView(
//                appState: streamAppState
//            ).environment(appModel)
//        }
//        
//        ImmersiveSpace(id: appModel.immersiveSpaceID) {
//            StreamImmersiveView(appState: streamAppState)
//                .environment(appModel)
//                .onAppear {
//                    appModel.immersiveSpaceState = .open
//                }
//                .onDisappear {
//                    appModel.immersiveSpaceState = .closed
//                }
//        }
///--------------------------------------------------------------------------------------------
    }
}
