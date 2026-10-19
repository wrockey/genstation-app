import XCTest
@testable import GenStationCore

final class AgentWorkflowTests: XCTestCase {
    private let definitions: [String: Any] = [
        "Text": ["input": ["required": ["text": ["STRING"]]], "output": ["STRING"]],
        "Render": ["input": ["required": ["prompt": ["STRING"], "steps": ["INT", ["min": 1, "max": 40]],
                                              "model": [["installed"]], "enabled": ["BOOLEAN"]]], "output": ["IMAGE"]],
    ]
    private var graph: [String: Any] { [
        "1": ["class_type": "Text", "inputs": ["text": "lighthouse"]],
        "2": ["class_type": "Render", "inputs": ["prompt": ["1", 0], "steps": 20, "model": "installed", "enabled": true]],
    ] }
    func testSavedIdentityAndNoAgentGraphOrPath() throws {
        let args: [String: Any] = ["workflow_id": UUID().uuidString, "request_id": "demo", "prompt": "lighthouse"]
        XCTAssertNoThrow(try AgentWorkflowContract(args, submitting: true))
        for key in ["workflow_json", "workflow_name", "server_url", "input_images", "node_overrides"] {
            var invalid = args; invalid[key] = "untrusted"
            XCTAssertThrowsError(try AgentWorkflowContract(invalid, submitting: true), key)
        }
        var missing = args; missing.removeValue(forKey: "request_id")
        XCTAssertThrowsError(try AgentWorkflowContract(missing, submitting: true))
        XCTAssertNoThrow(try AgentWorkflowContract(missing, submitting: false))
        for invalid: Any in [true, "", String(repeating: "é", count: 16_001)] {
            var bad = args; bad["prompt"] = invalid
            XCTAssertThrowsError(try AgentWorkflowContract(bad, submitting: true))
        }
    }
    func testLiveSchemaChecksValuesAndLinks() throws {
        XCTAssertNoThrow(try AgentWorkflowContract.validate(graph, objectInfo: definitions))
        for (key, badValue) in [("steps", true as Any), ("steps", 41), ("steps", 1.5), ("model", "missing"), ("enabled", 1), ("prompt", ["missing", 0]), ("prompt", ["1", 99]), ("prompt", ["2", 0]), ("extra", "no")] {
            var bad = graph
            var node = bad["2"] as! [String: Any]
            var inputs = node["inputs"] as! [String: Any]; inputs[key] = badValue
            node["inputs"] = inputs; bad["2"] = node
            XCTAssertThrowsError(try AgentWorkflowContract.validate(bad, objectInfo: definitions), key)
        }
        XCTAssertThrowsError(try AgentWorkflowContract.validate(graph, objectInfo: [:]))
        var missing = graph; missing["1"] = ["class_type": "NotInstalled", "inputs": [:]]
        XCTAssertThrowsError(try AgentWorkflowContract.validate(missing, objectInfo: definitions))
    }
    func testModernComboOptionsRemainBoundedToServerChoices() throws {
        let schema: [String: Any] = ["Loader": ["input": ["required": [
            "model": ["COMBO", ["options": ["installed.safetensors"], "multiselect": false]]
        ]], "output": ["MODEL"]]]
        func workflow(_ value: Any) -> [String: Any] {
            ["1": ["class_type": "Loader", "inputs": ["model": value]]]
        }
        XCTAssertNoThrow(try AgentWorkflowContract.validate(workflow("installed.safetensors"), objectInfo: schema))
        for value: Any in ["missing.safetensors", true, ["path": "installed.safetensors"], ["installed.safetensors"]] {
            XCTAssertThrowsError(try AgentWorkflowContract.validate(workflow(value), objectInfo: schema))
        }
        let missingOptions: [String: Any] = ["Loader": ["input": ["required": ["model": ["COMBO"]]], "output": ["MODEL"]]]
        XCTAssertThrowsError(try AgentWorkflowContract.validate(workflow("anything"), objectInfo: missingOptions))
    }

    func testCyclesAreRejectedBeforeServerSubmission() {
        let loop: [String: Any] = ["1": ["class_type": "Text", "inputs": ["text": ["1", 0]]]]
        XCTAssertThrowsError(try AgentWorkflowContract.validate(loop, objectInfo: definitions))
    }
    func testPromptOverrideNeverReplacesLinksOrAmbiguousFields() {
        let def = ["input": ["required": ["text": ["STRING"], "prompt": ["STRING"]]]]
        XCTAssertEqual(AgentWorkflowContract.promptKey(node: ["inputs": ["text": "original"]], definition: def), "text")
        XCTAssertNil(AgentWorkflowContract.promptKey(node: ["inputs": ["text": ["1", 0]]], definition: def))
        XCTAssertNil(AgentWorkflowContract.promptKey(node: ["inputs": ["text": "a", "prompt": "b"]], definition: def))
        XCTAssertNil(AgentWorkflowContract.promptKey(node: ["inputs": ["file": "path"]], definition: def))
    }
    func testWorkflowRequestReplayPersistsWithoutAutomaticResubmission() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("workflows.json")
        let args: [String: Any] = ["workflow_id": UUID().uuidString, "prompt": "lighthouse", "request_id": "demo"]
        var ledger = AgentImageLedger()
        var job = try ledger.register(requestID: "demo", arguments: args, at: file)
        job.status = "submitting"; job.billing = "unknown"
        try ledger.update(job, at: file)
        var restored = try AgentImageLedger.load(from: file)
        let replay = try restored.register(requestID: "demo", arguments: args, at: file)
        XCTAssertEqual(replay.id, job.id); XCTAssertEqual(replay.status, "interrupted")
        XCTAssertEqual(replay.billing, "unknown")
        var changed = args; changed["prompt"] = "new prompt"
        XCTAssertThrowsError(try restored.register(requestID: "demo", arguments: changed, at: file))
    }
}
