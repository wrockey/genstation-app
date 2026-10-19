import XCTest
@testable import GenStationCore

final class GrokClientTests: XCTestCase {

    func testEndpointsMatchTheLiteralsTheyReplace() {
        XCTAssertEqual(GrokClient.imageGenerationsURL.absoluteString,
                       "https://api.x.ai/v1/images/generations")
        XCTAssertEqual(GrokClient.modelsURL.absoluteString, "https://api.x.ai/v1/models")
        XCTAssertEqual(GrokClient.chatCompletionsURL.absoluteString,
                       "https://api.x.ai/v1/chat/completions")
    }

    /// The legacy grok-2-image models reject aspect_ratio/resolution, so only the
    /// grok-imagine family may carry them. Sending them anyway is a 400.
    func testImagineModelsCarrySizingParamsAndLegacyModelsDoNot() {
        let imagine = GrokClient.imageRequestBody(
            model: "grok-imagine-image", prompt: "a bicycle",
            aspectRatio: "16:9", resolution: "2k")
        XCTAssertEqual(imagine["model"] as? String, "grok-imagine-image")
        XCTAssertEqual(imagine["prompt"] as? String, "a bicycle")
        XCTAssertEqual(imagine["n"] as? Int, 1)
        XCTAssertEqual(imagine["response_format"] as? String, "b64_json")
        XCTAssertEqual(imagine["aspect_ratio"] as? String, "16:9")
        XCTAssertEqual(imagine["resolution"] as? String, "2k")

        let legacy = GrokClient.imageRequestBody(
            model: "grok-2-image-1212", prompt: "a bicycle",
            aspectRatio: "16:9", resolution: "2k")
        XCTAssertNil(legacy["aspect_ratio"])
        XCTAssertNil(legacy["resolution"])
        XCTAssertEqual(legacy.keys.sorted(), ["model", "n", "prompt", "response_format"])
    }

    func testAuthorizationHeaderIsABearerToken() {
        let header = GrokClient.authorizationHeader(apiKey: "xai-secret")
        XCTAssertEqual(header.name, "Authorization")
        XCTAssertEqual(header.value, "Bearer xai-secret")
    }

    func testDecodesABase64ImageResponse() throws {
        let json = """
        {"created":1,"data":[{"b64_json":"AAAA","revised_prompt":"a red bicycle"}]}
        """
        let decoded = try JSONDecoder().decode(
            OpenAICompatible.ImageResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.data.count, 1)
        XCTAssertEqual(decoded.data[0].b64_json, "AAAA")
        XCTAssertEqual(decoded.data[0].revised_prompt, "a red bicycle")
        XCTAssertNil(decoded.error)
    }

    func testDecodesAUrlOnlyResponse() throws {
        let json = #"{"data":[{"url":"https://cdn.example.com/a.png"}]}"#
        let decoded = try JSONDecoder().decode(
            OpenAICompatible.ImageResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.data[0].url, "https://cdn.example.com/a.png")
        XCTAssertNil(decoded.data[0].b64_json)
    }

    func testDecodesAnErrorEnvelope() throws {
        let json = """
        {"data":[],"error":{"message":"content policy violation","type":"invalid_request","code":"content_policy"}}
        """
        let decoded = try JSONDecoder().decode(
            OpenAICompatible.ImageResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.error?.code, "content_policy")
        XCTAssertTrue(decoded.data.isEmpty)
    }

    /// The formatter's job is turning a provider error into copy a user can act on.
    /// These assertions pin the classification, not the exact wording.
    func testFormatterClassifiesContentPolicyErrors() {
        let message = OpenAICompatible.formatError(
            OpenAICompatible.ErrorDict(message: "Your request violated our content policy",
                      type: "invalid_request", code: "content_policy"))
        XCTAssertFalse(message.isEmpty)
        XCTAssertNotEqual(message, "Your request violated our content policy",
                          "a bare passthrough means the classification was lost")
    }

    func testFormatterHandlesAnEmptyErrorDict() {
        let message = OpenAICompatible.formatError(OpenAICompatible.ErrorDict(message: nil, type: nil, code: nil))
        XCTAssertFalse(message.isEmpty, "an unknown error still needs user-facing copy")
    }
}
