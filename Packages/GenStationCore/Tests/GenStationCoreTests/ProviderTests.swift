import XCTest
@testable import GenStationCore

final class ProviderTests: XCTestCase {

    /// These four strings are written into history_v2.json and into exported history
    /// packages. If this test fails, a rename has silently broken every existing file.
    func testRawValuesAreTheFrozenOnDiskContract() {
        XCTAssertEqual(Provider.gemini.rawValue, "gemini")
        XCTAssertEqual(Provider.comfyUI.rawValue, "comfyUI")
        XCTAssertEqual(Provider.grok.rawValue, "grok")
        XCTAssertEqual(Provider.aimlapi.rawValue, "aimlapi")
        XCTAssertEqual(Provider.allCases.count, 4)
    }

    func testDecodesFromTheOnDiskRawValues() throws {
        let json = Data(#"["gemini","comfyUI","grok","aimlapi"]"#.utf8)
        let decoded = try JSONDecoder().decode([Provider].self, from: json)
        XCTAssertEqual(decoded, [.gemini, .comfyUI, .grok, .aimlapi])
    }

    func testEncodesBackToTheSameRawValues() throws {
        let data = try JSONEncoder().encode([Provider.aimlapi, .comfyUI])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["aimlapi","comfyUI"]"#)
    }

    /// An unrecognized raw must be rejected by the enum itself — leniency belongs in
    /// HistoryItem's decoder (Task 7), not here, so a typo in code still fails loudly.
    func testUnknownRawValueIsRejected() {
        XCTAssertNil(Provider(rawValue: "midjourney"))
        XCTAssertNil(Provider(rawValue: "Gemini"))
    }

    /// Reproduces the copy the settings panel and help sheet build today.
    func testDisplayNameMatchesExistingUICopy() {
        XCTAssertEqual(Provider.gemini.displayName, "Gemini")
        XCTAssertEqual(Provider.grok.displayName, "Grok")
        XCTAssertEqual(Provider.comfyUI.displayName, "ComfyUI")
        XCTAssertEqual(Provider.aimlapi.displayName, "AI/ML API")
    }
}
