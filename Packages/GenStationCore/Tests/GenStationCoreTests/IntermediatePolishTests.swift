import XCTest
@testable import GenStationCore

final class IntermediatePolishTests: XCTestCase {
    func testChecksNeverPostAndTrimKeys() {
        for provider: Provider in [.gemini, .grok, .aimlapi] {
            let request = KeyValidation.request(provider: provider, key: "  test-key\n")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            if provider != .gemini { XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key") }
        }
        XCTAssertEqual(KeyValidation.request(provider: .aimlapi, key: "test").url?.path, "/v2/billing/detail")
    }
    func testErrorsCannotAuthenticate() {
        for status in [400, 401, 403, 404, 429, 500, 503] { XCTAssertNotNil(KeyValidation.failure(status: status)) }
        XCTAssertNil(KeyValidation.failure(status: 200))
    }
    func testRecoveryPrefersExistingAssetAndJob() {
        XCTAssertEqual(JobRecovery.action(assetURL: "https://example.org/result", fileExists: false, jobID: "job", pollingEndpoint: "poll", status: .failed, hasSubmission: true), .download)
        XCTAssertEqual(JobRecovery.action(assetURL: nil, fileExists: false, jobID: "job", pollingEndpoint: "poll", status: .timeout, hasSubmission: true), .checkStatus)
        XCTAssertEqual(JobRecovery.action(assetURL: nil, fileExists: false, jobID: nil, pollingEndpoint: nil, status: .failed, hasSubmission: true), .generateAgain)
        XCTAssertEqual(JobRecovery.action(assetURL: nil, fileExists: true, jobID: nil, pollingEndpoint: nil, status: .completed, hasSubmission: true), .none)
    }
    func testDraftDestinationsAndOccupiedWork() {
        for task: CreateTask in [.image, .video] {
            let destinations = HistoryDraftTransition.destinations(task: task)
            XCTAssertFalse(destinations.isEmpty)
            for destination in destinations {
                if destination.provider == .aimlapi {
                    XCTAssertTrue(ReleaseModelPolicy.allows(destination.id, task: task))
                    XCTAssertTrue(Catalog.model(for: destination.id)!.isI2I)
                }
                XCTAssertNil(HistoryDraftTransition.issue(destination: destination, prompt: "", occupiedInputs: 0, sourceReadable: true))
                XCTAssertNotNil(HistoryDraftTransition.issue(destination: destination, prompt: "existing work", occupiedInputs: 0, sourceReadable: true))
                XCTAssertNotNil(HistoryDraftTransition.issue(destination: destination, prompt: "", occupiedInputs: 1, sourceReadable: true))
                XCTAssertNotNil(HistoryDraftTransition.issue(destination: destination, prompt: "", occupiedInputs: 0, sourceReadable: false))
            }
        }
    }
    func testClassificationUsesCodesAndPhase() {
        XCTAssertEqual(ProviderFailure.classify(provider: .aimlapi, status: 403, phase: .submission).kind, .denied)
        XCTAssertEqual(ProviderFailure.classify(provider: .grok, status: 403, code: "insufficient_credits", phase: .submission).kind, .credits)
        XCTAssertEqual(ProviderFailure.classify(provider: .gemini, status: 429, phase: .connection).kind, .throttled)
        XCTAssertEqual(ProviderFailure.classify(provider: .grok, phase: .save).kind, .save)
        let timeout = ProviderFailure.classify(provider: .grok, phase: .submission, transportCode: NSURLErrorTimedOut)
        XCTAssertEqual(timeout.kind, .timeout)
        XCTAssertTrue(timeout.message.contains("may have accepted"))
    }
    func testDiagnosticsRedactSecretsAndBoundSize() {
        let raw = "Authorization: Bearer private-secret https://example.org/a?api_key=secret&token=secret data:image/png;base64,YWJjZA=="
        let redacted = ProviderFailure.redact(raw)
        XCTAssertFalse(redacted.contains("secret"))
        XCTAssertFalse(redacted.contains("YWJjZA"))
        XCTAssertLessThanOrEqual(ProviderFailure.redact(String(repeating: "a", count: 5000)).count, 1600)
    }
    func testVideoSummaryAndExpiredHostedInputs() throws {
        let payload = try JSONSerialization.data(withJSONObject: ["duration": 5, "resolution": "480p", "audio": true, "image": ["url": "https://example.org/frame"]] as [String: Any])
        let summary = VideoSubmissionSummary.describe(payload: payload)
        XCTAssertTrue(summary.contains("Duration: 5"))
        XCTAssertTrue(summary.contains("First frame: present"))
        XCTAssertTrue(summary.contains("hosted URLs"))
        XCTAssertFalse(VideoSubmissionSummary.containsHostedInput(["image": ["url": "data:image/png;base64,abcd"]]))
    }
}
