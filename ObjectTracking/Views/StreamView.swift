import SwiftUI

struct StreamView: View {
    @State var appState: StreamAppState
    
    var body: some View {
        VStack {
            ToggleImmersiveSpaceButton()
            if let cgImage = appState.client.receivedImage {
                Image(uiImage: UIImage(cgImage: cgImage))
                    .resizable()
                    .scaledToFit()
            } else {
                Image(uiImage: UIImage(named: "catsquare")!)
                    .resizable()
                    .frame(width: 300, height: 300)
            }
        }
        .padding()
        .onChange(of: appState.client.receivedImage) {
            print("Image updated: \(String(describing: appState.client.receivedImage))")
        }
    }
    
}
