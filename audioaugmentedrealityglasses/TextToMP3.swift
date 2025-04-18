import Foundation

/// Sends `text` to Google Cloud TTS and writes back an MP3 file at `outputURL`.
func synthesizeTextToMP3(text: String,
                         apiKey: String,
                         outputURL: URL) async throws {
    // 1. Build the REST URL
    guard let url = URL(string:
        "https://texttospeech.googleapis.com/v1/text:synthesize?key=_____"
    ) else {
        throw URLError(.badURL)
    }
    
    // 2. Construct the JSON payload
    let payload: [String: Any] = [
        "input": ["text": text],
        "voice": [
            "languageCode": "en-US",
            "ssmlGender": "FEMALE"
        ],
        "audioConfig": [
            "audioEncoding": "MP3"
        ]
    ]
    let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
    
    // 3. Create the request
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    
    // 4. Perform the network call
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "TTS", code: 0,
                      userInfo: [NSLocalizedDescriptionKey: errorString])
    }
    
    // 5. Parse the JSON response
    guard
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let audioContent = json["audioContent"] as? String,
        let audioData = Data(base64Encoded: audioContent)
    else {
        throw NSError(domain: "TTS", code: 0,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }
    
    // 6. Write out the MP3 file
    try audioData.write(to: outputURL)
}
