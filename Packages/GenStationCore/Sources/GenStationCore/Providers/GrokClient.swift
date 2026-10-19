import Foundation

/// Everything GenStation knows about talking to xAI. The base URL and the three endpoint
/// paths were previously spelled out at six call sites across view, settings and command code.
public enum GrokClient {

    public static let baseURL = URL(string: "https://api.x.ai/v1")!

    public static var imageGenerationsURL: URL {
        baseURL.appendingPathComponent("images/generations")
    }

    public static var imageEditsURL: URL {
        baseURL.appendingPathComponent("images/edits")
    }

    public static func supportsEditing(model: String) -> Bool {
        model == "grok-imagine-image-2.0"
    }

    /// Used by the three key-validation probes and nothing else.
    public static var modelsURL: URL {
        baseURL.appendingPathComponent("models")
    }

    /// Used by the prompt enhancer.
    public static var chatCompletionsURL: URL {
        baseURL.appendingPathComponent("chat/completions")
    }

    public static func authorizationHeader(apiKey: String) -> (name: String, value: String) {
        ("Authorization", "Bearer \(apiKey)")
    }

    /// Builds the image-generation body.
    ///
    /// `aspectRatio` and `resolution` are sent **only** for the `grok-imagine-*` family; the
    /// legacy `grok-2-image-*` models reject them with a 400.
    public static func imageRequestBody(
        model: String,
        prompt: String,
        aspectRatio: String,
        resolution: String,
        imageDataURI: String? = nil
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": 1,
            "response_format": "b64_json",
        ]
        if model.hasPrefix("grok-imagine") {
            body["aspect_ratio"] = aspectRatio
            body["resolution"] = resolution
        }
        if let imageDataURI, supportsEditing(model: model) {
            body["image"] = ["url": imageDataURI, "type": "image_url"]
        }
        return body
    }
}
