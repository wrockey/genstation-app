import XCTest
@testable import GenStationCore

final class ReleaseRepairTests: XCTestCase {
    func testSeptemberIntakeMatchesPublishedSchemasAndNames() throws {
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let data = try Data(contentsOf: base.appendingPathComponent("2026-09-image-intake-schemas.json"))
        let schemas = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        XCTAssertEqual(schemas.count, 4)
        for document in schemas.values {
            let paths = try XCTUnwrap(document["paths"] as? [String: [String: Any]])
            let operation = try XCTUnwrap(paths.values.first?["post"] as? [String: Any])
            let body = try XCTUnwrap(operation["requestBody"] as? [String: Any])
            let content = try XCTUnwrap(body["content"] as? [String: [String: Any]])
            let schema = try XCTUnwrap(content["application/json"]?["schema"] as? [String: Any])
            let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])
            let id = try XCTUnwrap((properties["model"]?["enum"] as? [String])?.first)
            let model = try XCTUnwrap(Catalog.model(for: id))
            for (_, params) in ProbeSet.all {
                let encoded = ParamEncoder.encode(ParamCatalog.descriptors(for: model), params: params,
                    context: ParamCatalog.context(for: model, hasInputImages: paths.keys.contains("/v1/images/edits")))
                for (key, value) in encoded {
                    let property = try XCTUnwrap(properties[key], "Undocumented request field: \(id) / \(key)")
                    if let choices = property["enum"] as? [String], let string = value as? String {
                        XCTAssertTrue(choices.contains(string), "Invalid enum: \(id) / \(key) / \(string)")
                    }
                }
            }
        }
        let modelsData = try Data(contentsOf: base.appendingPathComponent("2026-09-image-intake-models.json"))
        let models = try XCTUnwrap(JSONSerialization.jsonObject(with: modelsData) as? [[String: Any]])
        XCTAssertEqual(models.count, 4)
        for entry in models {
            let id = try XCTUnwrap(entry["id"] as? String)
            XCTAssertEqual(Catalog.model(for: id)?.displayName, (entry["info"] as? [String: Any])?["name"] as? String)
            XCTAssertTrue(ReleaseModelPolicy.allows(id, task: .image))
        }
    }

    func testSpecializedAndUnknownModelsCannotGenerateButHistoryStillResolves() {
        XCTAssertFalse(ReleaseModelPolicy.allows("klingai/video-o1-reference-to-video"))
        XCTAssertNotNil(Catalog.model(for: "klingai/video-o1-reference-to-video"))
        XCTAssertFalse(ReleaseModelPolicy.allows("future/unknown-model"))
        XCTAssertFalse(ReleaseModelPolicy.allows("topaz-labs/sharpen"))
        XCTAssertTrue(ReleaseModelPolicy.allows("gpt-image-2", task: .image))
        XCTAssertFalse(ReleaseModelPolicy.allows("gpt-image-2", task: .video))
    }

    func testSupportedModelsHaveControlsAndAppropriateMediaShapes() {
        for id in ReleaseModelPolicy.imageIDs.union(ReleaseModelPolicy.videoIDs) {
            let model = Catalog.model(for: id)
            XCTAssertNotNil(model, id)
            XCTAssertFalse(ParamCatalog.descriptors(forModelId: id)?.isEmpty ?? true, id)
            XCTAssertTrue(ReleaseModelPolicy.allows(id), id)
        }
    }

    func testCustomPayloadAndEndpointCannotBypassSupportBoundary() {
        XCTAssertNotNil(ReleaseModelPolicy.validateRequest(modelID: "gpt-image-2", task: .image,
            customPayload: "{\"model\":\"future/unknown\"}", endpoint: nil))
        XCTAssertNotNil(ReleaseModelPolicy.validateRequest(modelID: "gpt-image-2", task: .image,
            customPayload: nil, endpoint: "https://example.com/collect"))
        XCTAssertNil(ReleaseModelPolicy.validateRequest(modelID: "gpt-image-2", task: .image,
            customPayload: "{\"model\":\"openai/gpt-image-2\"}", endpoint: AIMLEndpoints.imagesEditsURL.absoluteString))
    }

    func testGrokEditUsesJSONImageObjectAndGenerationDoesNot() {
        let plain = GrokClient.imageRequestBody(model: "grok-imagine-image-2.0", prompt: "test", aspectRatio: "1:1", resolution: "2k")
        XCTAssertNil(plain["image"])
        let edit = GrokClient.imageRequestBody(model: "grok-imagine-image-2.0", prompt: "test", aspectRatio: "1:1", resolution: "2k", imageDataURI: "data:image/jpeg;base64,YQ==")
        XCTAssertEqual((edit["image"] as? [String: String])?["url"], "data:image/jpeg;base64,YQ==")
        XCTAssertEqual((edit["image"] as? [String: String])?["type"], "image_url")
        XCTAssertEqual(Catalog.model(for: "grok-imagine-image-2.0")?.maxInputImages, 1)
    }

    func testGeminiExcludesVisionUnderstandingAndDecodesThoughtFlag() throws {
        XCTAssertFalse(GeminiClient.supportedImageModels.contains("gemini-vision"))
        XCTAssertTrue(GeminiClient.supportedImageModels.contains("gemini-3.1-flash-image"))
        let data = Data("{\"thought\":true,\"text\":\"draft\"}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(GeminiClient.NewResponsePart.self, from: data).thought, true)
    }

    func testKlingImageToVideoDoesNotSendAnUnsupportedAspectRatio() throws {
        let descriptors = try XCTUnwrap(ParamCatalog.descriptors(forModelId: "kling-video/v3/standard/image-to-video"))
        XCTAssertFalse(descriptors.contains { $0.wireKey == "aspect_ratio" })
        let params = ModelParameters()
        let body = ParamEncoder.encode(descriptors, params: params, context: .init(modelId: "kling-video/v3/standard/image-to-video", isI2I: true, hasInputImages: true))
        XCTAssertNil(body["aspect_ratio"])
        XCTAssertNotNil(ParamCatalog.descriptors(forModelId: "kling-video/v3/standard/text-to-video")?.first { $0.wireKey == "aspect_ratio" })
    }

    func testComfyFailureWithoutCompletedFlagIsTerminal() {
        let failure: [String: Any] = ["completed": false, "status_str": "error",
            "messages": [["execution_error", ["exception_message": "Missing checkpoint"]]]]
        XCTAssertEqual(ComfyUIExecutionStatus.failureMessage(failure), "ComfyUI execution failed: Missing checkpoint")
        XCTAssertNotNil(ComfyUIExecutionStatus.failureMessage(["messages": [["execution_interrupted", [:]]]]))
        XCTAssertNil(ComfyUIExecutionStatus.failureMessage(["completed": false, "status_str": "running"]))
        XCTAssertNil(ComfyUIExecutionStatus.failureMessage(["completed": true, "status_str": "success"]))
    }
}
