import XCTest
@testable import GenStationCore

final class GrokVideoClientTests: XCTestCase {
    func testVideoBodySeparatesVideoAndImageOptions() throws {
        let body = try GrokVideoClient.requestBody(prompt: "Animate", duration: 5, aspectRatio: "16:9", resolution: "480p", audio: false, imageDataURI: "data:image/png;base64,AAAA")
        XCTAssertEqual(body["model"] as? String, "grok-imagine-video-1.5")
        XCTAssertEqual((body["image"] as? [String: String])?["url"], "data:image/png;base64,AAAA")
        XCTAssertEqual(body["generate_audio"] as? Bool, false)
        XCTAssertNil(body["response_format"])
        XCTAssertThrowsError(try GrokVideoClient.requestBody(prompt: "x", duration: 16, aspectRatio: "16:9", resolution: "480p", audio: true))
        XCTAssertThrowsError(try GrokVideoClient.requestBody(prompt: "x", duration: 5, aspectRatio: "16:9", resolution: "2k", audio: true))
    }

    func testSubmissionAndPollingUseSharedDecoder() throws {
        let submit = try GrokVideoClient.normalizedResponse(Data(#"{"request_id":"job-1"}"#.utf8), submission: true)
        XCTAssertEqual(try JSONDecoder().decode(AIMLEndpoints.VideoGenerationResponse.self, from: submit).id, "job-1")
        for (wire, expected) in [("pending", "processing"), ("done", "completed"), ("failed", "failed"), ("expired", "expired")] {
            let raw = Data("{\"status\":\"\(wire)\",\"video\":{\"url\":\"https://example.com/movie.mp4\"}}".utf8)
            let normalized = try GrokVideoClient.normalizedResponse(raw)
            let response = try JSONDecoder().decode(AIMLEndpoints.VideoPollResponse.self, from: normalized)
            XCTAssertEqual(response.status, expected)
            XCTAssertEqual(response.video?.url, "https://example.com/movie.mp4")
        }
    }

    func testResumeDecoderRecognizesNativeCompletionAndPending() throws {
        let pending = try GrokVideoClient.normalizedResponse(Data(#"{"status":"pending"}"#.utf8))
        guard case .inProgress(let status) = AIMLEndpoints.decodeVideoPoll(pending) else { return XCTFail("Pending job must remain resumable") }
        XCTAssertEqual(status, "processing")
        let done = try GrokVideoClient.normalizedResponse(Data(#"{"status":"done","video":{"url":"https://example.com/movie.mp4"}}"#.utf8))
        guard case .completed(let url, let cost) = AIMLEndpoints.decodeVideoPoll(done) else { return XCTFail("Completed job must download") }
        XCTAssertEqual(url, "https://example.com/movie.mp4")
        XCTAssertNil(cost, "Do not invent an AIMLAPI cost for xAI")
    }

    func testModerationAndErrorResponses() throws {
        let blocked = try GrokVideoClient.normalizedResponse(Data(#"{"status":"done","video":{"url":"https://example.com/movie.mp4","respect_moderation":false}}"#.utf8))
        let response = try JSONDecoder().decode(AIMLEndpoints.VideoPollResponse.self, from: blocked)
        XCTAssertEqual(response.status, "blocked")
        XCTAssertNil(response.video)
        let failed = try GrokVideoClient.normalizedResponse(Data(#"{"status":"failed","error":"Provider failure"}"#.utf8))
        XCTAssertEqual(try JSONDecoder().decode(AIMLEndpoints.VideoPollResponse.self, from: failed).error?.message, "Provider failure")
        XCTAssertThrowsError(try GrokVideoClient.normalizedResponse(Data("[]".utf8)))
    }
    func testNativeVideoReportedChargeSurvivesNormalizationForRecovery() throws {
        for (ticks, expected) in [("12345678901", 1.2345678901), ("0", 0.0)] {
            let raw = Data("{\"status\":\"done\",\"video\":{\"url\":\"https://example.com/movie.mp4\"},\"usage\":{\"cost_in_usd_ticks\":\(ticks)}}".utf8)
            let live = ProviderChargeEvidence.observe(provider: .grok, data: raw, httpStatus: 200).evidence
            XCTAssertEqual(try XCTUnwrap(live).amount.displayUSD, expected, accuracy: 1e-10)
            let normalized = try GrokVideoClient.normalizedResponse(raw)
            guard case .completed(_, let cost) = AIMLEndpoints.decodeVideoPoll(normalized, provider: .grok) else { return XCTFail("Expected completion") }
            XCTAssertEqual(try XCTUnwrap(cost), expected, accuracy: 1e-10)
        }
    }
    func testNativeVideoMissingOrInvalidBillingNeverBecomesZero() throws {
        for usage in ["{}", "{\"cost_in_usd_ticks\":-1}", "{\"cost_in_usd_ticks\":0,\"currency\":\"EUR\"}", "{\"usd_spent\":1.23}"] {
            let raw = Data("{\"status\":\"done\",\"video\":{\"url\":\"https://example.com/movie.mp4\"},\"usage\":\(usage)}".utf8)
            let normalized = try GrokVideoClient.normalizedResponse(raw)
            guard case .completed(_, let cost) = AIMLEndpoints.decodeVideoPoll(normalized, provider: .grok) else { return XCTFail("Expected completion") }
            XCTAssertNil(cost)
        }
    }

}
