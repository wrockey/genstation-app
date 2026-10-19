import Foundation

/// Whether a model is one we would put in front of a user today.
///
/// It is a **filter, not a deletion**. `Catalog.model(for:)` returns `.dead` and `.superseded`
/// models on purpose: hiding a model from a picker must never break re-running a generation the
/// user already made. Only the selectable/advertised surfaces filter on this —
/// `Catalog.selectable(task:)` (Task 9) and MCP `list_models` (Task 21).
public enum Lifecycle: String, Codable, Sendable, CaseIterable {
    /// Served, and the one we recommend for its family.
    case current
    /// Still served, but a newer model in the same family replaces it. Hidden from pickers,
    /// resolvable forever. `google/veo-3` is the worked example — superseded, not dead.
    case superseded
    /// The API no longer serves it. Kept as a row so history re-run can still resolve the id.
    case dead
}
