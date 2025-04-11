import GoogleGenerativeAI
import UIKit

func analyzeImage(imageData: Data) async throws -> String {
    // Configure the API key
    // GenerativeAI.configure()

    // Initialize the model
    let model = GenerativeModel(name: "gemini-2.0-flash", apiKey: "AIzaSyC_U36O4BGv6A-nFjuSJJWoFFUwuQwgMSk")

    // Create the prompt with proper newlines
    let prompt = "\n\nThis should be an image of a plant, in three sentences describe the following: The scientific name of the plant, the coloquial name of the plant, its origin, and a fun fact about the plant. Refrain from adding any prefixes about satisfying my request. If this is not an image of a plant, state 'This does not seem to be a plant, can you take another picture?'"

    // Create ModelContent with parts
        let content = ModelContent(
            parts: [
                .data(mimetype: "image/jpeg", imageData),
                .text(prompt)
            ]
        )

        // Call generateContent with the ModelContent object
        let response = try await model.generateContent([content])

    // Handle response
    guard let text = response.text else {
        throw NSError(domain: "com.you.app", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "No response received"])
    }

    return text
}
