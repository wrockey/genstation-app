import XCTest
@testable import GenStationCore

final class AgentVideoTests: XCTestCase {
    private var model: CatalogModel { Catalog.all.first { $0.isVideo && !$0.requiresInputImage && ReleaseModelPolicy.allows($0.id, task: .video) }! }
    private var args: [String: Any] { ["model": model.id, "prompt": "A lighthouse at sunrise", "request_id": "video-test"] }
    private func file() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("video.json") }

    func testEveryCuratedVideoDefaultBuildsPolicyConformantPayload() throws {
        let models = Catalog.all.filter { $0.isVideo && ReleaseModelPolicy.allows($0.id, task: .video) }
        XCTAssertFalse(models.isEmpty)
        for row in models {
            var args: [String: Any] = ["model": row.id, "prompt": "Lighthouse at sunrise"]
            if row.requiresInputImage { args["input_images"] = ["data:image/png;base64,fixture"] }
            let contract = try AgentVideoContract(args, submitting: false)
            let body = try contract.body(references: contract.inputImages.indices.map { "https://example.com/frame\($0).png" })
            XCTAssertNil(VideoRequestPolicy.payloadIssue(model: row, body: body), row.id)
            XCTAssertEqual(body["model"] as? String, row.id)
        }
    }
    func testStrictVideoRequestIdentityTypesAndBoundaries() throws {
        XCTAssertNoThrow(try AgentVideoContract(args, submitting: true))
        var noID = args; noID.removeValue(forKey: "request_id")
        XCTAssertThrowsError(try AgentVideoContract(noID, submitting: true))
        XCTAssertNoThrow(try AgentVideoContract(noID, submitting: false))
        for (key, value) in [("request_id", true as Any), ("request_id", " "), ("request_id", String(repeating: "a", count: 129)), ("prompt", ""), ("prompt", String(repeating: "é", count: 16_001)), ("params", "bad"), ("input_images", "path"), ("provider", "grok"), ("server_url", "https://example.com")] {
            var invalid = args; invalid[key] = value
            XCTAssertThrowsError(try AgentVideoContract(invalid, submitting: true), key)
        }
        var invalid = args; invalid["params"] = ["arbitrary_option": 2]
        XCTAssertThrowsError(try AgentVideoContract(invalid, submitting: true))
    }
    func testExplicitInvalidParamsAreNotSilentlyDefaulted() {
        for row in Catalog.all where row.isVideo && ReleaseModelPolicy.allows(row.id, task: .video) {
            let properties = AgentVideoContract.schema(row)["properties"] as! [String: [String: Any]]
            for (key, rule) in properties {
                var invalid: [String: Any] = ["model": row.id, "prompt": "lighthouse", "params": [key: ["invalid": true]]]
                if row.requiresInputImage { invalid["input_images"] = ["data:image/png;base64,fixture"] }
                XCTAssertThrowsError(try AgentVideoContract(invalid, submitting: false), "\(row.id) \(key)")
                if ["number", "integer"].contains(rule["type"] as? String ?? "") {
                    invalid["params"] = [key: true]
                    XCTAssertThrowsError(try AgentVideoContract(invalid, submitting: false), "\(row.id) boolean \(key)")
                }
            }
        }
    }
    func testUncertainSubmissionNeverBecomesNewJobOnReplay() throws {
        let f = file(); defer { try? FileManager.default.removeItem(at: f.deletingLastPathComponent()) }
        var ledger = AgentVideoLedger()
        var job = try ledger.register(requestID: "video-test", arguments: args, at: f)
        job.status = "submitting"; job.billing = "unknown"
        try ledger.update(job, at: f)
        var restored = try AgentVideoLedger.load(from: f)
        let replay = try restored.register(requestID: "video-test", arguments: args, at: f)
        XCTAssertEqual(replay.id, job.id); XCTAssertEqual(replay.status, "submission_unknown"); XCTAssertEqual(replay.billing, "unknown")
        XCTAssertNil(replay.history)
        var changed = args; changed["prompt"] = "another video"
        XCTAssertThrowsError(try restored.register(requestID: "video-test", arguments: changed, at: f))
        XCTAssertEqual(restored.jobs.count, 1)
    }
    func testKnownProviderAndOutputSurviveRestartWithoutInputPayloads() throws {
        let f = file(); defer { try? FileManager.default.removeItem(at: f.deletingLastPathComponent()) }
        var ledger = AgentVideoLedger()
        var job = try ledger.register(requestID: "video-test", arguments: args, at: f)
        let item = HistoryItem(prompt: "Lighthouse", date: Date(), mode: .aimlapi, task: .video, modelUsed: model.id,
            jobId: "provider-123", status: .completed, videoUrl: "https://example.com/original.mp4",
            pollingEndpoint: model.pollingEndpoint, customAIMLPayload: "DO-NOT-PERSIST-INPUT-BYTES", costUSD: 1.25, agentGenerated: true)
        job.history = item; job.status = "saving"; job.billing = "reported"
        try ledger.update(job, at: f)
        let restored = try AgentVideoLedger.load(from: f).jobs[job.id]!
        XCTAssertEqual(restored.status, "recoverable")
        XCTAssertEqual(restored.history?.id, item.id); XCTAssertEqual(restored.history?.jobId, "provider-123")
        XCTAssertEqual(restored.history?.videoUrl, item.videoUrl); XCTAssertEqual(restored.history?.costUSD, 1.25)
        XCTAssertNil(restored.history?.customAIMLPayload)
        XCTAssertFalse(try String(contentsOf: f).contains("DO-NOT-PERSIST"))
    }
    func testApprovalInterruptionAndDenialAreNotAutoResumed() throws {
        for state in ["awaiting_approval", "preparing", "denied", "cancelled"] {
            let f = file(); defer { try? FileManager.default.removeItem(at: f.deletingLastPathComponent()) }
            var ledger = AgentVideoLedger()
            var job = try ledger.register(requestID: "video-test", arguments: args, at: f)
            job.status = state; try ledger.update(job, at: f)
            let restored = try AgentVideoLedger.load(from: f).jobs[job.id]!
            XCTAssertEqual(restored.status, ["awaiting_approval", "preparing"].contains(state) ? "interrupted" : state)
            XCTAssertEqual(restored.billing, "not_submitted")
        }
    }
    func testStorageFailureDoesNotAllocateAReplayIdentity() throws {
        let f = file(); defer { try? FileManager.default.removeItem(at: f.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: false)
        var ledger = AgentVideoLedger()
        XCTAssertThrowsError(try ledger.register(requestID: "video-test", arguments: args, at: f))
        XCTAssertTrue(ledger.jobs.isEmpty)
        try Data("corrupt".utf8).write(to: f.deletingLastPathComponent().appendingPathComponent("bad.json"))
        XCTAssertThrowsError(try AgentVideoLedger.load(from: f.deletingLastPathComponent().appendingPathComponent("bad.json")))
    }
}
