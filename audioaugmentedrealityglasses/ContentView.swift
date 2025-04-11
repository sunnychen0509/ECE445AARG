import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject var bleReceiver = BLEImageReceiver()
    @State private var analysisResult = "Description will appear here..."
    @State private var isAnalyzing = false
    @State private var speechSynthesizer = AVSpeechSynthesizer() // persistent synthesizer

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

            TextEditor(text: $analysisResult)
                .frame(height: 150)
                .border(Color.gray, width: 1)
                .padding(.horizontal)

            if bleReceiver.isConnected {
                Button(action: {
                    isAnalyzing = true
                    Task {
                        await MainActor.run {
                            bleReceiver.receivedImage = nil
                            analysisResult = "Capturing image..."
                        }

                        bleReceiver.sendCaptureCommand()

                        while bleReceiver.receivedImage == nil {
                            try await Task.sleep(nanoseconds: 100_000_000)
                        }

                        if let imageData = bleReceiver.receivedImage?.jpegData(compressionQuality: 0.8) {
                            do {
                                let result = try await analyzeImage(imageData: imageData)
                                await MainActor.run {
                                    analysisResult = result
                                    speakText(result)
                                }
                            } catch {
                                await MainActor.run {
                                    analysisResult = "Error: \(error.localizedDescription)"
                                    speakText("There was an error analyzing the image.")
                                }
                            }
                        } else {
                            await MainActor.run {
                                analysisResult = "No image data available."
                                speakText("No image data was received.")
                            }
                        }

                        await MainActor.run {
                            isAnalyzing = false
                        }
                    }
                }) {
                    if isAnalyzing {
                        ProgressView()
                    } else {
                        Text("Capture Image")
                    }
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
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
