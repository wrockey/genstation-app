import XCTest
@testable import GenStationCore

@MainActor
final class AgentSpendingThresholdTests: XCTestCase {
    private func store() throws -> AgentSpendingThreshold {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("budget.json")
        return AgentSpendingThreshold(file: url)
    }
    private let scope = AgentSpendingThreshold.Scope(provider: .grok, model: "grok-imagine-image-2.0")
    private func charge(_ decimal: String) throws -> ProviderChargeEvidence {
        let data = Data("{\"usage\":{\"cost_in_usd_ticks\":\(try ExactUSD(decimal: decimal).ticks)}}".utf8)
        return try XCTUnwrap(ProviderChargeEvidence.observe(provider: .grok, data: data, httpStatus: 500).evidence)
    }
    func testSerialOvershootAndReplay() throws {
        let s = try store()
        try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600))
        let grant = try XCTUnwrap(s.activeGrantID)
        try s.reserve(jobID: "one", requestID: "r1", fingerprint: "a", scope: scope, grantID: grant)
        XCTAssertEqual(s.pauseReason(grantID: grant), "in_flight")
        try s.markIntent(jobID: "one", grantID: grant)
        try s.settle(jobID: "one", evidence: charge("4.9999999999"))
        XCTAssertNil(s.pauseReason(grantID: grant))
        try s.reserve(jobID: "two", requestID: "r2", fingerprint: "b", scope: scope, grantID: grant)
        try s.markIntent(jobID: "two", grantID: grant)
        try s.settle(jobID: "two", evidence: charge("4"))
        try s.settle(jobID: "two", evidence: charge("4"))
        XCTAssertEqual(s.spent.decimal, "8.9999999999")
        XCTAssertEqual(s.pauseReason(grantID: grant), "budget_exhausted")
        XCTAssertThrowsError(try s.reserve(jobID: "three", requestID: "new-id", fingerprint: "c", scope: scope, grantID: grant))
    }
    func testUnknownAndRestartCannotClearObligation() throws {
        let s = try store()
        try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600))
        let grant = try XCTUnwrap(s.activeGrantID)
        try s.reserve(jobID: "one", requestID: "r", fingerprint: "a", scope: scope, grantID: grant)
        try s.markIntent(jobID: "one", grantID: grant)
        try s.settle(jobID: "one", evidence: nil)
        XCTAssertEqual(s.pauseReason(grantID: grant), "billing_unresolved")
        let restarted = AgentSpendingThreshold(file: s.file)
        XCTAssertNil(restarted.activeGrantID)
        XCTAssertThrowsError(try restarted.enable(budget: ExactUSD(decimal: "10"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600)))
        XCTAssertEqual(restarted.snapshot["state"] as? String, "billing_unresolved")
    }
    func testKnownZeroAndExactBoundaryLimitChanges() throws {
        let s = try store()
        try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600))
        let grant = try XCTUnwrap(s.activeGrantID)
        for (id, cost) in [("zero", "0"), ("five", "5")] {
            try s.reserve(jobID: id, requestID: id, fingerprint: id, scope: scope, grantID: grant)
            try s.markIntent(jobID: id, grantID: grant)
            try s.settle(jobID: id, evidence: charge(cost))
        }
        XCTAssertEqual(s.pauseReason(grantID: grant), "budget_exhausted")
        try s.changeBudget(ExactUSD(decimal: "6"))
        XCTAssertNil(s.pauseReason(grantID: grant))
        try s.changeBudget(ExactUSD(decimal: "4"))
        XCTAssertEqual(s.spent.decimal, "5.0000000000")
        XCTAssertEqual(s.pauseReason(grantID: grant), "budget_exhausted")
    }
    func testRevocationExpiryAndDefinitelyUnsubmittedCrash() throws {
        let s = try store()
        try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600))
        let grant = try XCTUnwrap(s.activeGrantID)
        try s.reserve(jobID: "one", requestID: "r", fingerprint: "a", scope: scope, grantID: grant)
        try s.disable()
        XCTAssertThrowsError(try s.markIntent(jobID: "one", grantID: grant))
        let restarted = AgentSpendingThreshold(file: s.file)
        try restarted.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(1))
        XCTAssertEqual(restarted.pauseReason(grantID: restarted.activeGrantID!, now: Date().addingTimeInterval(2)), "grant_expired")
    }
    func testCorruptStorageFailsClosed() throws {
        let s = try store()
        try FileManager.default.createDirectory(at: s.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("bad".utf8).write(to: s.file)
        let bad = AgentSpendingThreshold(file: s.file)
        XCTAssertThrowsError(try bad.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600)))
        XCTAssertEqual(bad.snapshot["state"] as? String, "storage_unavailable")
    }
    func testMockTransportSeveralImagesThenNoCallsAfterExhaustion() async throws {
        let s = try store()
        try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600))
        let grant = try XCTUnwrap(s.activeGrantID)
        var calls = 0
        let request = URLRequest(url: URL(string: "https://mock.invalid/images")!)
        for (id, price) in [("1", "1"), ("2", "1.90"), ("3", "4")] {
            let (data, response) = try await AgentImageSubmission.perform(request: request, authorize: {
                try s.reserve(jobID: id, requestID: id, fingerprint: id, scope: self.scope, grantID: grant)
            }, persistIntent: {
                try s.markIntent(jobID: id, grantID: grant)
            }, transport: { req in
                calls += 1
                // Aggregate request usage covers both outputs, including a charged HTTP failure.
                let body = Data("{\"usage\":{\"cost_in_usd_ticks\":\(try ExactUSD(decimal: price).ticks)},\"data\":[{},{}]}".utf8)
                return (body, HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
            })
            let evidence = ProviderChargeEvidence.observe(provider: .grok, data: data, httpStatus: (response as! HTTPURLResponse).statusCode).evidence
            try s.settle(jobID: id, evidence: evidence)
            try s.settle(jobID: id, evidence: evidence)
        }
        do {
            _ = try await AgentImageSubmission.perform(request: request, authorize: {
                try s.reserve(jobID: "4", requestID: "changed-retry", fingerprint: "4", scope: self.scope, grantID: grant)
            }, persistIntent: { XCTFail("Must not persist intent after exhaustion") }, transport: { _ in
                calls += 1; throw AgentImageError("Unexpected call")
            })
            XCTFail("Must reject exhausted grant")
        } catch { }
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(s.spent.decimal, "6.9000000000")
    }
    func testMalformedResponseBlocksNextProviderAndLostResponseRestart() async throws {
        for body in ["{}", "{\"usage\":{\"cost_in_usd_ticks\":-1}}", "{\"usage\":{\"currency\":\"EUR\",\"cost_in_usd_ticks\":0}}"] {
            let s = try store()
            try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600))
            let grant = try XCTUnwrap(s.activeGrantID)
            try s.reserve(jobID: "one", requestID: "r", fingerprint: "a", scope: scope, grantID: grant)
            try s.markIntent(jobID: "one", grantID: grant)
            let evidence = ProviderChargeEvidence.observe(provider: .grok, data: Data(body.utf8), httpStatus: 200).evidence
            XCTAssertNil(evidence)
            try s.settle(jobID: "one", evidence: evidence)
            XCTAssertEqual(s.pauseReason(grantID: grant), "billing_unresolved")
            XCTAssertThrowsError(try s.reserve(jobID: "two", requestID: "new", fingerprint: "b", scope: scope, grantID: grant))
        }
        let s = try store()
        try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600))
        let grant = try XCTUnwrap(s.activeGrantID)
        try s.reserve(jobID: "one", requestID: "r", fingerprint: "a", scope: scope, grantID: grant)
        try s.markIntent(jobID: "one", grantID: grant)
        let restarted = AgentSpendingThreshold(file: s.file)
        XCTAssertEqual(restarted.snapshot["state"] as? String, "billing_unresolved")
        // Restoring already persisted response usage settles without any POST or GET.
        try restarted.settle(jobID: "one", evidence: charge("1.2345678901"))
        XCTAssertEqual(restarted.spent.decimal, "1.2345678901")
        XCTAssertNil(restarted.activeGrantID)
    }
    func testProvidersShareOneSlotAndUnsupportedScopeCannotReserve() throws {
        let s = try store()
        let aiml = AgentSpendingThreshold.Scope(provider: .aimlapi, model: "mock-image")
        try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope, aiml], expiresAt: Date().addingTimeInterval(3600))
        let grant = try XCTUnwrap(s.activeGrantID)
        try s.reserve(jobID: "one", requestID: "r1", fingerprint: "a", scope: scope, grantID: grant)
        XCTAssertThrowsError(try s.reserve(jobID: "two", requestID: "r2", fingerprint: "b", scope: aiml, grantID: grant))
        try s.releaseUnsubmitted(jobID: "one")
        try s.reserve(jobID: "two", requestID: "r2", fingerprint: "b", scope: aiml, grantID: grant)
        try s.releaseUnsubmitted(jobID: "two")
        XCTAssertThrowsError(try s.reserve(jobID: "three", requestID: "r3", fingerprint: "c", scope: .init(provider: .gemini, model: "gemini"), grantID: grant))
        XCTAssertThrowsError(try s.reserve(jobID: "one", requestID: "r1", fingerprint: "a", scope: scope, grantID: grant))
    }
    func testPersistenceFailurePreventsTransport() async throws {
        let s = try store()
        try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600))
        let grant = try XCTUnwrap(s.activeGrantID)
        try FileManager.default.removeItem(at: s.file)
        try FileManager.default.createDirectory(at: s.file, withIntermediateDirectories: false)
        var calls = 0
        do {
            _ = try await AgentImageSubmission.perform(request: URLRequest(url: URL(string: "https://mock.invalid")!), authorize: {
                try s.reserve(jobID: "one", requestID: "r", fingerprint: "a", scope: self.scope, grantID: grant)
            }, persistIntent: { XCTFail("No durable authorization") }, transport: { _ in
                calls += 1; throw AgentImageError("Unexpected transport")
            })
            XCTFail("Persistence must fail")
        } catch { }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(s.snapshot["state"] as? String, "storage_unavailable")
    }

    func testConcurrentCallersCannotSubmitAcrossProviders() async throws {
        let s = try store()
        let aiml = AgentSpendingThreshold.Scope(provider: .aimlapi, model: "mock-image")
        try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope, aiml], expiresAt: Date().addingTimeInterval(3600))
        let grant = try XCTUnwrap(s.activeGrantID)
        let xai = scope
        let winners = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for index in 0..<20 {
                group.addTask {
                    await MainActor.run {
                        do {
                            let id = String(index)
                            try s.reserve(jobID: id, requestID: id, fingerprint: id, scope: index % 2 == 0 ? aiml : xai, grantID: grant)
                            try s.markIntent(jobID: id, grantID: grant)
                            return true
                        } catch { return false }
                    }
                }
            }
            var count = 0
            for await won in group { if won { count += 1 } }
            return count
        }
        XCTAssertEqual(winners, 1)
    }

    func testMissingSpendingFileCannotEraseImageLedgerObligation() throws {
        let s = try store()
        try s.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600))
        let grant = try XCTUnwrap(s.activeGrantID)
        try s.reserve(jobID: "one", requestID: "r", fingerprint: "original", scope: scope, grantID: grant)
        try s.markIntent(jobID: "one", grantID: grant)
        try FileManager.default.removeItem(at: s.file)
        let restarted = AgentSpendingThreshold(file: s.file)
        XCTAssertThrowsError(try restarted.verifyRecordedJob(jobID: "one", grantID: grant, fingerprint: "original"))
        XCTAssertThrowsError(try restarted.enable(budget: ExactUSD(decimal: "5"), scopes: [scope], expiresAt: Date().addingTimeInterval(3600)))
        XCTAssertEqual(restarted.snapshot["state"] as? String, "storage_unavailable")
    }

}
