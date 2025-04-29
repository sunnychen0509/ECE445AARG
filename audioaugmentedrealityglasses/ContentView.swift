import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var bleReceiver = BLEImageReceiver()
    @StateObject private var globalFlow = GlobalFlowManager.shared
    @State private var analysisResult = "Description will appear here..."

    private let ttsAPIKey = "_____"

    var body: some View {
        VStack(spacing: 20) {
            if let img = bleReceiver.receivedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
            } else {
                Text("Waiting for an image…")
                    .foregroundColor(.secondary)
            }

            TextEditor(text: $analysisResult)
                .frame(height: 150)
                .border(Color.gray, width: 1)
                .padding(.horizontal)

            Button("Open Documents Folder") {
                let docs = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask).first!
                print("📁 Documents folder path: \(docs.path)")
            }
            .padding(.top, 10)
        }
        .padding()
        .onReceive(bleReceiver.$buttonPressed) { _ in
            guard bleReceiver.isConnected, !globalFlow.isBusy else { return }
            globalFlow.isBusy = true
            Task { await captureAnalyzeSpeakAndSave() }
        }
    }

    private func captureAnalyzeSpeakAndSave() async {
        await MainActor.run {
            bleReceiver.receivedImage = nil
            analysisResult = "Capturing image…"
        }

        while bleReceiver.receivedImage == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let jpegData = bleReceiver.receivedImage?.jpegData(compressionQuality: 0.8) else {
            finishFlow(error: "No image data received.")
            return
        }

        do {
            let resultText = try await analyzeImage(imageData: jpegData)
            await MainActor.run { analysisResult = resultText }
            speakText(resultText)

            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let wavURL = docs.appendingPathComponent("description.wav")
            try await synthesizeTextToWAV(
                text: resultText,
                apiKey: ttsAPIKey,
                wavURL: wavURL,
                sampleRate: 8000,
                channels: 1,
                bitsPerSample: 16
            )

            bleReceiver.sendCommand("spk_stream")
            try await Task.sleep(nanoseconds: 300_000_000)
            await bleReceiver.sendRawPCMChunks(from: wavURL)

            finishFlow()
        } catch {
            finishFlow(error: error.localizedDescription)
        }
    }

    @MainActor
    private func finishFlow(error: String? = nil) {
        if let err = error {
            analysisResult = "Error: \(err)"
            speakText(analysisResult)
        }
        globalFlow.isBusy = false
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
