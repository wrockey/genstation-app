import XCTest
@testable import GenStationCore

final class AgentJobDiscoveryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1000)
    private func job(_ id: String, request: String = "panel-1", kind: String = "image", status: String = "awaiting_approval", pending: Bool = false) -> AgentJobSummary {
        AgentJobSummary(id: id, requestID: request, kind: kind, createdAt: date, status: status,
            billing: "unknown", pendingApproval: pending, recoveryAvailable: false, label: "Panel One")
    }
    private func rows(_ value: [String: Any]) -> [[String: Any]] { value["jobs"] as! [[String: Any]] }
    func testPendingUsesDecisionRatherThanStatusAndDoesNotExposePromptOrPaths() throws {
        let result = try AgentJobDiscovery.list(["filter": "pending"], jobs: [job("a"), job("b", pending: true)], now: date.addingTimeInterval(12))
        XCTAssertEqual(rows(result).map { $0["job_id"] as! String }, ["b"])
        let row = try XCTUnwrap(rows(result).first)
        XCTAssertEqual(row["age_seconds"] as? Int, 12)
        XCTAssertEqual(row["approval_state"] as? String, "pending")
        XCTAssertNil(row["prompt"]); XCTAssertNil(row["file_path"])
        XCTAssertEqual(job("a").json(now: date)["approval_state"] as? String, "preparing_review")
    }
    func testPaginationStableAtEqualTimestampsAndQueryBound() throws {
        let jobs = [job("a"), job("b"), job("c")]
        let first = try AgentJobDiscovery.list(["limit": 2], jobs: jobs)
        XCTAssertEqual(rows(first).map { $0["job_id"] as! String }, ["c", "b"])
        let cursor = try XCTUnwrap(first["next_cursor"] as? String)
        let second = try AgentJobDiscovery.list(["cursor": cursor], jobs: jobs)
        XCTAssertEqual(rows(second).map { $0["job_id"] as! String }, ["a"])
        XCTAssertNil(second["next_cursor"])
        XCTAssertThrowsError(try AgentJobDiscovery.list(["cursor": cursor, "filter": "pending"], jobs: jobs))
        // Removed rows cannot be restored by a cursor.
        XCTAssertTrue(rows(try AgentJobDiscovery.list(["cursor": cursor], jobs: [])).isEmpty)
    }
    func testLookupExactIdentityAndCrossKindAmbiguity() throws {
        let jobs = [job("A"), job("B", kind: "video"), job("C", request: "panel-10")]
        XCTAssertThrowsError(try AgentJobDiscovery.lookup(["request_id": "panel-1"], jobs: jobs))
        XCTAssertEqual(try AgentJobDiscovery.lookup(["request_id": "panel-1", "kind": "video"], jobs: jobs), "B")
        XCTAssertEqual(try AgentJobDiscovery.lookup(["job_id": "a"], jobs: jobs), "A")
        XCTAssertThrowsError(try AgentJobDiscovery.lookup(["request_id": "PANEL-1", "kind": "image"], jobs: jobs))
        XCTAssertThrowsError(try AgentJobDiscovery.lookup(["request_id": "panel-1", "job_id": "A"], jobs: jobs))
        XCTAssertEqual(rows(try AgentJobDiscovery.list(["request_id": "panel-1"], jobs: jobs)).count, 2)
    }
    func testAttentionAndMalformedArguments() throws {
        XCTAssertEqual(rows(try AgentJobDiscovery.list(["filter": "attention"], jobs: [job("a", status: "done"), job("b", status: "submission_unknown")])).count, 1)
        for args: [String: Any] in [["limit": true], ["limit": 1.2], ["limit": 101], ["limit": 0], ["filter": "other"], ["cursor": "garbage"], ["kind": "manual"], ["request_id": 2], ["prompt": "private"]] {
            XCTAssertThrowsError(try AgentJobDiscovery.list(args, jobs: []), "\(args)")
        }
    }
    func testLabelDurabilityAndReplayDoesNotChangeIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("jobs.json")
        var ledger = AgentImageLedger()
        let arguments = ["request_label": "Panel One", "prompt": "safe"]
        let first = try ledger.register(requestID: "one", arguments: arguments, at: file)
        ledger = try AgentImageLedger.load(from: file)
        XCTAssertEqual(ledger.jobs[first.id]?.requestLabel, "Panel One")
        XCTAssertEqual(try ledger.register(requestID: "one", arguments: arguments, at: file).id, first.id)
        XCTAssertThrowsError(try ledger.register(requestID: "one", arguments: ["request_label": "Other"], at: file))
        for raw: Any in [true, "", "line\nbreak", String(repeating: "x", count: 129)] {
            XCTAssertThrowsError(try AgentJobDiscovery.label(["request_label": raw]))
        }
    }
}
