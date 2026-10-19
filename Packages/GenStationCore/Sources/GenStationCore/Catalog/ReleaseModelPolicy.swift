import Foundation

/// The release support boundary. Catalog history remains readable; only these operations
/// may start a new paid job. Additions require a descriptor and a verified request shape.
public enum ReleaseModelPolicy {
    public static let imageIDs: Set<String> = [
        "openai/gpt-image-2",
        "openai/gpt-image-2.5-flare", "openai/gpt-image-2.5-sunburst",
        "google/gemini-3.1-flash-image-preview",
        "google/gemini-3-pro-image-preview",
        "google/gemini-3-pro-image-preview-edit",
        "bytedance/seedream-5-0-pro",
        "bytedance/seedream-5-0-lite",
        "blackforestlabs/flux-2-max",
    ]
    public static let videoIDs: Set<String> = [
        "alibaba/wan-3-0-video", "bytedance/seedance-2-5", "minimax/h3-max",
        "bytedance/seedance-2-0",
        "google/veo-3.1-t2v", "google/veo-3.1-i2v",
        "google/veo-3.1-t2v-fast", "google/veo-3.1-i2v-fast",
        "kling-video/v3/standard/text-to-video",
        "kling-video/v3/standard/image-to-video",
    ]
    public static let unavailableMessage = "This model or operation is not supported in this release. Choose a model from the supported picker. Your existing history is still available."

    public static func allows(_ id: String, task: CreateTask? = nil) -> Bool {
        guard let model = Catalog.model(for: id), model.provider == .aimlapi,
              model.knownIssue == nil, model.lifecycle != .dead,
              task == nil || model.task == task else { return false }
        return (model.task == .image ? imageIDs : videoIDs).contains(model.id)
    }

    /// Custom JSON and history retries cannot override the supported model or endpoint.
    public static func validateRequest(modelID: String, task: CreateTask,
                                       customPayload: String?, endpoint: String?) -> String? {
        guard allows(modelID, task: task), let model = Catalog.model(for: modelID) else {
            return unavailableMessage
        }
        if let endpoint, endpoint != model.generationEndpoint &&
            !(task == .image && model.acceptsBinary && endpoint == AIMLEndpoints.imagesEditsURL.absoluteString) {
            return "Custom endpoints are disabled for this release. Reset the custom request to use the supported model."
        }
        if let customPayload, !customPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = customPayload.data(using: .utf8),
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "The custom request must be a JSON object."
            }
            if task == .video && !Set(body.keys).isDisjoint(with: ["video_url", "video_urls", "audio_url", "audio_urls", "elements", "multi_prompt"]) {
                return "Video editing, audio-driven generation, and character replacement are not supported in this release. Reset the custom request to generate from a prompt or image."
            }
            if task == .video, let issue = VideoRequestPolicy.payloadIssue(model: model, body: body) { return issue }
            if let raw = body["model"] {
                guard let id = raw as? String, Catalog.canonicalID(for: id) == model.id else {
                    return "The custom request model differs from the selected model. Reset the custom request before generating."
                }
            }
        }
        return nil
    }
}
