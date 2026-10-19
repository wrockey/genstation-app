import XCTest
@testable import GenStationCore

private final class ComfyMockProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var captured: [URLRequest] = []
    nonisolated(unsafe) static var failSubmit = false
    nonisolated(unsafe) static var missingHistory = false
    static func reset(failSubmit: Bool = false, missingHistory: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        captured = []; self.failSubmit = failSubmit; self.missingHistory = missingHistory
    }
    static func requests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        let fail = Self.failSubmit && request.httpMethod == "POST"
        let missing = Self.missingHistory
        Self.lock.unlock()
        if fail { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        let path = request.url!.path
        let body: Data
        if path.hasSuffix("/upload/image") { body = Data(#"{"name":"accepted.png","subfolder":"isolated","type":"input"}"#.utf8) }
        else if path.hasSuffix("/prompt") { body = Data(#"{"prompt_id":"known-job"}"#.utf8) }
        else if path.contains("/history/") {
            body = Data((missing ? "{}" : #"{"known-job":{"status":{"completed":true},"outputs":{"20":{"images":[{"filename":"second.png"}]},"10":{"images":[{"filename":"first image.png"},{"filename":"another.png"}]}}}}"#).utf8)
        } else { body = Data("original".utf8) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ComfyUITransportTests: XCTestCase {
    func testUploadUsesUniquePNGNameWithoutSubmittingWorkflow() async throws {
        ComfyMockProtocol.reset()
        let session = session(); defer { session.invalidateAndCancel() }
        let transport = try ComfyUITransport(serverURL: "https://fixture.invalid", session: session)
        let uploaded = try await transport.uploadPNG(Data([137, 80, 78, 71, 13, 10, 26, 10]))
        XCTAssertEqual(uploaded.serverFileID, "isolated/accepted.png")
        let requests = ComfyMockProtocol.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.path, "/upload/image")
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertTrue(requests.first?.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
    }
    func testUploadResponseRejectsTraversalAbsolutePathsAndWrongMedia() throws {
        for name in ["../escape.png", "/escape.png", "bad\\name.png", "name.txt", "bad\nname.png"] {
            let data = try JSONSerialization.data(withJSONObject: ["name": name, "subfolder": "", "type": "input"])
            XCTAssertThrowsError(try ComfyUITransport.uploadedImage(from: data))
        }
        for folder in ["../outside", "/absolute", "a//b", "a/../b", "C:\\temp"] {
            let data = try JSONSerialization.data(withJSONObject: ["name": "valid.png", "subfolder": folder, "type": "input"])
            XCTAssertThrowsError(try ComfyUITransport.uploadedImage(from: data))
        }
        XCTAssertThrowsError(try ComfyUITransport.uploadedImage(from: Data(#"{"name":"valid.png","subfolder":"","type":"output"}"#.utf8)))
    }
    func testBlockedSavedPromptNeverPersistsSubmissionIntentOrMakesNetworkRequest() async throws {
        ComfyMockProtocol.reset()
        let session = session(); defer { session.invalidateAndCancel() }
        let transport = try ComfyUITransport(serverURL: "https://fixture.invalid", session: session)
        let graph: [String: Any] = ["1": ["class_type": "CLIPTextEncode", "inputs": ["text": "gore"]]]
        do {
            _ = try await transport.submit(apiWorkflow: graph, clientID: "client",
                persistIntent: { XCTFail("Blocked prompt cannot reach submission intent") },
                persistPromptID: { _ in XCTFail("Blocked prompt cannot return a server ID") })
            XCTFail("Expected content block")
        } catch { XCTAssertTrue(error is WorkflowPromptSafety.Blocked) }
        XCTAssertTrue(ComfyMockProtocol.requests().isEmpty)
    }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ComfyMockProtocol.self]
        return URLSession(configuration: config)
    }
    func testSubmitOnceThenRetrieveOrderedOutputsUsingGET() async throws {
        ComfyMockProtocol.reset()
        let session = session(); defer { session.invalidateAndCancel() }
        let transport = try ComfyUITransport(serverURL: "fixture.invalid/comfy/", session: session)
        let id = try await transport.submit(apiWorkflow: [:], clientID: "client", persistIntent: {}, persistPromptID: { _ in })
        let entry = try await transport.history(promptID: id)
        let outputs = ComfyUITransport.outputs(in: try XCTUnwrap(entry))
        XCTAssertEqual(outputs.map(\.filename), ["first image.png", "another.png", "second.png"])
        XCTAssertEqual(ComfyUITransport.outputs(in: entry!, selectedNodeID: "20").count, 1)
        let original = try await transport.download(outputs[0])
        XCTAssertEqual(original, Data("original".utf8))
        let requests = ComfyMockProtocol.requests()
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "GET", "GET"])
        XCTAssertEqual(requests[0].url?.path, "/comfy/prompt")
        XCTAssertEqual(requests[1].url?.path, "/comfy/history/known-job")
        XCTAssertTrue(requests[2].url!.absoluteString.contains("first%20image.png"))
    }
    func testLostSubmissionResponseIsNotRetriedAndRecoveryNeverPosts() async throws {
        ComfyMockProtocol.reset(failSubmit: true)
        let session = session(); defer { session.invalidateAndCancel() }
        let transport = try ComfyUITransport(serverURL: "https://fixture.invalid", session: session)
        do { _ = try await transport.submit(apiWorkflow: [:], clientID: "client", persistIntent: {}, persistPromptID: { _ in }); XCTFail("Expected failure") } catch { }
        XCTAssertEqual(ComfyMockProtocol.requests().map(\.httpMethod), ["POST"])
        ComfyMockProtocol.reset(missingHistory: true)
        let missing = try await transport.history(promptID: "known-job")
        XCTAssertNil(missing)
        XCTAssertEqual(ComfyMockProtocol.requests().map(\.httpMethod), ["GET"])
        do { _ = try await transport.history(promptID: "../prompt"); XCTFail("Expected invalid ID") } catch { }
        XCTAssertEqual(ComfyMockProtocol.requests().count, 1)
    }
    func testSharedNormalizationRejectsCredentialsAndUnsupportedSchemes() throws {
        XCTAssertEqual(try ComfyUITransport(serverURL: " localhost:8188/ ").serverURL, "http://localhost:8188")
        XCTAssertNotNil(ComfyUIEndpoints.promptURL(serverURL: "HTTP://localhost:8188"))
        for value in ["ftp://host", "https://user:password@host", "http://host/?token=secret", "http://host/#fragment"] {
            XCTAssertThrowsError(try ComfyUITransport(serverURL: value))
            XCTAssertNil(ComfyUIEndpoints.promptURL(serverURL: value))
        }
    }

    @MainActor
    func testDurablePromptIDRestartReplayAndMissingHistoryDownload() async throws {
        ComfyMockProtocol.reset()
        let session = session(); defer { session.invalidateAndCancel() }
        let transport = try ComfyUITransport(serverURL: "https://fixture.invalid/comfy", session: session)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("jobs.json")
        let arguments: [String: Any] = ["workflow_id": UUID().uuidString, "request_id": "durable"]
        var ledger = AgentImageLedger()
        var job = try ledger.register(requestID: "durable", arguments: arguments, at: file)
        job.workflow = WorkflowRecoverySnapshot(workflowID: UUID(), workflowRevision: 2, graphDigest: "digest",
            serverURL: transport.serverURL, selectedOutputNodeID: "10", workflowName: "Fixture", displayPrompt: "Ceramic study")
        let id = try await transport.submit(apiWorkflow: [:], clientID: "client", persistIntent: {
            XCTAssertTrue(ComfyMockProtocol.requests().isEmpty)
            job.status = "submitting"; try ledger.update(job, at: file)
        }, persistPromptID: { id in
            XCTAssertEqual(ComfyMockProtocol.requests().map(\.httpMethod), ["POST"])
            job.workflow?.promptID = id; job.status = "queued"; try ledger.update(job, at: file)
        })
        let restored = try AgentImageLedger.load(from: file)
        let replay = try XCTUnwrap(restored.existing(requestID: "durable", arguments: arguments))
        XCTAssertEqual(replay.id, job.id)
        XCTAssertEqual(replay.status, "recoverable")
        XCTAssertEqual(replay.workflow?.promptID, id)
        XCTAssertEqual(replay.workflow?.serverURL, "https://fixture.invalid/comfy")
        XCTAssertThrowsError(try restored.existing(requestID: "durable", arguments: ["different": true]))
        let entry = try await transport.history(promptID: id)
        job.workflow?.outputs = ComfyUITransport.outputs(in: try XCTUnwrap(entry), selectedNodeID: "10")
        job.status = "downloading"; try ledger.update(job, at: file)
        let afterDownloadInterruption = try AgentImageLedger.load(from: file)
        let descriptor = try XCTUnwrap(afterDownloadInterruption.jobs[job.id]?.workflow?.outputs.first)
        ComfyMockProtocol.reset(missingHistory: true)
        let bytes = try await transport.download(descriptor)
        XCTAssertEqual(bytes, Data("original".utf8))
        XCTAssertEqual(ComfyMockProtocol.requests().map(\.httpMethod), ["GET"])
    }

    @MainActor
    func testFailedIntentPreventsPOSTAndLostResponseRestoresUnknown() async throws {
        ComfyMockProtocol.reset()
        let session = session(); defer { session.invalidateAndCancel() }
        let transport = try ComfyUITransport(serverURL: "https://fixture.invalid", session: session)
        do {
            _ = try await transport.submit(apiWorkflow: [:], clientID: "client",
                persistIntent: { throw CocoaError(.fileWriteOutOfSpace) }, persistPromptID: { _ in XCTFail("Unexpected prompt ID") })
            XCTFail("Expected storage failure")
        } catch { }
        XCTAssertTrue(ComfyMockProtocol.requests().isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("jobs.json")
        var ledger = AgentImageLedger()
        var job = try ledger.register(requestID: "uncertain", arguments: [:], at: file)
        job.workflow = WorkflowRecoverySnapshot(workflowID: nil, workflowRevision: nil, graphDigest: "digest",
            serverURL: transport.serverURL, selectedOutputNodeID: nil, workflowName: "Fixture", displayPrompt: "Ceramic study")
        ComfyMockProtocol.reset(failSubmit: true)
        do {
            _ = try await transport.submit(apiWorkflow: [:], clientID: "client", persistIntent: {
                job.status = "submitting"; try ledger.update(job, at: file)
            }, persistPromptID: { _ in XCTFail("Unexpected prompt ID") })
            XCTFail("Expected lost response")
        } catch { }
        XCTAssertEqual(ComfyMockProtocol.requests().map(\.httpMethod), ["POST"])
        let restored = try AgentImageLedger.load(from: file)
        XCTAssertEqual(restored.jobs[job.id]?.status, "submission_unknown")
        XCTAssertNil(restored.jobs[job.id]?.workflow?.promptID)
    }
}
