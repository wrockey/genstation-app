import XCTest
@testable import GenStationCore

final class WorkflowPromptSafetyTests: XCTestCase {
    private func graph(positive: Any, negative: Any = "gore") -> [String: Any] {
        ["1": ["class_type": "CLIPTextEncode", "inputs": ["text": positive]],
         "2": ["class_type": "CLIPTextEncode", "inputs": ["text": negative]],
         "3": ["class_type": "KSampler", "inputs": ["positive": ["1", 0], "negative": ["2", 0]]],
         "4": ["class_type": "LoadImage", "inputs": ["image": "gore.png"]],
         "5": ["class_type": "UNETLoader", "inputs": ["unet_name": "porn.safetensors"]]]
    }
    func testFingerprintTracksOnlyInspectedPositiveText() {
        let original = WorkflowPromptSafety.inspect(graph(positive: "safe", negative: "gore"))
        XCTAssertEqual(original.positivePromptFingerprint, WorkflowPromptSafety.inspect(graph(positive: "safe", negative: "other negative")).positivePromptFingerprint)
        XCTAssertNotEqual(original.positivePromptFingerprint, WorkflowPromptSafety.inspect(graph(positive: "revised")).positivePromptFingerprint)
    }
    func testSavedPromptWithoutOverrideIsBlocked() {
        let result = WorkflowPromptSafety.inspect(graph(positive: "gore"))
        XCTAssertEqual(result.blocked.map(\.nodeID), ["1"])
        XCTAssertEqual(result.blocked.first?.inputKey, "text")
    }
    func testNegativePromptsAndModelOrImageNamesAreNotPositiveInstructions() throws {
        XCTAssertTrue(try WorkflowPromptSafety.requireSafe(graph(positive: "Ceramic study")).isSafe)
    }
    func testChangedEffectivePromptIsRechecked() throws {
        var prepared = graph(positive: "Ceramic study")
        try WorkflowPromptSafety.requireSafe(prepared)
        prepared["1"] = ["class_type": "CLIPTextEncode", "inputs": ["text": "Ceramic study, gore"]]
        XCTAssertThrowsError(try WorkflowPromptSafety.requireSafe(prepared)) { error in
            XCTAssertTrue(error is WorkflowPromptSafety.Blocked)
        }
    }
    func testSharedPositiveNegativeEncoderStillChecksPositiveText() {
        var prepared = graph(positive: "gore")
        prepared["3"] = ["class_type": "KSampler", "inputs": ["positive": ["1", 0], "negative": ["1", 0]]]
        XCTAssertFalse(WorkflowPromptSafety.inspect(prepared).isSafe)
    }
    func testDynamicTextIsReportedAsUnresolvedRatherThanClaimedInspected() {
        var prepared = graph(positive: ["6", 0])
        prepared["6"] = ["class_type": "CustomPromptBuilder", "inputs": ["template_path": "template.txt"]]
        let report = WorkflowPromptSafety.inspect(prepared)
        XCTAssertTrue(report.isSafe)
        XCTAssertTrue(report.unresolved.contains { $0.contains("1.text") })
        XCTAssertTrue(report.unresolved.contains { $0.contains("CustomPromptBuilder") })
    }
    func testSelectedCustomLiteralBindingAndUnicodeNormalization() {
        var prepared = graph(positive: "Ceramic study")
        prepared["6"] = ["class_type": "CustomString", "inputs": ["value": "p\u{200B}0rn"]]
        XCTAssertTrue(WorkflowPromptSafety.inspect(prepared).isSafe)
        XCTAssertEqual(WorkflowPromptSafety.inspect(prepared, selectedPromptNodeID: "6").blocked.map(\.nodeID), ["6"])
    }
}
