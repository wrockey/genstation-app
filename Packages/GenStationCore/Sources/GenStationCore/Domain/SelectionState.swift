import Foundation

/// What GenStation restores on launch: which backend the form was pointed at, whether the
/// user was making images or video, and the last model chosen for each provider.
///
/// None of this was persisted before — the app reopened on Gemini/image every time, and each
/// provider's model was re-derived from a cache or a hardcoded default. There is therefore no
/// legacy key to migrate; this is new state.
///
/// Versioning follows `MCPStateStore`: the `schemaVersion` lives *inside* the payload, so the
/// blob is self-describing, and decoding never throws. An envelope this build does not
/// understand is rejected whole and the caller falls back to `defaults` — losing a restored
/// selection costs the user one click, whereas partially applying an unknown schema is how
/// settings corruption starts.
///
/// `provider` is transitional. Stage 5's sidebar navigates by `task`, and the provider follows
/// from the chosen model; this field goes away with the provider tab row.
public struct SelectionState: Codable, Equatable, Sendable {

    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var provider: Provider
    public var task: CreateTask
    /// `Provider.rawValue` -> last model id chosen for that provider. Keyed by raw value so
    /// the persisted JSON stays readable and a new provider case cannot invalidate the blob.
    public var modelByProvider: [String: String]

    public init(
        schemaVersion: Int = SelectionState.currentSchemaVersion,
        provider: Provider = .gemini,
        task: CreateTask = .image,
        modelByProvider: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.provider = provider
        self.task = task
        self.modelByProvider = modelByProvider
    }

    /// The launch state the app had before it persisted anything.
    public static let defaults = SelectionState()

    public func model(for provider: Provider) -> String? {
        modelByProvider[provider.rawValue]
    }

    /// Returns a copy with `id` recorded for `provider`. An empty id records nothing —
    /// `selectedAIMLModel` starts empty and that is "no selection", not a selection.
    public func settingModel(_ id: String, for provider: Provider) -> SelectionState {
        guard !id.isEmpty else { return self }
        var copy = self
        copy.modelByProvider[provider.rawValue] = id
        return copy
    }

    /// Reads a persisted blob. Returns nil — never throws, never partially applies — for
    /// absent, corrupt, or future-versioned data.
    public static func decode(_ data: Data?) -> SelectionState? {
        guard let data, !data.isEmpty,
              let decoded = try? JSONDecoder().decode(SelectionState.self, from: data),
              decoded.schemaVersion == currentSchemaVersion
        else { return nil }
        return decoded
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
