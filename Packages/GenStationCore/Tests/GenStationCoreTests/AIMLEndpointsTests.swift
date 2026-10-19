import XCTest
@testable import GenStationCore

final class AIMLEndpointsTests: XCTestCase {

    func testEndpointsMatchTheLiteralsTheyReplace() {
        XCTAssertEqual(AIMLEndpoints.imagesGenerationsURL.absoluteString,
                       "https://api.aimlapi.com/v1/images/generations")
        XCTAssertEqual(AIMLEndpoints.imagesEditsURL.absoluteString,
                       "https://api.aimlapi.com/v1/images/edits")
        XCTAssertEqual(AIMLEndpoints.videoGenerationsURL.absoluteString,
                       "https://api.aimlapi.com/v2/video/generations")
        XCTAssertEqual(AIMLEndpoints.chatCompletionsURL.absoluteString,
                       "https://api.aimlapi.com/v1/chat/completions")
        XCTAssertEqual(AIMLEndpoints.modelsURL.absoluteString, "https://api.aimlapi.com/models")
        XCTAssertEqual(AIMLEndpoints.balanceURL.absoluteString,
                       "https://billing.aimlapi.com/v1/billing/balance")
        XCTAssertEqual(AIMLEndpoints.balanceFallbackURL.absoluteString,
                       "https://api.aimlapi.com/v1/billing/balance")
        // Embedded in credit-exhaustion copy and in the MCP insufficient_credits payload;
        // tools/genstation-mcp/smoke_test.py asserts this exact string.
        XCTAssertEqual(AIMLEndpoints.billingConsoleURLString, "https://aimlapi.com/app/billing/")
    }

    /// The registry stores endpoints as `String`, so `ModelRegistry.swift`'s 198 literals collapse
    /// onto these string members rather than the `URL` ones above. Each value is a byte-for-byte
    /// copy of the literal it replaced — that is the whole safety argument for the substitution,
    /// so it is asserted rather than assumed.
    func testEndpointStringsMatchTheRegistryLiteralsTheyReplace() {
        XCTAssertEqual(AIMLEndpoints.videoGeneration,
                       "https://api.aimlapi.com/v2/video/generations")
        XCTAssertEqual(AIMLEndpoints.videoGenerationPoll,
                       "https://api.aimlapi.com/v2/video/generations?generation_id=")
        XCTAssertEqual(AIMLEndpoints.imageGeneration,
                       "https://api.aimlapi.com/v1/images/generations")
        XCTAssertEqual(AIMLEndpoints.klingGeneration,
                       "https://api.aimlapi.com/v2/generate/video/kling/generation")
        XCTAssertEqual(AIMLEndpoints.klingGenerationPoll,
                       "https://api.aimlapi.com/v2/generate/video/kling/generation?generation_id=")
        XCTAssertEqual(AIMLEndpoints.providerVideoGeneration(provider: "alibaba"),
                       "https://api.aimlapi.com/v2/generate/video/alibaba/generation")
        XCTAssertEqual(AIMLEndpoints.providerVideoGenerationPoll(provider: "alibaba"),
                       "https://api.aimlapi.com/v2/generate/video/alibaba/generation?generation_id=")
    }

    /// The string members and the `URL` members describe the same endpoints; keep them tied so
    /// a change to one cannot silently leave the other behind.
    func testEndpointStringsAgreeWithTheURLMembers() {
        XCTAssertEqual(AIMLEndpoints.videoGeneration, AIMLEndpoints.videoGenerationsURL.absoluteString)
        XCTAssertEqual(AIMLEndpoints.imageGeneration, AIMLEndpoints.imagesGenerationsURL.absoluteString)
        XCTAssertEqual(AIMLEndpoints.klingGeneration,
                       AIMLEndpoints.videoEndpoint(modelID: "kling/v2-master").absoluteString)
        XCTAssertEqual(AIMLEndpoints.videoGenerationPoll,
                       AIMLEndpoints.pollingEndpoint(for: AIMLEndpoints.videoGenerationsURL))
        XCTAssertEqual(AIMLEndpoints.klingGenerationPoll,
                       AIMLEndpoints.pollingEndpoint(
                           for: AIMLEndpoints.videoEndpoint(modelID: "kling/v2-master")))
    }

    /// The /edits rule, previously implemented in two places that could drift: mask-capable
    /// model AND at least one input image. Everything else generates.
    func testImageEndpointRoutesToEditsOnlyForMaskCapableModelsWithInput() {
        XCTAssertEqual(
            AIMLEndpoints.imageEndpoint(supportsMask: true, hasInputImages: true),
            AIMLEndpoints.imagesEditsURL)
        XCTAssertEqual(
            AIMLEndpoints.imageEndpoint(supportsMask: true, hasInputImages: false),
            AIMLEndpoints.imagesGenerationsURL)
        XCTAssertEqual(
            AIMLEndpoints.imageEndpoint(supportsMask: false, hasInputImages: true),
            AIMLEndpoints.imagesGenerationsURL)
        XCTAssertEqual(
            AIMLEndpoints.imageEndpoint(supportsMask: false, hasInputImages: false),
            AIMLEndpoints.imagesGenerationsURL)
    }

    /// openai/ and google/ models post to the shared v2 video endpoint; everything else
    /// gets a per-provider path built from the first path component of the model id.
    func testVideoEndpointUsesTheSharedPathForOpenAIAndGoogle() {
        XCTAssertEqual(AIMLEndpoints.videoEndpoint(modelID: "openai/sora-2").absoluteString,
                       "https://api.aimlapi.com/v2/video/generations")
        XCTAssertEqual(AIMLEndpoints.videoEndpoint(modelID: "google/veo-3.1").absoluteString,
                       "https://api.aimlapi.com/v2/video/generations")
    }

    func testVideoEndpointSynthesizesAPerProviderPath() {
        XCTAssertEqual(AIMLEndpoints.videoEndpoint(modelID: "kling/v2-master").absoluteString,
                       "https://api.aimlapi.com/v2/generate/video/kling/generation")
        XCTAssertEqual(AIMLEndpoints.videoEndpoint(modelID: "alibaba/wan2.5").absoluteString,
                       "https://api.aimlapi.com/v2/generate/video/alibaba/generation")
    }

    /// A model id with no provider prefix cannot produce a per-provider path; fall back to
    /// the shared endpoint rather than emitting ".../video//generation".
    func testVideoEndpointFallsBackWhenTheModelIDHasNoProviderPrefix() {
        XCTAssertEqual(AIMLEndpoints.videoEndpoint(modelID: "veo-3").absoluteString,
                       "https://api.aimlapi.com/v2/video/generations")
        XCTAssertEqual(AIMLEndpoints.videoEndpoint(modelID: "").absoluteString,
                       "https://api.aimlapi.com/v2/video/generations")
    }

    /// The poll URL is the generation endpoint plus a trailing query the job id appends to —
    /// JobQueue builds `pollingEndpoint + genId`, so the string must end with `=`.
    func testPollingEndpointEndsReadyForAJobIDToBeAppended() {
        let poll = AIMLEndpoints.pollingEndpoint(for: AIMLEndpoints.videoGenerationsURL)
        XCTAssertEqual(poll, "https://api.aimlapi.com/v2/video/generations?generation_id=")
        XCTAssertTrue(poll.hasSuffix("="))
        let kling = AIMLEndpoints.pollingEndpoint(
            for: AIMLEndpoints.videoEndpoint(modelID: "kling/v2-master"))
        XCTAssertEqual(kling,
            "https://api.aimlapi.com/v2/generate/video/kling/generation?generation_id=")
    }

    // MARK: - AIMLEndpoints.friendlyError

    func testCreditExhaustionIsClassifiedAndCarriesTheBillingLink() {
        let body = Data(#"{"message":"Insufficient funds on your balance"}"#.utf8)
        let message = AIMLEndpoints.friendlyError(status: 402, body: body)
        XCTAssertTrue(message.contains("out of API credits"), message)
        XCTAssertTrue(message.contains(AIMLEndpoints.billingConsoleURLString), message)
        // The MCP layer keys its structured error off this classification.
        XCTAssertTrue(AIMLEndpoints.isInsufficientCredits(message))
    }

    func testAPlain403IsNotMisreadAsCreditExhaustion() {
        let message = AIMLEndpoints.friendlyError(
            status: 403, body: Data(#"{"message":"Region not supported"}"#.utf8))
        XCTAssertEqual(message, "Region not supported")
        XCTAssertFalse(AIMLEndpoints.isInsufficientCredits(message))
    }

    func testStatusCodesMapToActionableCopy() {
        XCTAssertTrue(AIMLEndpoints.friendlyError(status: 401, body: Data()).contains("API key"))
        XCTAssertTrue(AIMLEndpoints.friendlyError(status: 429, body: Data()).contains("Rate limited"))
        XCTAssertTrue(AIMLEndpoints.friendlyError(status: 503, body: Data()).contains("server error"))
        XCTAssertTrue(AIMLEndpoints.friendlyError(
            status: 404, body: Data(#"{"message":"model not found"}"#.utf8))
            .contains("isn't available on your plan"))
        XCTAssertTrue(AIMLEndpoints.friendlyError(
            status: 400, body: Data(#"{"message":"flagged by moderation"}"#.utf8))
            .contains("content moderation"))
    }

    func testErrorMessageIsReadFromAllFourJSONShapes() {
        for body in [
            #"{"message":"boom"}"#,
            #"{"error":{"message":"boom"}}"#,
            #"{"error":"boom"}"#,
            #"{"title":"boom"}"#,
        ] {
            XCTAssertEqual(AIMLEndpoints.friendlyError(status: 418, body: Data(body.utf8)), "boom", body)
        }
    }

    // MARK: - cost + poll decoding

    func testUsdSpentIsReadFromBothResponseShapes() {
        XCTAssertEqual(AIMLEndpoints.usdSpent(from: 
            Data(#"{"meta":{"usage":{"usd_spent":0.42}}}"#.utf8)), 0.42)
        XCTAssertEqual(AIMLEndpoints.usdSpent(from: Data(#"{"usage":{"usd_spent":0.07}}"#.utf8)), 0.07)
        XCTAssertNil(AIMLEndpoints.usdSpent(from: Data(#"{"usage":{}}"#.utf8)))
        XCTAssertNil(AIMLEndpoints.usdSpent(from: Data("not json".utf8)))
    }

    func testPollDecodingClassifiesEachOutcome() {
        if case .inProgress(let status) = AIMLEndpoints.decodeVideoPoll(
            Data(#"{"id":"j","status":"generating"}"#.utf8)) {
            XCTAssertEqual(status, "generating")
        } else {
            XCTFail("expected .inProgress")
        }

        if case .completed(let url, let cost) = AIMLEndpoints.decodeVideoPoll(Data(#"""
        {"id":"j","status":"completed","video":{"url":"https://cdn.example.com/v.mp4"},"meta":{"usage":{"usd_spent":0.4}}}
        """#.utf8)) {
            XCTAssertEqual(url, "https://cdn.example.com/v.mp4")
            XCTAssertEqual(cost, 0.4)
        } else {
            XCTFail("expected .completed")
        }

        if case .failed = AIMLEndpoints.decodeVideoPoll(Data(#"{"id":"j","status":"error"}"#.utf8)) {
            // expected
        } else {
            XCTFail("expected .failed for an unrecognized terminal status")
        }
    }

    // MARK: - ImgBB

    func testImgBBUploadURLMatchesTheLiteralItReplaces() {
        XCTAssertEqual(
            ImgBBClient.uploadURL(apiKey: "abc", expirationSeconds: 600).absoluteString,
            "https://api.imgbb.com/1/upload?key=abc&expiration=600")
    }

    /// Two call sites validated the key shape differently (32 hex vs 32 chars); one rule now.
    func testImgBBKeyPlausibilityIs32HexCharacters() {
        XCTAssertTrue(ImgBBClient.isPlausibleKey(String(repeating: "a", count: 32)))
        XCTAssertTrue(ImgBBClient.isPlausibleKey("0123456789abcdef0123456789ABCDEF"))
        XCTAssertFalse(ImgBBClient.isPlausibleKey(String(repeating: "a", count: 31)))
        XCTAssertFalse(ImgBBClient.isPlausibleKey(String(repeating: "z", count: 32)))
        XCTAssertFalse(ImgBBClient.isPlausibleKey(""))
    }
}
