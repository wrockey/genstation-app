import XCTest
@testable import GenStationCore

final class AgentImageTests: XCTestCase {
    func testDurableReplayAndConflict() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("jobs.json")
        var ledger = try AgentImageLedger.load(from: url)
        let first = try ledger.register(requestID: "test-1", arguments: ["prompt": "cat"], at: url)
        XCTAssertEqual(try ledger.register(requestID: "test-1", arguments: ["prompt": "cat"], at: url).id, first.id)
        XCTAssertThrowsError(try ledger.register(requestID: "test-1", arguments: ["prompt": "dog"], at: url))
        var submitted = first
        submitted.status = "submitting"
        submitted.billing = "unknown"
        try ledger.update(submitted, at: url)
        let restored = try AgentImageLedger.load(from: url)
        XCTAssertEqual(restored.jobs[first.id]?.status, "interrupted")
        XCTAssertEqual(restored.jobs[first.id]?.billing, "unknown")
        XCTAssertEqual(restored.jobs.count, 1)
    }

    func testPersistenceFailureDoesNotRegisterRequest() throws {
        var ledger = AgentImageLedger()
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        XCTAssertThrowsError(try ledger.register(requestID: "test", arguments: [:], at: parent.appendingPathComponent("jobs.json")))
        XCTAssertTrue(ledger.jobs.isEmpty)
    }

    @MainActor
    func testApprovalAndPersistenceGateTransportAndNeverRetry() async throws {
        let request = URLRequest(url: URL(string: "https://example.invalid/generate")!)
        var events: [String] = []
        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            events.append("POST")
            throw URLError(.timedOut)
        }
        do {
            _ = try await AgentImageSubmission.perform(request: request, authorize: {
                events.append("deny"); throw AgentImageError("Denied")
            }, persistIntent: { events.append("persist") }, transport: send)
            XCTFail("Expected denial")
        } catch { XCTAssertEqual(events, ["deny"]) }
        events = []
        do {
            _ = try await AgentImageSubmission.perform(request: request, authorize: { events.append("approve") }, persistIntent: {
                events.append("storage_failure"); throw AgentImageError("Disk full")
            }, transport: send)
            XCTFail("Expected storage failure")
        } catch { XCTAssertEqual(events, ["approve", "storage_failure"]) }
        events = []
        do {
            _ = try await AgentImageSubmission.perform(request: request, authorize: { events.append("approve") }, persistIntent: { events.append("persist") }, transport: send)
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(events, ["approve", "persist", "POST"]) }
    }

    func testEveryDiscoveredImageBuildsAndPrivateFieldsAreRejected() throws {
        let entries = AgentImageContract.models()
        XCTAssertTrue(entries.contains { $0["id"] as? String == "openai/gpt-image-2" })
        for entry in entries {
            let provider = try XCTUnwrap(entry["provider"] as? String)
            let model = try XCTUnwrap(entry["id"] as? String)
            let count = entry["requires_input_image"] as? Bool == true ? 1 : 0
            let contract = try AgentImageContract(provider: provider, model: model, prompt: "test", params: [:], inputCount: count)
            let request = try contract.request(apiKey: "test", imageDataURIs: Array(repeating: "data:image/png;base64,YQ==", count: count))
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNotNil(request.httpBody)
            XCTAssertThrowsError(try AgentImageContract(provider: provider, model: model, prompt: "test", params: ["api_key": "secret"], inputCount: count))
        }
    }

    func testCorruptStorageFailsClosedAndFingerprintDoesNotPersistPrompt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try AgentImageLedger.load(from: url))
        try FileManager.default.removeItem(at: url)
        var ledger = AgentImageLedger()
        let a = try ledger.register(requestID: "identity", arguments: ["prompt": "private prompt", "params": ["width": 3, "height": 4]], at: url)
        let b = try ledger.register(requestID: "identity", arguments: ["params": ["height": 4, "width": 3], "prompt": "private prompt"], at: url)
        XCTAssertEqual(a.id, b.id)
        XCTAssertFalse(try String(contentsOf: url).contains("private prompt"))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testEveryAdvertisedImageEnumValueIsUsable() throws {
        for entry in AgentImageContract.models() {
            let provider = try XCTUnwrap(entry["provider"] as? String)
            let model = try XCTUnwrap(entry["id"] as? String)
            let count = entry["requires_input_image"] as? Bool == true ? 1 : 0
            let schema = try XCTUnwrap(entry["parameter_schema"] as? [String: Any])
            let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
            for (key, rule) in properties {
                for value in rule["enum"] as? [Any] ?? [] {
                    XCTAssertNoThrow(try AgentImageContract(provider: provider, model: model, prompt: "test", params: [key: value], inputCount: count), "\(model) \(key)=\(value)")
                }
            }
        }
        XCTAssertThrowsError(try AgentImageContract(provider: "aimlapi", model: "google/gemini-3-pro-image-preview", prompt: "test", params: ["resolution": "100K"], inputCount: 0))
    }

    func testExplicitAdvertisedAIMLGeminiDefaultsReachWire() throws {
        for model in ["google/gemini-3-pro-image-preview", "google/gemini-3-pro-image-preview-edit"] {
            let count = model.hasSuffix("-edit") ? 1 : 0
            let contract = try AgentImageContract(provider: "aimlapi", model: model, prompt: "test", params: ["aspect_ratio": "1:1", "num_images": 1], inputCount: count)
            let request = try contract.request(apiKey: "fixture", imageDataURIs: Array(repeating: "data:image/png;base64,YQ==", count: count))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["aspect_ratio"] as? String, "1:1")
            XCTAssertEqual(body["num_images"] as? Int, 1)
        }
    }

    func testNativeWireBodiesAndValidation() throws {
        let gemini = try AgentImageContract(provider: "gemini", model: "gemini-2.5-flash-image", prompt: "cat", params: ["aspect_ratio": "1:1"], inputCount: 1)
        let request = try gemini.request(apiKey: "test-secret", imageDataURIs: ["data:image/png;base64,YQ=="])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: GeminiClient.apiKeyHeaderName), "test-secret")
        let parts = ((body["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])
        XCTAssertEqual((parts?.last?["inline_data"] as? [String: Any])?["data"] as? String, "YQ==")
        let grok = try AgentImageContract(provider: "grok", model: "grok-imagine-image-2.0", prompt: "cat", params: [:], inputCount: 1)
        XCTAssertEqual(try grok.request(apiKey: "k", imageDataURIs: ["data:image/png;base64,YQ=="]).url, GrokClient.imageEditsURL)
        XCTAssertThrowsError(try AgentImageContract(provider: "gemini", model: "gemini-2.5-flash-image", prompt: "cat", params: ["api_key": "secret"], inputCount: 0))
        XCTAssertThrowsError(try AgentImageContract(provider: "grok", model: "grok-imagine-image-2.0", prompt: "cat", params: ["resolution": "100k"], inputCount: 0))
        XCTAssertThrowsError(try AgentImageContract(provider: "grok", model: "grok-imagine-image-2.0", prompt: "cat", params: [:], inputCount: 2))
    }
    func testGPTImageEditsMatchUIDiscoveryAndMultipartWire() throws {
        let ids = ["openai/gpt-image-2", "openai/gpt-image-2.5-flare", "openai/gpt-image-2.5-sunburst"]
        let png = Data([0x89, 0x50, 0x4e, 0x47, 0, 0xff, 0x0d, 0x0a])
        for id in ids {
            let entry = try XCTUnwrap(AgentImageContract.models().first { $0["id"] as? String == id })
            XCTAssertEqual(entry["max_input_images"] as? Int, 16)
            XCTAssertEqual(entry["requires_input_image"] as? Bool, false)
            XCTAssertEqual(entry["display_name"] as? String, Catalog.model(for: id)?.displayName)
            XCTAssertNotNil(entry["description"] as? String)
            let contract = try AgentImageContract(provider: "aimlapi", model: id, prompt: "Change the sky", params: ["size": "1536x1024", "quality": "high"], inputCount: 1)
            let request = try contract.request(apiKey: "fixture", imageDataURIs: ["data:image/png;base64," + png.base64EncodedString()])
            XCTAssertEqual(request.url, AIMLEndpoints.imagesEditsURL)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
            XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
            let boundary = String(contentType.split(separator: "=").last!)
            let body = try XCTUnwrap(request.httpBody)
            XCTAssertNotNil(body.range(of: png))
            for (key, value) in [("model", id), ("prompt", "Change the sky"), ("size", "1536x1024"), ("quality", "high")] {
                XCTAssertNotNil(body.range(of: Data("name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8)))
            }
            XCTAssertTrue(body.suffix(Data("--\(boundary)--\r\n".utf8).count).elementsEqual(Data("--\(boundary)--\r\n".utf8)))
            XCTAssertNil(body.range(of: Data("base64,".utf8)))
            let generation = try AgentImageContract(provider: "aimlapi", model: id, prompt: "Create a sky", params: [:], inputCount: 0)
            let textRequest = try generation.request(apiKey: "fixture", imageDataURIs: [])
            XCTAssertEqual(textRequest.url?.absoluteString, Catalog.model(for: id)?.generationEndpoint)
            XCTAssertEqual(textRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertThrowsError(try AgentImageContract(provider: "aimlapi", model: id, prompt: "test", params: [:], inputCount: 17))
            XCTAssertThrowsError(try contract.request(apiKey: "fixture", imageDataURIs: ["https://example.invalid/image.png"]))
            XCTAssertThrowsError(try contract.request(apiKey: "fixture", imageDataURIs: ["data:image/png;base64,***"]))
        }
        let descriptions = AgentImageContract.models().filter { ids.dropFirst().contains($0["id"] as? String ?? "") }.compactMap { $0["description"] as? String }
        XCTAssertEqual(Set(descriptions).count, 2)
    }
    func testGPTImageMultipartKeepsEveryReferenceAndRejectsCountChanges() throws {
        let contract = try AgentImageContract(provider: "aimlapi", model: "openai/gpt-image-2.5-flare", prompt: "Combine these", params: [:], inputCount: 16)
        let references = (0..<16).map { "data:image/jpeg;base64," + Data("reference-\($0)".utf8).base64EncodedString() }
        let request = try contract.request(apiKey: "fixture", imageDataURIs: references)
        let body = try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
        XCTAssertEqual(body.components(separatedBy: "filename=\"image_").count - 1, 16)
        for index in 0..<16 { XCTAssertTrue(body.contains("reference-\(index)\r\n")) }
        XCTAssertThrowsError(try contract.request(apiKey: "fixture", imageDataURIs: Array(references.dropLast())))
    }

}
