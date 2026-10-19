import Foundation

/// Everything GenStation knows about talking to Google's Generative Language API.
///
/// Gemini authenticates by **query parameter** (`?key=…`) at every call site — a URL produced
/// here therefore contains a secret and must never be logged or shown in an error message.
/// One call site also sends a redundant `x-goog-api-key` header; `apiKeyHeaderName` exists so
/// that site does not spell it out.
public enum GeminiClient {

    public static let supportedImageModels: Set<String> = [
        "gemini-3.1-flash-image", "gemini-3.1-flash-image-preview",
        "gemini-3-pro-image", "gemini-3-pro-image-preview", "gemini-2.5-flash-image"
    ]

    public static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    /// Redundant alongside `?key=`, but one call site sends both and behavior is preserved.
    public static let apiKeyHeaderName = "x-goog-api-key"

    /// `POST` target for a generation. `model` is interpolated with a literal colon before
    /// `generateContent`, which is what the API expects — percent-encoding it 404s.
    public static func generateContentURL(model: String, apiKey: String) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
        components.percentEncodedPath += "/\(model):generateContent"
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        return components.url!
    }

    /// `GET` target for the model list. `pageSize` is set only by the key-validation
    /// probes, which fetch one entry to prove a key works.
    public static func modelsURL(apiKey: String, pageSize: Int? = nil) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if let pageSize { items.append(URLQueryItem(name: "pageSize", value: String(pageSize))) }
        items.append(URLQueryItem(name: "key", value: apiKey))
        components.queryItems = items
        return components.url!
    }

    /// Whether this model accepts `generationConfig.imageConfig.imageSize`.
    ///
    /// **This is the only place the question is answered.** It was answered twice, differently: the
    /// settings view drew its Image Resolution card for `gemini-3`/`pro-image` while the request
    /// builder sent the key for everything except `2.5-flash-image`. The Gemini list is fetched live
    /// and admits any id containing `image` or `vision`, so the set they disagreed on is open, not
    /// enumerable — `gemini-2.0-flash-preview-image-generation` is just the id we can name.
    ///
    /// The narrower — the view's — answer is the one kept, so a control the user cannot see can
    /// never put a key on the wire.
    public static func supportsImageSize(modelID: String) -> Bool {
        let id = modelID.lowercased()
        return id.contains("gemini-3") || id.contains("pro-image")
    }

    public struct Part: Codable {
        public let text: String?
        public let inlineData: InlineData?

        enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }

        public init(text: String? = nil, inlineData: InlineData? = nil) {
            self.text = text
            self.inlineData = inlineData
        }
    }
    public struct InlineData: Codable {
        public let mimeType: String
        public let data: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }

        public init(mimeType: String, data: String) {
            self.mimeType = mimeType
            self.data = data
        }
    }
    public struct Content: Codable {
        public let parts: [Part]

        public init(parts: [Part]) {
            self.parts = parts
        }
    }
    public struct GeminiImageConfig: Codable {
        public let aspectRatio: String?
        public let imageSize: String?

        enum CodingKeys: String, CodingKey {
            case aspectRatio
            case imageSize
        }

        public init(aspectRatio: String? = nil, imageSize: String? = nil) {
            self.aspectRatio = aspectRatio
            self.imageSize = imageSize
        }
    }
    public struct GeminiGenerationConfig: Codable {
        public let responseModalities: [String]?
        public let imageConfig: GeminiImageConfig?

        public init(responseModalities: [String]? = nil, imageConfig: GeminiImageConfig? = nil) {
            self.responseModalities = responseModalities
            self.imageConfig = imageConfig
        }
    }
    public struct GenerateContentRequest: Codable {
        public let contents: [Content]
        public let generationConfig: GeminiGenerationConfig?

        public init(contents: [Content], generationConfig: GeminiGenerationConfig? = nil) {
            self.contents = contents
            self.generationConfig = generationConfig
        }
    }
    public struct GeminiSafetyRating: Codable {
        public let category: String
        public let probability: String
    }
    public struct GeminiPromptFeedback: Codable {
        public let blockReason: String?
        public let safetyRatings: [GeminiSafetyRating]?
    }
    public struct ResponseInlineData: Codable {
        public let mimeType: String
        public let data: String

        enum CodingKeys: String, CodingKey {
            case mimeType
            case data
        }
    }
    public struct NewResponsePart: Codable {
        public let thought: Bool?
        public let text: String?
        public let inlineData: ResponseInlineData?

        enum CodingKeys: String, CodingKey {
            case text
            case inlineData
            case thought
        }
    }
    public struct NewResponseContent: Codable {
        public let parts: [NewResponsePart]?  // May be missing if blocked
    }
    public struct NewCandidate: Codable {
        public let content: NewResponseContent?  // May be missing if generation blocked
        public let finishReason: String?
        public let finishMessage: String?  // User-facing message from Google when blocked
        public let safetyRatings: [GeminiSafetyRating]?
    }
    public struct NewGenerateContentResponse: Codable {
        public let candidates: [NewCandidate]?  // May be missing if prompt blocked
        public let promptFeedback: GeminiPromptFeedback?  // Present when prompt is blocked
    }

    // MARK: - Error Formatting

    /// Formats Gemini block reasons into user-friendly messages
    public static func formatBlockReason(_ reason: String, safetyRatings: [GeminiSafetyRating]?, finishMessage: String? = nil) -> String {
        // If Google provided a finishMessage, use it as the primary message
        if let finishMessage = finishMessage, !finishMessage.isEmpty {
            return finishMessage
        }

        var message: String

        switch reason {
        case "SAFETY":
            message = "Generation blocked for safety reasons."
        case "IMAGE_SAFETY":
            message = "Image generation blocked for safety reasons. The generated image violated content policies."
        case "BLOCK_REASON_UNSPECIFIED":
            message = "Generation blocked (reason unspecified)."
        case "BLOCKLIST":
            message = "Generation blocked due to blocklist match."
        case "PROHIBITED_CONTENT":
            message = "Generation blocked: prohibited content detected."
        case "SPII":
            message = "Generation blocked: sensitive personal information detected."
        case "RECITATION":
            message = "Generation blocked: potential copyright/recitation issue."
        case "OTHER":
            message = "Generation blocked for policy reasons."
        default:
            message = "Generation blocked: \(reason)"
        }

        // Add safety rating details if available
        if let ratings = safetyRatings, !ratings.isEmpty {
            let highRatings = ratings.filter { ["HIGH", "MEDIUM"].contains($0.probability) }
            if !highRatings.isEmpty {
                let categories = highRatings.map { rating -> String in
                    let category = rating.category
                        .replacingOccurrences(of: "HARM_CATEGORY_", with: "")
                        .replacingOccurrences(of: "_", with: " ")
                        .lowercased()
                        .capitalized
                    return "\(category) (\(rating.probability.lowercased()))"
                }
                message += "\n\nTriggered categories: \(categories.joined(separator: ", "))"
            }
        }

        message += "\n\nPlease revise your prompt and try again."
        return message
    }
}
