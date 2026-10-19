import Foundation

/// One model, once. Supersedes `AIMLModel` + `EnhancedModel`.
///
/// Two things this fixes by construction. `id` is the **canonical key**, where `AIMLModel.id` was
/// whatever spelling the caller passed — `ModelRegistry.swift:2087-2088` looks up
/// `registry[lowerID]` but then calls `make(id)` with the original string, so an alias resolved to
/// a model whose `.id` was the alias, in the caller's own casing. And `task: CreateTask` replaces
/// `isVideo: Bool` with the enum whose raw values are the MCP `list_models` type filter; `isVideo`
/// survives as a computed view, so the two can no longer disagree.
public struct CatalogModel: Sendable, Hashable, Codable {

    // MARK: Identity

    /// **Always the lowercased canonical key.** Never the caller's spelling.
    public let id: String
    /// Other lowercased ids that resolve to this model. Empty until the alias collapse (Task 11),
    /// and always empty on a synthesized row.
    public let aliases: [String]
    public let provider: Provider

    // MARK: Presentation

    public let displayName: String
    public let family: String
    public let lifecycle: Lifecycle
    /// Typical **wall-clock generation time** — how long a job takes to come back, 60…480 s.
    /// Per-model data, hand-authored (design § 3.5). Nothing in this repository can falsify it —
    /// and unlike `displayName` and `family`, which the captured `/models` fixture now seeds, nothing
    /// outside it can either: neither `aiml-models-response.json` nor `aiml-model-schemas.json`
    /// carries a duration, a wall-clock or a price field. This is the stage's hardest blind spot;
    /// `CatalogWallClockTests` only proves the table is internally consistent and matches what the
    /// app showed on 2026-07-27.
    ///
    /// **Not output clip length.** Clip length is 5–15 s, it is the `duration` row in the model's
    /// `ParamDescriptor` table, and it is never a catalog field. One value cannot be both, which is
    /// why this property is not called `typicalDuration`.
    ///
    /// `nil` for every non-video model — `CatalogWallClockTests` forbids otherwise — and for the
    /// two video families with no published or observed figure, where the Jobs panel and
    /// `VideoJobFormat.progressLine` degrade to elapsed + provider status.
    ///
    /// These are estimates, not measurements. The predecessor's comment claimed history stored
    /// actual durations; it does not. `HistoryItem`'s 22 stored fields include no duration and no
    /// completion timestamp, and `VideoJob.createdAt`/`startedAt` (`JobQueue.swift:52-53`) live in
    /// memory only. Persisting one is an on-disk format change and Stage 4 owns that surface.
    public let typicalWallClock: ClosedRange<TimeInterval>?

    /// False only for rows from `Catalog.synthesized(for:)`. This is what an "unregistered" badge
    /// reads. `lifecycle` cannot carry it: a synthesized model has no lifecycle we know.
    public let isRegistered: Bool
    /// Non-nil only for a row the vendor currently serves broken, per a live probe (Task 4,
    /// 2026-08-11). `nil` for every other row, including on decode when the field is absent from
    /// an older persisted payload — this is the compatibility story for adding an optional field to
    /// a `Codable` struct, so it needs no custom `init(from:)`. This is what the `.knownIssue` badge
    /// reads.
    public let knownIssue: String?

    // MARK: Capability — AIMLModel's 14 fields, semantics unchanged

    public let task: CreateTask
    public let isI2I: Bool
    public let requiresInputImage: Bool
    /// True only for the OpenAI gpt-image models that accept a binary mask on `/v1/images/edits`.
    /// Also drives the `/edits` routing for i2i — see
    /// `AIMLEndpoints.imageEndpoint(supportsMask:hasInputImages:)` at `AIMLEndpoints.swift:61-63`.
    public let supportsMask: Bool
    public let maxInputImages: Int
    public let imageInputParam: String
    public let secondImageParam: String?
    public let acceptsMultiImages: Bool
    public let acceptsBase64: Bool
    public let acceptsPublicURL: Bool
    public let acceptsBinary: Bool
    public let generationEndpoint: String
    public let pollingEndpoint: String?

    public var isVideo: Bool { task == .video }

    /// Spelled out rather than left implicit: the memberwise initialiser of a `public struct` is
    /// internal, and both the generated rows and the app target construct these values.
    public init(id: String, aliases: [String], provider: Provider,
                displayName: String, family: String, lifecycle: Lifecycle,
                typicalWallClock: ClosedRange<TimeInterval>?, isRegistered: Bool,
                task: CreateTask, isI2I: Bool, requiresInputImage: Bool, supportsMask: Bool,
                maxInputImages: Int, imageInputParam: String, secondImageParam: String?,
                acceptsMultiImages: Bool, acceptsBase64: Bool, acceptsPublicURL: Bool,
                acceptsBinary: Bool, generationEndpoint: String, pollingEndpoint: String?,
                knownIssue: String? = nil) {
        self.id = id
        self.aliases = aliases
        self.provider = provider
        self.displayName = displayName
        self.family = family
        self.lifecycle = lifecycle
        self.typicalWallClock = typicalWallClock
        self.isRegistered = isRegistered
        self.knownIssue = knownIssue
        self.task = task
        self.isI2I = isI2I
        self.requiresInputImage = requiresInputImage
        self.supportsMask = supportsMask
        self.maxInputImages = maxInputImages
        self.imageInputParam = imageInputParam
        self.secondImageParam = secondImageParam
        self.acceptsMultiImages = acceptsMultiImages
        self.acceptsBase64 = acceptsBase64
        self.acceptsPublicURL = acceptsPublicURL
        self.acceptsBinary = acceptsBinary
        self.generationEndpoint = generationEndpoint
        self.pollingEndpoint = pollingEndpoint
    }
}
