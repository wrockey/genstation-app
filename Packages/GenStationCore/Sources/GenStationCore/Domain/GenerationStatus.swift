import Foundation

/// The lifecycle state of one generation, typed.
///
/// This replaces the free `String?` that `HistoryItem.status` carried. Two wire contracts
/// constrain it and neither may be broken:
///
/// 1. **On-disk.** `wireValue` reproduces, character for character, the eleven strings the
///    untyped field wrote into `history_v2.json`, so an existing file round-trips and an
///    older build can still read a file this build wrote.
/// 2. **Agent-facing.** `mcpWireValue` is one of `queued / generating / done / failed` — the
///    four values the sidecar's `get_job_status` description publishes. Note `done`, not
///    `completed`.
///
/// An unrecognized provider string decodes to `.unknown(raw)` rather than throwing or being
/// dropped. Throwing would destroy the history file; dropping silently abandons a live job.
public enum GenerationStatus: Equatable, Hashable, Sendable {
    // In-progress family — the provider is still working.
    case queued
    case waiting
    case generating
    case active
    case processing
    // Terminal success.
    case completed
    // Terminal failure family.
    case failed
    case blocked
    case timeout
    case expired
    case cancelled
    /// A status this build does not recognize, preserved verbatim so nothing is lost and
    /// the badge can still show what the provider actually said.
    case unknown(String)

    /// Statuses meaning "the provider is still working". `processing` belongs here — it is a
    /// healthy transient, not a failure. Was `VideoJobStatus.inProgress`.
    public static let inProgressCases: [GenerationStatus] = [
        .queued, .waiting, .generating, .active, .processing,
    ]

    /// Terminal states that want the user's attention — they gate the Retry and re-download
    /// affordances in the Jobs panel.
    public static let attentionCases: [GenerationStatus] = [.timeout, .expired, .failed, .blocked]

    public var isInProgress: Bool { Self.inProgressCases.contains(self) }

    public var needsAttention: Bool { Self.attentionCases.contains(self) }

    /// Anything not actively working is terminal, `.unknown` included — matching what the
    /// Jobs panel concluded from set membership before this type existed.
    public var isTerminal: Bool { !isInProgress }

    /// The exact string this status persists as.
    public var wireValue: String {
        switch self {
        case .queued: return "queued"
        case .waiting: return "waiting"
        case .generating: return "generating"
        case .active: return "active"
        case .processing: return "processing"
        case .completed: return "completed"
        case .failed: return "failed"
        case .blocked: return "blocked"
        case .timeout: return "timeout"
        case .expired: return "expired"
        case .cancelled: return "cancelled"
        case .unknown(let raw): return raw
        }
    }

    /// Parses a persisted or provider-supplied status.
    ///
    /// Matching is case-insensitive because providers have returned both `generating` and
    /// `Generating`, and the pre-typed reader in `ResponseSection` compared case-sensitively
    /// and mislabelled the capitalized form. Re-encoding normalizes to the canonical
    /// spelling; anything unrecognized keeps its original casing under `.unknown`.
    public init(legacy raw: String) {
        switch raw.lowercased() {
        case "queued": self = .queued
        case "waiting": self = .waiting
        case "generating": self = .generating
        case "active": self = .active
        case "processing": self = .processing
        case "completed": self = .completed
        case "failed": self = .failed
        case "blocked": self = .blocked
        case "timeout": self = .timeout
        case "expired": self = .expired
        case "cancelled": self = .cancelled
        default: self = .unknown(raw)
        }
    }

    /// Status as the MCP `get_job_status` tool reports it. Constrained to four values.
    public var mcpWireValue: String {
        if self == .completed { return "done" }
        if isInProgress { return "generating" }
        return "failed"
    }

    /// Badge text. The Jobs panel and the response header both rendered
    /// `status.capitalized`, so this preserves that copy exactly.
    public var displayLabel: String { wireValue.capitalized }
}

extension GenerationStatus: Codable {
    public init(from decoder: Decoder) throws {
        self.init(legacy: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }
}
