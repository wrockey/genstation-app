import Foundation

public struct VideoWorkflowGuide: Sendable {
    public let title: String
    public let summary: String
    public let supportsAudio: Bool
    public let tips: [String]

    public static func guide(for id: String) -> VideoWorkflowGuide? {
        let canonical = Catalog.canonicalID(for: id) ?? id.lowercased()
        if canonical == GrokVideoClient.model {
            return .init(title: "Grok Imagine Video 1.5", summary: "Text or one starting image · 1–15 seconds · 480p, 720p, 1080p", supportsAudio: true,
                tips: ["Describe one clear action and a camera movement.", "An input image anchors the opening frame; describe how it should move.", "The chosen aspect ratio also applies to input images.", "Describe dialogue, ambience, or sound effects when audio is enabled."])
        }
        guard ReleaseModelPolicy.videoIDs.contains(canonical) else { return nil }
        if canonical == "alibaba/wan-3-0-video" {
            return .init(title: "Wan 3.0 Video", summary: "Text or first/last frames · 2–30 seconds · 480p, 720p, 1080p", supportsAudio: true,
                tips: ["Structure the prompt as subject, action, environment, then camera movement.", "With two frames, describe a plausible transition from the first to the last.", "Frame inputs need direct public HTTPS URLs; GenStation can upload them with ImgBB.", "Start with 5 seconds and 480p to evaluate motion before increasing cost."])
        }
        if canonical.contains("seedance-2-") {
            let newer = canonical.hasSuffix("2-5")
            return .init(title: newer ? "Seedance 2.5" : "Seedance 2.0", summary: newer ? "Text or first/last frames · 4–30 seconds · 480p or 720p" : "Text or first/last frames · 4–15 seconds · 480p through 4K", supportsAudio: true,
                tips: ["Describe the action in chronological order; avoid packing many scene changes into a short clip.", "First-frame images determine the aspect ratio. A second image is the ending frame.", "Put dialogue in quotation marks and describe the desired ambience.", newer ? "Current Seedance 2.5 routing rejects reference images containing real people; choose another model for those inputs." : "Use the default provider routing for the broadest supported input handling."])
        }
        if canonical == "minimax/h3-max" {
            return .init(title: "MiniMax H3 Max", summary: "Text or first/last frames · 5–15 seconds · 480p or 768p · native audio", supportsAudio: true,
                tips: ["Start with 5–10 seconds and one clear action.", "Balanced prompt expansion starts faster; Quality spends more time elaborating your prompt.", "Frame images determine the aspect ratio. Use JPEG/PNG, short side above 300 pixels, below 20 MB.", "Describe dialogue and sound explicitly. This endpoint has no audio-off option."])
        }
        if canonical.contains("veo-3.1") {
            return .init(title: canonical.contains("fast") ? "Veo 3.1 Fast" : "Veo 3.1", summary: "4, 6, or 8 seconds · 16:9 or 9:16 · 720p, 1080p, 4K", supportsAudio: true,
                tips: ["Describe subject motion, camera movement, lighting, and sound separately.", "1080p and 4K require an 8-second clip.", "For image-to-video, use a starting frame with a short side of at least 720 pixels.", "Describe a continuous shot; this release does not expose video extension or reference-video inputs."])
        }
        if canonical.contains("kling") {
            return .init(title: "Kling 3 Standard", summary: "3–15 seconds · text-to-video or first/last frames", supportsAudio: true,
                tips: ["Describe a clear subject action and camera movement for a single shot.", "Text-to-video supports 16:9, 9:16, and 1:1. Image-to-video follows the frame image.", "A last frame requires Generate Audio to be off.", "Negative Prompt lists unwanted elements; CFG controls how closely the model follows the prompt."])
        }
        return nil
    }
}
