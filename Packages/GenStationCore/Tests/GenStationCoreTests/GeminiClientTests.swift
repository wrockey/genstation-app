import XCTest
@testable import GenStationCore

final class GeminiClientTests: XCTestCase {

    func testGenerateContentURLMatchesTheLiteralItReplaces() {
        let url = GeminiClient.generateContentURL(model: "gemini-3-pro-image-preview", apiKey: "K")
        XCTAssertEqual(url.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image-preview:generateContent?key=K")
    }

    func testModelsURLMatchesBothFormsInUse() {
        XCTAssertEqual(GeminiClient.modelsURL(apiKey: "K").absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models?key=K")
        XCTAssertEqual(GeminiClient.modelsURL(apiKey: "K", pageSize: 1).absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1&key=K")
    }

    /// The model id contains a colon before `generateContent`, which must survive as a
    /// literal — percent-encoding it produces a 404.
    func testTheGenerateContentColonIsNotPercentEncoded() {
        let url = GeminiClient.generateContentURL(model: "gemini-2.0-flash", apiKey: "K")
        XCTAssertTrue(url.absoluteString.contains("gemini-2.0-flash:generateContent"),
                      url.absoluteString)
        XCTAssertFalse(url.absoluteString.contains("%3AgenerateContent"), url.absoluteString)
    }

    func testAKeyWithURLUnsafeCharactersIsEncodedInTheQuery() {
        let url = GeminiClient.generateContentURL(model: "m", apiKey: "a+b/c=d")
        XCTAssertFalse(url.absoluteString.hasSuffix("a+b/c=d"),
                       "an unencoded key silently truncates at the +")
    }

    func testRequestBodyEncodesPromptAndInlineImages() throws {
        let request = GeminiClient.GenerateContentRequest(
            contents: [GeminiClient.Content(parts: [
                GeminiClient.Part(text: "a red bicycle", inlineData: nil),
                GeminiClient.Part(text: nil, inlineData: GeminiClient.InlineData(mimeType: "image/jpeg", data: "AAAA")),
            ])],
            generationConfig: GeminiClient.GeminiGenerationConfig(
                imageConfig: GeminiClient.GeminiImageConfig(aspectRatio: "16:9", imageSize: "2K")))
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("a red bicycle"), json)
        // JSONEncoder escapes "/" as "\/" by default (valid per the JSON spec), so accept either form.
        XCTAssertTrue(json.contains("image/jpeg") || json.contains("image\\/jpeg"), json)
        XCTAssertTrue(json.contains("16:9"), json)
    }

    func testBlockReasonProducesActionableCopy() {
        let message = GeminiClient.formatBlockReason("SAFETY", safetyRatings: nil, finishMessage: nil)
        XCTAssertFalse(message.isEmpty)
        XCTAssertNotEqual(message, "SAFETY", "the raw enum name is not user-facing copy")
    }

    func testBlockReasonIncludesTheProvidersFinishMessageWhenGiven() {
        let message = GeminiClient.formatBlockReason(
            "PROHIBITED_CONTENT", safetyRatings: nil,
            finishMessage: "The request mentioned a real person.")
        XCTAssertTrue(message.contains("real person"), message)
    }

    /// One predicate, two readers. `GeminiAdvancedSettingsView.supportsResolution` decides whether
    /// the Image Resolution card is drawn and `ContentView+Generation` decides whether
    /// `generationConfig.imageConfig.imageSize` goes on the wire. They used to be two different
    /// substring tests, and every served Gemini id outside the four the fetch prioritises fell in
    /// the gap: no control, key sent anyway. The view's narrower answer is the one that wins, so a
    /// hidden control can never reach the wire (drift ledger § A.12).
    func testOnlyTheModelsThatShowAResolutionControlAcceptImageSize() {
        XCTAssertTrue(GeminiClient.supportsImageSize(modelID: "gemini-3-pro-image"))
        XCTAssertTrue(GeminiClient.supportsImageSize(modelID: "gemini-3-pro-image-preview"))
        XCTAssertTrue(GeminiClient.supportsImageSize(modelID: "gemini-3.1-flash-image"))

        XCTAssertFalse(GeminiClient.supportsImageSize(modelID: "gemini-2.5-flash-image"))
        XCTAssertFalse(GeminiClient.supportsImageSize(modelID: "gemini-2.5-flash-image-preview"))

        // The id the two old predicates disagreed about: the view hid the control and the request
        // builder sent `imageSize` regardless.
        XCTAssertFalse(
            GeminiClient.supportsImageSize(modelID: "gemini-2.0-flash-preview-image-generation"))
    }

    /// Case-insensitive, because the two predicates it replaces were not: the view lowercased its
    /// id and the request builder compared the raw string.
    func testTheImageSizePredicateIgnoresCase() {
        XCTAssertTrue(GeminiClient.supportsImageSize(modelID: "GEMINI-3-PRO-IMAGE-PREVIEW"))
        XCTAssertFalse(GeminiClient.supportsImageSize(modelID: "GEMINI-2.5-FLASH-IMAGE"))
    }
}
