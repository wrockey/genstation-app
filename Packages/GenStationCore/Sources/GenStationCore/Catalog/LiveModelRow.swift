// One row of a provider's live model list, reduced to the two fields a merge can use.
//
// Deliberately NOT `GeminiModel` (GenStationApp.swift:84-118). That type is a Gemini wire DTO — it
// carries `name`, `description` and `supportedGenerationMethods`, it lives in the app target, and
// the package may not depend on it. `id` here is Gemini's `shortName` (the API `name` with its
// "models/" prefix stripped), which is the key every other piece of Gemini code uses.
//
// Top-level public *type*, which NamespaceBoundaryTests explicitly permits (see its scope note at
// NamespaceBoundaryTests.swift:16-20); only top-level public *functions* are forbidden.

import Foundation

public struct LiveModelRow: Sendable, Hashable {
    public let id: String
    /// The provider's own name for the model. Optional because a provider may omit it, and because
    /// a caller mapping from a leaner DTO may not have one.
    public let displayName: String?

    public init(id: String, displayName: String?) {
        self.id = id
        self.displayName = displayName
    }
}
