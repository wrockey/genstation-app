import Foundation

/// One of the four backends GenStation can talk to.
///
/// This was `GenerationMode`, an enum that doubled as top-level navigation. It is now a
/// property of a model: it selects which credential and which client a request uses, and
/// never selects a screen. `CreateTask` is what the user navigates by.
///
/// The raw values are a **file-format contract** — they are persisted as
/// `HistoryItem.mode` in `history_v2.json` and inside exported history packages. Cases may
/// only ever be added; renaming or removing one silently invalidates existing files.
public enum Provider: String, Codable, CaseIterable, Sendable {
    case gemini
    case comfyUI
    case grok
    case aimlapi

    /// The provider's name as the UI already spells it — settings-panel titles, help
    /// sheet titles and progress copy all built this string by hand before.
    ///
    /// Not interchangeable with `rawValue`: image metadata writes
    /// `rawValue.capitalized` (which yields "Comfyui"), and changing that would alter
    /// what gets embedded in already-shipped output files.
    public var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .comfyUI: return "ComfyUI"
        case .grok: return "Grok"
        case .aimlapi: return "AI/ML API"
        }
    }
}
