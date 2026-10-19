import XCTest
@testable import GenStationCore

final class PromptSafetyPolicyTests: XCTestCase {
    func testBenignArtAndExistingContextExceptions() {
        for prompt in [
            "Editorial ceramic pitcher on limestone in soft daylight",
            "Educational botanical diagram of a flower",
            "A rooster weather cock on a farmhouse",
            "Illustration of Moby Dick",
            "Stars visible to the naked eye"
        ] {
            XCTAssertTrue(PromptSafetyPolicy.isPromptSafe(prompt).isSafe, prompt)
        }
    }

    func testExistingNormalizationRulesAndStableFindings() {
        for prompt in ["porn", "P0RN", "p\u{200B}orn", "pоrn"] {
            XCTAssertFalse(PromptSafetyPolicy.isPromptSafe(prompt).isSafe, prompt)
        }
        let result = PromptSafetyPolicy.isPromptSafe("gore porn gore")
        XCTAssertEqual(result.offendingPhrases, ["gore", "porn"])
    }

    func testComposedTextIsCheckedAfterJoining() {
        let benignSubject = "An editorial object study"
        XCTAssertTrue(PromptSafetyPolicy.isPromptSafe(benignSubject).isSafe)
        XCTAssertFalse(PromptSafetyPolicy.isPromptSafe(benignSubject + ", gore").isSafe)
    }

    func testChildSafetyHasNoContextException() {
        let result = PromptSafetyPolicy.isPromptSafe("nude child in an educational painting")
        XCTAssertFalse(result.isSafe)
        XCTAssertTrue(result.offendingPhrases.contains("child safety violation"))
    }
    func testReportedContextsDoNotAloneReproduceARejection() {
        // Synthetic contexts, not the unavailable original failing comic prompts.
        for prompt in ["A cellar with a crack in the wall", "A hand holding a clutch bag",
                       "An aged face with weathered skin texture", "An eyelash in soft light",
                       "A tired adult rubbing an arm in pain"] {
            XCTAssertTrue(PromptSafetyPolicy.filterReasons(prompt).isEmpty, prompt)
        }
    }

    func testDiagnosticsAreBoundedNormalizedAndDoNotDiscloseContext() throws {
        let reasons = PromptSafetyPolicy.filterReasons("Private project name: P0RN and gore")
        XCTAssertEqual(reasons.map(\.phrase), ["gore", "porn"])
        XCTAssertTrue(reasons.allSatisfy { $0.matchKind == "normalized_phrase" })
        XCTAssertEqual(try JSONDecoder().decode([PromptSafetyPolicy.FilterReason].self,
            from: JSONEncoder().encode(reasons)), reasons)
        let bounded = PromptSafetyPolicy.reasons(for: (0..<30).map { "\($0)" + String(repeating: "a", count: 200) })
        XCTAssertEqual(bounded.count, 16)
        XCTAssertTrue(bounded.allSatisfy { $0.phrase.count <= 80 })
        let child = try XCTUnwrap(PromptSafetyPolicy.filterReasons("nude child").first { $0.category == "child_safety" })
        XCTAssertEqual(child.matchKind, "category_label")
    }

    @MainActor
    func testDryRunAndSubmissionGateReturnSameReasonsWithoutTransport() async throws {
        let prompt = "A private composition, P0RN"
        var expected: [PromptSafetyPolicy.FilterReason] = []
        do { try PromptSafetyPolicy.requireSafe(prompt); XCTFail("Expected rejection") }
        catch let error as PromptSafetyPolicy.Blocked { expected = error.reasons }
        var sideEffects = 0
        do {
            _ = try await AgentImageSubmission.perform(
                request: URLRequest(url: URL(string: "https://example.invalid/generate")!),
                authorize: { try PromptSafetyPolicy.requireSafe(prompt) },
                persistIntent: { sideEffects += 1 }, transport: { _ in
                    sideEffects += 1; throw URLError(.badServerResponse)
                })
            XCTFail("Expected rejection")
        } catch let error as PromptSafetyPolicy.Blocked { XCTAssertEqual(error.reasons, expected) }
        XCTAssertEqual(sideEffects, 0)
    }

    func testWorkflowAndDurableJobKeepSameDiagnosticsAndLegacyDecoding() throws {
        let graph: [String: Any] = ["1": ["class_type": "CLIPTextEncode", "inputs": ["text": "P0RN"]]]
        let reasons = WorkflowPromptSafety.inspect(graph).filterReasons
        XCTAssertEqual(reasons, PromptSafetyPolicy.filterReasons("P0RN"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("jobs.json")
        var ledger = AgentImageLedger()
        var job = try ledger.register(requestID: "blocked", arguments: [:], at: file)
        XCTAssertNil(try AgentImageLedger.load(from: file).jobs[job.id]?.filterReasons)
        job.status = "failed"; job.errorCode = "content_filtered"; job.filterReasons = reasons
        try ledger.update(job, at: file)
        XCTAssertEqual(try AgentImageLedger.load(from: file).jobs[job.id]?.filterReasons, reasons)
        var videos = AgentVideoLedger()
        let videoFile = folder.appendingPathComponent("videos.json")
        var video = try videos.register(requestID: "video-blocked", arguments: [:], at: videoFile)
        XCTAssertNil(try AgentVideoLedger.load(from: videoFile).jobs[video.id]?.filterReasons)
        video.status = "failed"; video.errorCode = "content_filtered"; video.filterReasons = reasons
        try videos.update(video, at: videoFile)
        XCTAssertEqual(try AgentVideoLedger.load(from: videoFile).jobs[video.id]?.filterReasons, reasons)
        // A provider failure does not fabricate local matches.
        job.errorCode = "provider_error"; job.filterReasons = nil
        try ledger.update(job, at: file)
        XCTAssertNil(try AgentImageLedger.load(from: file).jobs[job.id]?.filterReasons)
    }
}
