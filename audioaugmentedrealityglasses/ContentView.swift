import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var bleReceiver = BLEImageReceiver()
    @State private var analysisResult = "Description will appear here..."
    @State private var isProcessing = false
    
    // Your Google Cloud TTS API key
    private let ttsAPIKey = "_____"
    
    var body: some View {
        VStack(spacing: 20) {
            // 1) Display the received image
            if let img = bleReceiver.receivedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
            } else {
                Text("Waiting for an image…")
                    .foregroundColor(.secondary)
            }
            
            // 2) Show the analysis or status
            TextEditor(text: $analysisResult)
                .frame(height: 150)
                .border(Color.gray, width: 1)
                .padding(.horizontal)
            
            // 3) Capture & Process button
            if bleReceiver.isConnected {
                Button {
                    Task { await captureAnalyzeSpeakAndSave() }
                } label: {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("Capture Image")
                            .bold()
                    }
                }
                .disabled(isProcessing)
                .padding()
                .background(isProcessing ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            } else {
                Text("Connecting to ESP32…")
                    .foregroundColor(.secondary)
            }
            
            // 🧪 Test Button – Prints Documents path
            Button("Open Documents Folder") {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                print("📁 Documents folder path: \(docs.path)")
            }
            .padding(.top, 10)
        }
        .padding()
    }
    
    // MARK: – Core Flow
    private func captureAnalyzeSpeakAndSave() async {
        isProcessing = true
        
        // 1) Reset UI
        await MainActor.run {
            bleReceiver.receivedImage = nil
            analysisResult = "Capturing image…"
        }
        
        // 2) Trigger BLE capture
        bleReceiver.sendCaptureCommand()
        while bleReceiver.receivedImage == nil {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        // 3) Run Gemini analysis
        guard let data = bleReceiver.receivedImage?
                .jpegData(compressionQuality: 0.8) else {
            await updateUI("No image data received.", speak: "No image data was received.")
            isProcessing = false
            return
        }
        
        do {
            let result = try await analyzeImage(imageData: data)
            await MainActor.run { analysisResult = result }
            speakText(result)
            
            // 4) Save MP3 to Documents/
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let mp3URL = docs.appendingPathComponent("description.mp3")
            
            try await synthesizeTextToMP3(
                text: result,
                apiKey: ttsAPIKey,
                outputURL: mp3URL
            )
            print("✅ MP3 saved to Documents: \(mp3URL.path)")
            
        } catch {
            await updateUI("Error: \(error.localizedDescription)",
                           speak: "There was an error processing the image.")
        }
        
        isProcessing = false
    }
    
    // MARK: – UI + Speech Helper
    @MainActor
    private func updateUI(_ text: String, speak speech: String) {
        analysisResult = text
        speakText(speech)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
