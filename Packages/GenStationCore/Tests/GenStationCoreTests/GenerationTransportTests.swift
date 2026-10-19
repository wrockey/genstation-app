import XCTest
@testable import GenStationCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class PolishMockProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var failure: URLError.Code?
    static func reset(status: Int = 200, failure: URLError.Code? = nil) {
        lock.lock(); defer { lock.unlock() }
        requests = []; self.status = status; self.failure = failure
    }
    static func captured() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return requests
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            stream.close()
            captured.httpBody = bytes
        }
        Self.lock.lock()
        Self.requests.append(captured)
        let status = Self.status
        let failure = Self.failure
        Self.lock.unlock()
        if let failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class GenerationTransportTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PolishMockProtocol.self]
        return URLSession(configuration: config)
    }
    @MainActor
    func testVideoPersistenceFailurePreventsPOSTAndLostResponseStaysUncertain() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("video.json")
        var ledger = AgentVideoLedger()
        let args: [String: Any] = ["model": "fixture", "prompt": "lighthouse", "request_id": "durable-video"]
        var job = try ledger.register(requestID: "durable-video", arguments: args, at: file)
        var request = URLRequest(url: URL(string: "https://example.org/video")!)
        request.httpMethod = "POST"; request.httpBody = Data("approved body".utf8)
        PolishMockProtocol.reset()
        do {
            _ = try await AgentVideoSubmission.perform(request, jobID: UUID(), transport: GenerationTransport(), session: session,
                persistIntent: { throw CocoaError(.fileWriteNoPermission) })
            XCTFail("Persistence failure submitted video")
        } catch {}
        XCTAssertTrue(PolishMockProtocol.captured().isEmpty)
        PolishMockProtocol.reset(failure: .networkConnectionLost)
        do {
            _ = try await AgentVideoSubmission.perform(request, jobID: UUID(), transport: GenerationTransport(), session: session,
                persistIntent: {
                    XCTAssertTrue(PolishMockProtocol.captured().isEmpty)
                    job.status = "submitting"; job.billing = "unknown"
                    try ledger.update(job, at: file)
                })
            XCTFail("Lost response unexpectedly succeeded")
        } catch {}
        var restored = try AgentVideoLedger.load(from: file)
        let replay = try restored.register(requestID: "durable-video", arguments: args, at: file)
        XCTAssertEqual(replay.id, job.id)
        XCTAssertEqual(replay.status, "submission_unknown")
        XCTAssertEqual(PolishMockProtocol.captured().map(\.httpMethod), ["POST"])
    }

    func testCancelledReviewPostsNothingAndApprovedSnapshotPostsExactlyOnce() async throws {
        PolishMockProtocol.reset()
        let session = session()
        defer { session.invalidateAndCancel() }
        let transport = GenerationTransport()
        let id = UUID()
        var formRequest = URLRequest(url: URL(string: "https://example.org/generation")!)
        formRequest.httpMethod = "POST"
        formRequest.httpBody = Data("reviewed payload".utf8)
        let snapshot = formRequest
        formRequest.httpBody = Data("later form edits".utf8)
        do { _ = try await transport.submit(snapshot, id: id, approved: false, session: session); XCTFail("Cancelled review submitted") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertTrue(PolishMockProtocol.captured().isEmpty)
        _ = try await transport.submit(snapshot, id: id, approved: true, session: session)
        do { _ = try await transport.submit(snapshot, id: id, approved: true, session: session); XCTFail("Duplicate POST") } catch {}
        XCTAssertEqual(PolishMockProtocol.captured().count, 1)
        XCTAssertEqual(PolishMockProtocol.captured().first?.httpBody, Data("reviewed payload".utf8))
        XCTAssertEqual(PolishMockProtocol.captured().first?.httpMethod, "POST")
    }
    func testFailedDownloadAndStatusRecoveryUseOnlyGET() async throws {
        PolishMockProtocol.reset(status: 503)
        let session = session()
        defer { session.invalidateAndCancel() }
        let asset = URLRequest(url: URL(string: "https://example.org/asset")!)
        let (_, failedResponse) = try await GenerationTransport.recover(asset, session: session)
        XCTAssertEqual((failedResponse as? HTTPURLResponse)?.statusCode, 503)
        _ = try await GenerationTransport.recover(asset, session: session)
        let poll = URLRequest(url: URL(string: "https://example.org/status/existing-job")!)
        _ = try await GenerationTransport.recover(poll, session: session)
        XCTAssertEqual(PolishMockProtocol.captured().map(\.httpMethod), ["GET", "GET", "GET"])
        var invalid = poll; invalid.httpMethod = "POST"
        do { _ = try await GenerationTransport.recover(invalid, session: session); XCTFail("Recovery posted") } catch {}
        XCTAssertEqual(PolishMockProtocol.captured().count, 3)
    }
    func testServerErrorsNeverVerifyKeyThroughMockedTransport() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        for status in [401, 403, 429, 500] {
            PolishMockProtocol.reset(status: status)
            do { try await KeyValidation.check(provider: .aimlapi, key: "test", session: session); XCTFail("False verification") }
            catch {}
            XCTAssertEqual(PolishMockProtocol.captured().map(\.httpMethod), ["GET"])
        }
    }
    func testAmbiguousPostTimeoutCannotResubmitSameIdentity() async {
        PolishMockProtocol.reset(failure: .timedOut)
        let session = session()
        defer { session.invalidateAndCancel() }
        let transport = GenerationTransport()
        let id = UUID()
        var request = URLRequest(url: URL(string: "https://example.org/generation")!)
        request.httpMethod = "POST"
        for _ in 0..<2 {
            do { _ = try await transport.submit(request, id: id, approved: true, session: session); XCTFail("Expected failure") }
            catch {}
        }
        XCTAssertEqual(PolishMockProtocol.captured().map(\.httpMethod), ["POST"])
    }
    func testOfflineConnectionCannotVerifyKey() async {
        PolishMockProtocol.reset(failure: .notConnectedToInternet)
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            try await KeyValidation.check(provider: .aimlapi, key: "test", session: session)
            XCTFail("Offline connection verified")
        } catch ConnectionFailure.offline {} catch { XCTFail("Expected offline classification") }
        XCTAssertEqual(PolishMockProtocol.captured().map(\.httpMethod), ["GET"])
    }
    func testImageRecoveryMetadataSurvivesRestart() throws {
        let item = HistoryItem(prompt: "source", responseText: "download failed", date: Date(), mode: .grok, task: .image, status: .failed, sourceAssetURL: "https://example.org/original.png")
        let restored = try JSONDecoder().decode(HistoryItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(restored.sourceAssetURL, item.sourceAssetURL)
        XCTAssertNil(restored.videoUrl)
        XCTAssertEqual(JobRecovery.action(assetURL: restored.sourceAssetURL, fileExists: false, jobID: nil, pollingEndpoint: nil, status: restored.status, hasSubmission: false), .download)
    }
}
