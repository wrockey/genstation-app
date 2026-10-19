import Foundation

/// What the user is making. This is the axis the studio shell's sidebar selects —
/// the app is about images and video, not about which vendor serves them.
///
/// The raw values are an **agent-facing contract**: the MCP `list_models` tool accepts
/// exactly `"image"` and `"video"` for its `type` filter, and the sidecar's published tool
/// descriptions name them. They may not change.
///
/// `.threeD` lands additively when Trellis/retexturing arrive — nothing here assumes two cases.
public enum CreateTask: String, Codable, CaseIterable, Sendable {
    case image
    case video

    /// Bridges the per-model `isVideo` flag the AI/ML catalog carries.
    public init(isVideo: Bool) {
        self = isVideo ? .video : .image
    }

    /// True when this task produces video. Prefer pattern matching on the case; this
    /// exists for the catalog and MCP payloads, which speak in booleans.
    public var isVideo: Bool { self == .video }
}
