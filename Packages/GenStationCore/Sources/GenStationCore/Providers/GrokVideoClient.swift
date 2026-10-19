import Foundation

/// Native xAI video requests, adapted to the shared queue's existing response contract.
public enum GrokVideoClient {
    public static let model = "grok-imagine-video-1.5"
    public static var generationsURL: URL { GrokClient.baseURL.appendingPathComponent("videos/generations") }
    public static var pollingEndpoint: String { GrokClient.baseURL.appendingPathComponent("videos").absoluteString + "/" }
    public static let aspectRatios = ["16:9", "9:16", "1:1", "4:3", "3:4", "3:2", "2:3"]
    public static let resolutions = ["480p", "720p", "1080p"]

    public static func requestBody(prompt: String, duration: Int, aspectRatio: String,
                                   resolution: String, audio: Bool, imageDataURI: String? = nil) throws -> [String: Any] {
        guard (1...15).contains(duration), aspectRatios.contains(aspectRatio), resolutions.contains(resolution) else {
            throw NSError(domain: "GrokVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a duration from 1–15 seconds and a supported video aspect ratio and resolution."])
        }
        var body: [String: Any] = ["model": model, "prompt": prompt, "duration": duration,
                                  "aspect_ratio": aspectRatio, "resolution": resolution, "generate_audio": audio]
        if let imageDataURI { body["image"] = ["url": imageDataURI] }
        return body
    }

    public static func normalizedResponse(_ data: Data, submission: Bool = false) throws -> Data {
        guard var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "GrokVideo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid Grok video response."])
        }
        if submission {
            body["id"] = body["request_id"]
        } else {
            body["id"] = body["request_id"] ?? ""
            if let status = body["status"] as? String {
                body["status"] = ["pending": "processing", "done": "completed"][status.lowercased()] ?? status.lowercased()
            }
            if let video = body["video"] as? [String: Any], video["respect_moderation"] as? Bool == false {
                body["status"] = "blocked"
                body["video"] = nil
            }
        }
        if let error = body["error"] as? String { body["error"] = ["message": error] }
        return try JSONSerialization.data(withJSONObject: body)
    }
}
