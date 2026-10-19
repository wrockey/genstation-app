import XCTest
@testable import GenStationCore

final class WorkflowOutputRecoveryTests: XCTestCase {
    private func output(_ id: String, kind: String = "images", filename: String = "original.png") -> ComfyUIOutput {
        .init(id: id, nodeID: id, filename: filename, subfolder: "", type: "output", kind: kind)
    }
    private func snapshot() -> WorkflowRecoverySnapshot {
        .init(workflowID: UUID(), workflowRevision: 2, graphDigest: "prepared", serverURL: "https://fixture.invalid",
              selectedOutputNodeID: nil, workflowName: "Fixture", displayPrompt: "Ceramic")
    }
    func testPartialOutputsRetainIDsPathsAndErrorsAcrossRestart() throws {
        var value = snapshot()
        let descriptors = [output("1"), output("2", kind: "videos", filename: "clip.mp4")]
        try value.recordOutputs(descriptors)
        let identities = try XCTUnwrap(value.resultAssets).map(\.assetID)
        XCTAssertEqual(identities.first, value.assetID)
        value.resultAssets?[0].localPath = "/fixture/original.png"
        value.resultAssets?[0].byteCount = 512
        value.resultAssets?[1].errorMessage = "Download unavailable"
        var decoded = try JSONDecoder().decode(WorkflowRecoverySnapshot.self, from: JSONEncoder().encode(value))
        try decoded.recordOutputs(descriptors)
        XCTAssertEqual(decoded.resultAssets?.map(\.assetID), identities)
        XCTAssertEqual(decoded.resultAssets?[0].localPath, "/fixture/original.png")
        XCTAssertEqual(decoded.resultAssets?[1].errorMessage, "Download unavailable")
        XCTAssertThrowsError(try decoded.recordOutputs([output("changed")]))
        XCTAssertEqual(decoded.resultAssets, value.resultAssets)
    }
    func testOutputCountAndDuplicateDescriptorLimits() {
        var value = snapshot()
        XCTAssertThrowsError(try value.recordOutputs([]))
        XCTAssertThrowsError(try value.recordOutputs([output("same"), output("same")]))
        XCTAssertThrowsError(try value.recordOutputs((0..<13).map { output(String($0)) }))
        XCTAssertNil(value.resultAssets)
    }
    func testSelectedOutputNodesKeepDeterministicMixedMediaOrder() {
        let entry: [String: Any] = ["outputs": [
            "20": ["videos": [["filename": "clip.mp4"]]],
            "10": ["images": [["filename": "a.png"], ["filename": "b.png"]]],
            "30": ["images": [["filename": "excluded.png"]]]]]
        let result = ComfyUITransport.outputs(in: entry, selectedNodeID: "30", selectedNodeIDs: ["20", "10"])
        XCTAssertEqual(result.map(\.filename), ["a.png", "b.png", "clip.mp4"])
        XCTAssertEqual(result.map(\.isVideo), [false, false, true])
    }
    func testLegacySnapshotDecodesWithoutNewResultsOrInputs() throws {
        let data = try JSONEncoder().encode(snapshot())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["resultAssets", "inputAssets", "selectedOutputNodeIDs", "submittedGraphDigest"] { object.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(WorkflowRecoverySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.resultAssets)
        XCTAssertNil(restored.inputAssets)
    }
    func testHistoryRoundTripKeepsLegacyAndMultipleParents() throws {
        let parent = UUID(), other = UUID()
        var item = HistoryItem(prompt: "Ceramic", date: Date(), parentItemId: parent)
        item.parentAssetIDs = [parent, other]; item.sourceWorkflowID = UUID(); item.sourceWorkflowRevision = 3
        item.workflowInputs = ["seed": .integer(271828), "reference": .text("asset:" + parent.uuidString)]
        let decoded = try JSONDecoder().decode(HistoryItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.parentItemId, parent)
        XCTAssertEqual(decoded.parentAssetIDs, [parent, other])
        XCTAssertEqual(decoded.sourceWorkflowID, item.sourceWorkflowID)
        XCTAssertEqual(decoded.sourceWorkflowRevision, 3)
        XCTAssertEqual(decoded.workflowInputs, item.workflowInputs)
    }
}
