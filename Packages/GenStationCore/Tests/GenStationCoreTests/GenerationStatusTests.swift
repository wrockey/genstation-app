import XCTest
@testable import GenStationCore

final class GenerationStatusTests: XCTestCase {

    /// Every string the untyped `HistoryItem.status` ever wrote, with the write site.
    private static let legacyVocabulary: [(raw: String, status: GenerationStatus)] = [
        ("queued", .queued),          // JobQueue.swift:538
        ("waiting", .waiting),        // provider passthrough, JobQueue.swift:748
        ("generating", .generating),  // provider passthrough
        ("active", .active),          // provider passthrough
        ("processing", .processing),  // provider passthrough
        ("completed", .completed),    // JobQueue.swift:956, :1147
        ("failed", .failed),          // JobQueue.swift, ~10 sites
        ("blocked", .blocked),        // JobQueue.swift:691, Sora moderation
        ("timeout", .timeout),        // JobQueue.swift:817
        ("expired", .expired),        // JobQueue.swift:347, age > 24h
        ("cancelled", .cancelled),    // JobQueue.swift:434
    ]

    func testEveryLegacyStringParsesToItsCase() {
        for (raw, expected) in Self.legacyVocabulary {
            XCTAssertEqual(GenerationStatus(legacy: raw), expected, "parsing \(raw)")
        }
    }

    /// The on-disk contract: what we write must be what the old build wrote.
    func testWireValueReproducesTheLegacyStringExactly() {
        for (raw, status) in Self.legacyVocabulary {
            XCTAssertEqual(status.wireValue, raw, "wireValue of \(status)")
        }
    }

    func testUnknownStatusPreservesTheRawStringVerbatim() {
        let status = GenerationStatus(legacy: "in_queue")
        XCTAssertEqual(status, .unknown("in_queue"))
        XCTAssertEqual(status.wireValue, "in_queue")
        // Foundation's `.capitalized` treats `_` as a word boundary, so this is "In_Queue",
        // not "In_queue" — and that is exactly what the pre-typed UI rendered, because it
        // called `.capitalized` on the same raw string. Verified empirically.
        XCTAssertEqual(status.displayLabel, "In_Queue")
    }

    /// Providers have returned mixed casing; parsing folds it, encoding normalizes it.
    func testParsingIsCaseInsensitiveAndNormalizesOnReEncode() {
        XCTAssertEqual(GenerationStatus(legacy: "Completed"), .completed)
        XCTAssertEqual(GenerationStatus(legacy: "GENERATING"), .generating)
        XCTAssertEqual(GenerationStatus(legacy: "Completed").wireValue, "completed")
    }

    /// Must equal VideoJobStatus.inProgress exactly — the set Task 8 deletes.
    /// `processing` belongs here: it is a healthy transient, not a failure.
    func testInProgressSetMatchesTheDeletedVideoJobStatusSet() {
        let expected = Set(["queued", "waiting", "generating", "active", "processing"])
        XCTAssertEqual(Set(GenerationStatus.inProgressCases.map(\.wireValue)), expected)
        for (raw, status) in Self.legacyVocabulary {
            XCTAssertEqual(status.isInProgress, expected.contains(raw), "isInProgress of \(raw)")
        }
    }

    /// Must equal JobsPanelView.attentionStatuses exactly (it gates Retry).
    func testAttentionSetMatchesTheJobsPanelSet() {
        XCTAssertEqual(Set(GenerationStatus.attentionCases.map(\.wireValue)),
                       Set(["timeout", "expired", "failed", "blocked"]))
    }

    /// JobsPanelView.isTerminal is `!activeStatuses.contains(s)`, so an unrecognized
    /// status counts as terminal — preserve that rather than inventing a fourth state.
    func testUnknownStatusIsTerminal() {
        XCTAssertTrue(GenerationStatus.unknown("weird").isTerminal)
        XCTAssertFalse(GenerationStatus.unknown("weird").isInProgress)
        XCTAssertFalse(GenerationStatus.unknown("weird").needsAttention)
        XCTAssertFalse(GenerationStatus.completed.isInProgress)
        XCTAssertTrue(GenerationStatus.completed.isTerminal)
    }

    /// The agent-facing contract published in tools/genstation-mcp/main.swift:100 —
    /// exactly queued / generating / done / failed. Note "done", not "completed".
    func testMCPWireValueMatchesThePublishedFourValueContract() {
        XCTAssertEqual(GenerationStatus.completed.mcpWireValue, "done")
        for status in GenerationStatus.inProgressCases {
            XCTAssertEqual(status.mcpWireValue, "generating", "mcpWireValue of \(status)")
        }
        for status in GenerationStatus.attentionCases {
            XCTAssertEqual(status.mcpWireValue, "failed", "mcpWireValue of \(status)")
        }
        XCTAssertEqual(GenerationStatus.cancelled.mcpWireValue, "failed")
        XCTAssertEqual(GenerationStatus.unknown("weird").mcpWireValue, "failed")
        // Not a key path: Swift key paths cannot address tuple elements.
        let produced = Set(Self.legacyVocabulary.map { $0.status.mcpWireValue })
        XCTAssertTrue(produced.isSubset(of: ["queued", "generating", "done", "failed"]),
                      "produced values outside the frozen contract: \(produced)")
    }

    /// A *persisted* `queued` maps to `generating`, not to the MCP `queued`. This looks
    /// wrong and is not: MCPService derives the MCP `queued` from `VideoJobState`
    /// `.preparing`/`.queued` — the local queue record's own lifecycle, before the POST.
    /// By the time `queued` reaches `HistoryItem.status` the provider has accepted the job
    /// and is working on it, so `generating` is the honest report. Nothing in this type ever
    /// produces the MCP `queued`.
    func testPersistedQueuedMapsToGeneratingNotToTheMCPQueued() {
        XCTAssertEqual(GenerationStatus.queued.mcpWireValue, "generating")
        XCTAssertFalse(
            Self.legacyVocabulary.map { $0.status.mcpWireValue }.contains("queued"),
            "the MCP 'queued' comes from VideoJobState, never from a persisted status")
    }

    func testCodableRoundTripsAsABareString() throws {
        let data = try JSONEncoder().encode([GenerationStatus.completed, .unknown("odd")])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["completed","odd"]"#)
        XCTAssertEqual(try JSONDecoder().decode([GenerationStatus].self, from: data),
                       [.completed, .unknown("odd")])
    }

    func testDisplayLabelMatchesTheExistingBadgeCopy() {
        // JobsPanelView and ResponseSection both render `status.capitalized` today.
        XCTAssertEqual(GenerationStatus.generating.displayLabel, "Generating")
        XCTAssertEqual(GenerationStatus.timeout.displayLabel, "Timeout")
    }
}
