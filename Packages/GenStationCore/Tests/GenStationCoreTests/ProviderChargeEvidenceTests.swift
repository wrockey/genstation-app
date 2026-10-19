import XCTest
@testable import GenStationCore

final class ProviderChargeEvidenceTests: XCTestCase {
    func testExactUSDAndOverflow() throws {
        XCTAssertEqual(try ExactUSD(decimal: "25").ticks, 250_000_000_000)
        XCTAssertEqual(try ExactUSD(decimal: "0.0000000001").ticks, 1)
        XCTAssertEqual(try ExactUSD(decimal: "1.2345678912").decimal, "1.2345678912")
        for value in ["-1", "NaN", "Infinity", "1e3", "0.00000000001", "1844674408"] { XCTAssertThrowsError(try ExactUSD(decimal: value)) }
        XCTAssertThrowsError(try ExactUSD(ticks: .max).adding(ExactUSD(ticks: 1)))
    }
    func testIntegerTicksDoNotLosePrecisionAndChargedFailureIsRetained() throws {
        let result = ProviderChargeEvidence.observe(provider: .grok, data: Data(#"{"usage":{"cost_in_usd_ticks":9007199254740993}}"#.utf8), httpStatus: 500)
        let evidence = try XCTUnwrap(result.evidence)
        XCTAssertEqual(evidence.amount.ticks, 9_007_199_254_740_993)
        XCTAssertEqual(evidence.httpStatus, 500)
        XCTAssertEqual(evidence.json["usd_ticks"] as? String, "9007199254740993")
        XCTAssertEqual(try JSONDecoder().decode(ProviderChargeEvidence.self, from: JSONEncoder().encode(evidence)), evidence)
    }
    func testAIMLExactDecimalsAndZeroDifferFromMissing() throws {
        let data = Data(#"{"meta":{"usage":{"usd_spent":0.1234567891}}}"#.utf8)
        XCTAssertEqual(ProviderChargeEvidence.observe(provider: .aimlapi, data: data, httpStatus: 200).evidence?.amount.ticks, 1_234_567_891)
        XCTAssertEqual(ProviderChargeEvidence.observe(provider: .aimlapi, data: Data(#"{"usage":{"usd_spent":0}}"#.utf8), httpStatus: 400).evidence?.amount.ticks, 0)
        XCTAssertNil(ProviderChargeEvidence.observe(provider: .aimlapi, data: Data("{}".utf8), httpStatus: 200).evidence)
        XCTAssertNil(ProviderChargeEvidence.observe(provider: .gemini, data: data, httpStatus: 200).evidence)
    }
    func testRejectsMalformedCurrencyConflictsAndOutOfRangeUsage() {
        for raw in [#"{"usage":{"usd_spent":true}}"#, #"{"usage":{"usd_spent":-1}}"#,
                    #"{"usage":{"usd_spent":"1"}}"#, #"{"usage":{"usd_spent":1,"currency":"EUR"}}"#,
                    #"{"usage":{"usd_spent":1},"meta":{"usage":{"usd_spent":2}}}"#,
                    #"{"usage":{"usd_spent":0.00000000001}}"#] {
            XCTAssertNil(ProviderChargeEvidence.observe(provider: .aimlapi, data: Data(raw.utf8), httpStatus: 200).evidence, raw)
        }
        for raw in [#"{"usage":{"cost_in_usd_ticks":1.5}}"#, #"{"usage":{"cost_in_usd_ticks":true}}"#,
                    #"{"usage":{"cost_in_usd_ticks":-1}}"#, #"{"usage":{"cost_in_usd_ticks":18446744073709551616}}"#] {
            XCTAssertNil(ProviderChargeEvidence.observe(provider: .grok, data: Data(raw.utf8), httpStatus: 200).evidence, raw)
        }
    }
}
