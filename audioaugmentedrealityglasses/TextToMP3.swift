import Foundation
import AVFoundation

/// Calls Google TTS requesting LINEAR16 PCM, then writes a RIFF/WAVE file at wavURL.
func synthesizeTextToWAV(text: String,
                         apiKey: String,
                         wavURL: URL,
                         sampleRate: Int,
                         channels: Int,
                         bitsPerSample: Int) async throws {
    // 1) Build the request
    guard let url = URL(string:
        "https://texttospeech.googleapis.com/v1/text:synthesize?key=_____"
    ) else {
        throw URLError(.badURL)
    }
    let payload: [String: Any] = [
        "input": ["text": text],
        "voice": ["languageCode": "en-US", "ssmlGender": "FEMALE"],
        "audioConfig": [
            "audioEncoding": "LINEAR16",
            "sampleRateHertz": sampleRate,
            "speakingRate": 1.0
        ]
    ]
    let body = try JSONSerialization.data(withJSONObject: payload)
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    req.httpBody = body

    // 2) Fetch the base64-encoded PCM
    let (data, urlResponse) = try await URLSession.shared.data(for: req)
    guard let httpResponse = urlResponse as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
        let msg = String(data: data, encoding: .utf8) ?? "unknown"
        throw NSError(domain: "TTS",
                      code: status,
                      userInfo: [NSLocalizedDescriptionKey: msg])
    }
    guard
        let json = try JSONSerialization.jsonObject(with: data) as? [String:Any],
        let b64 = json["audioContent"] as? String,
        let pcm = Data(base64Encoded: b64)
    else {
        throw NSError(domain: "TTS",
                      code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid TTS response"])
    }

    // 3) Build the WAV header
    let byteRate = sampleRate * channels * bitsPerSample/8
    let blockAlign = channels * bitsPerSample/8
    let dataSize = pcm.count

    var header = Data()
    header.append("RIFF".data(using:.ascii)!)                           // ChunkID
    header.append(UInt32(36 + dataSize).littleEndianData)               // ChunkSize
    header.append("WAVE".data(using:.ascii)!)                           // Format
    header.append("fmt ".data(using:.ascii)!)                           // Subchunk1ID
    header.append(UInt32(16).littleEndianData)                          // Subchunk1Size
    header.append(UInt16(1).littleEndianData)                           // AudioFormat = PCM
    header.append(UInt16(channels).littleEndianData)                    // NumChannels
    header.append(UInt32(sampleRate).littleEndianData)                  // SampleRate
    header.append(UInt32(byteRate).littleEndianData)                    // ByteRate
    header.append(UInt16(blockAlign).littleEndianData)                  // BlockAlign
    header.append(UInt16(bitsPerSample).littleEndianData)               // BitsPerSample
    header.append("data".data(using:.ascii)!)                           // Subchunk2ID
    header.append(UInt32(dataSize).littleEndianData)                    // Subchunk2Size

    // 4) Write WAV file (header + PCM)
    try (header + pcm).write(to: wavURL, options: .atomic)
}

// Helpers to make little-endian Data
private extension UInt16 {
    var littleEndianData: Data {
        var v = self.littleEndian
        return Data(bytes: &v, count: 2)
    }
}
private extension UInt32 {
    var littleEndianData: Data {
        var v = self.littleEndian
        return Data(bytes: &v, count: 4)
    }
}
