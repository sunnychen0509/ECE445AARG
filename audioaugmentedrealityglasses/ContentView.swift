import SwiftUI

struct ContentView: View {
    @StateObject var bleReceiver = BLEImageReceiver()
    
    var body: some View {
        VStack(spacing: 20) {
            if let image = bleReceiver.receivedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
            } else {
                Text("Waiting for an image (Praying won't help LOL)...")
                    .foregroundColor(.secondary)
            }
            
            // Only show the button if the device is connected.
            if bleReceiver.isConnected {
                Button(action: {
                    bleReceiver.sendCaptureCommand()
                }) {
                    Text("Capture Image")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            } else {
                Text("Connecting to ESP32...")
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
