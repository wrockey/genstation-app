import Foundation
import CryptoKit

/// Identifies canonical bytes independently of their current path or History folder.
/// Seed and parameter metadata are supplied only when the submitting contract knows them.
public struct AgentAssetManifest: Codable, Equatable, Sendable {
    public let assetID: UUID
    public let sha256: String
    public let byteCount: Int
    public let mediaType: String
    public let width: Int?
    public let height: Int?
    public let model: String?
    public let promptFingerprint: String
    public let promptFingerprintScope: String?
    public let parametersJSON: String?
    public let seed: String?

    public init(assetID: UUID, data: Data, mediaType: String, width: Int?, height: Int?, model: String?, prompt: String, parametersJSON: String? = nil, seed: String? = nil, promptFingerprint: String? = nil, fingerprintScope: String = "effective_prompt") {
        self.assetID = assetID; self.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        self.byteCount = data.count; self.mediaType = mediaType; self.width = width; self.height = height
        self.model = model; self.promptFingerprint = promptFingerprint ?? SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        self.promptFingerprintScope = fingerprintScope
        self.parametersJSON = parametersJSON; self.seed = seed
    }
    public var json: [String: Any] {
        var result: [String: Any] = ["asset_id": assetID.uuidString, "sha256": sha256, "byte_count": byteCount,
            "media_type": mediaType, "canonical": true, "model_status": model == nil ? "unknown" : "known", "prompt_fingerprint": promptFingerprint,
            "seed_status": seed == nil ? "unknown" : "known", "parameters_status": parametersJSON == nil ? "unknown" : "known",
            "dimensions_status": width != nil && height != nil ? "known" : "unavailable"]
        result["prompt_fingerprint_scope"] = promptFingerprintScope ?? "unknown"
        if let model { result["model"] = model }
        if let width, let height { result["dimensions"] = [width, height] }
        if let seed { result["seed"] = seed; result["seed_source"] = "submitted_parameter" }
        if let text = parametersJSON, let data = text.data(using: .utf8), let parameters = try? JSONSerialization.jsonObject(with: data) { result["effective_parameters"] = parameters }
        return result
    }
}
