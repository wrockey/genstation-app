import Foundation

/// The wire shapes and error formatting shared by every OpenAI-compatible provider
/// GenStation talks to — Grok, AI/ML API and the chat-completions paths of both.
///
/// This is a namespace, not a client: it owns no host and issues no request. The provider
/// clients that do (`AIMLEndpoints`, `GrokClient`, `ImgBBClient`) decode into these types.
public enum OpenAICompatible {

    /// The error envelope shared by every OpenAI-compatible provider.
    public struct ErrorDict: Codable, Sendable {
        public let message: String?
        public let type: String?
        public let code: String?

        public init(message: String?, type: String?, code: String?) {
            self.message = message
            self.type = type
            self.code = code
        }
    }

    /// The image-generation response shape shared by Grok and AI/ML API. Named for the wire
    /// format rather than one provider, because it decodes both — it was `GrokImageResponse`,
    /// which misdescribed two of its three call sites.
    public struct ImageResponse: Codable, Sendable {
        public let created: Int?
        public let data: [ImageData]
        public let error: ErrorDict?
    }

    public struct ImageData: Codable, Sendable {
        public let b64_json: String?
        public let url: String?
        public let revised_prompt: String?
    }

    // MARK: - Error Formatting

    /// Formats errors from OpenAI-compatible APIs (AIML, Grok, etc.) into user-friendly messages
    public static func formatError(_ error: ErrorDict) -> String {
        var message: String

        // Check error type/code for specific handling
        let errorType = error.type?.lowercased() ?? ""
        let errorCode = error.code?.lowercased() ?? ""
        let errorMsg = error.message?.lowercased() ?? ""

        if errorType.contains("content_policy") || errorCode.contains("content_policy") ||
           errorMsg.contains("content policy") || errorMsg.contains("safety") ||
           errorMsg.contains("violation") || errorMsg.contains("inappropriate") {
            message = "Generation blocked for content policy violation."
            if let originalMsg = error.message, !originalMsg.isEmpty {
                message += "\n\nDetails: \(originalMsg)"
            }
            message += "\n\nPlease revise your prompt and try again."
        } else if errorType.contains("rate_limit") || errorCode.contains("rate_limit") ||
                  errorMsg.contains("rate limit") {
            message = "Rate limit exceeded. Please wait a moment before trying again."
        } else if errorType.contains("invalid_request") || errorCode.contains("invalid") {
            message = "Invalid request: \(error.message ?? "Unknown error")"
        } else if errorType.contains("authentication") || errorCode.contains("auth") ||
                  errorMsg.contains("api key") || errorMsg.contains("unauthorized") {
            message = "Authentication error. Please check your API key."
        } else if errorType.contains("model_not_found") || errorMsg.contains("model not found") {
            message = "Model not available. The selected model may not be accessible with your API key."
        } else {
            // Generic error with all available info
            message = error.message ?? "Unknown error"
            if let type = error.type, !type.isEmpty {
                message += "\n\nError type: \(type)"
            }
            if let code = error.code, !code.isEmpty {
                message += "\nError code: \(code)"
            }
        }

        return message
    }
}
