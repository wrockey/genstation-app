import XCTest
@testable import GenStationCore

final class WorkflowExposedInputTests: XCTestCase {
    func testNamedContractRequiresRevisionDigestAndRejectsNestedValues() throws {
        let base: [String: Any] = ["workflow_id": UUID().uuidString, "workflow_revision": 2,
            "workflow_digest": String(repeating: "a", count: 64), "inputs": ["subject": "Ceramic study"]]
        let contract = try AgentWorkflowContract(base, submitting: false)
        XCTAssertEqual(contract.inputs, ["subject": .text("Ceramic study")])
        var missing = base; missing.removeValue(forKey: "workflow_revision")
        XCTAssertThrowsError(try AgentWorkflowContract(missing, submitting: false))
        var nested = base; nested["inputs"] = ["subject": ["node": "1"]]
        XCTAssertThrowsError(try AgentWorkflowContract(nested, submitting: false))
        var bool = base; bool["workflow_revision"] = true
        XCTAssertThrowsError(try AgentWorkflowContract(bool, submitting: false))
    }

    func testNamedCustomPromptIsFilteredAfterDefaultAndOverrideResolution() {
        var definition = prompt; definition.defaultValue = .text("gore")
        XCTAssertThrowsError(try WorkflowInputResolver.resolve([:], definitions: [definition], graph: graph, objectInfo: info)) { error in
            XCTAssertTrue(error is WorkflowPromptSafety.Blocked)
        }
        XCTAssertThrowsError(try WorkflowInputResolver.resolve(["subject": .text("p0rn")], definitions: [prompt], graph: graph, objectInfo: info))
        var effectiveGUI = graph
        effectiveGUI["1"] = ["class_type": "Text", "inputs": ["text": "p0rn"]]
        XCTAssertThrowsError(try WorkflowInputResolver.checkPromptValues(in: effectiveGUI, definitions: [prompt]))
    }

    func testInterruptedUploadCannotBecomeAnUncertainGeneration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("jobs.json")
        var ledger = AgentImageLedger()
        var job = try ledger.register(requestID: "upload-test", arguments: ["workflow_id": "fixture"], at: url)
        job.status = "uploading"
        job.workflow = WorkflowRecoverySnapshot(workflowID: nil, workflowRevision: 1, graphDigest: "fixture", serverURL: "https://fixture.invalid", selectedOutputNodeID: nil, workflowName: "Fixture", displayPrompt: "Ceramic")
        try ledger.update(job, at: url)
        let restored = try AgentImageLedger.load(from: url)
        XCTAssertEqual(restored.jobs[job.id]?.status, "failed")
        XCTAssertEqual(restored.jobs[job.id]?.billing, "not_submitted")
        XCTAssertNil(restored.jobs[job.id]?.workflow?.promptID)
        XCTAssertEqual(try restored.existing(requestID: "upload-test", arguments: ["workflow_id": "fixture"])?.id, job.id)
    }
    private var graph: [String: Any] {
        ["1": ["class_type": "Text", "inputs": ["text": "Saved ceramic study"]],
         "2": ["class_type": "LoadImage", "inputs": ["image": "existing.png"]],
         "3": ["class_type": "Latent", "inputs": ["width": 1024]]]
    }
    private var info: [String: Any] {
        ["Text": ["input": ["required": ["text": ["STRING", [:]]]]],
         "LoadImage": ["input": ["required": ["image": ["COMBO", ["options": ["existing.png"], "image_upload": true]]]]],
         "Latent": ["input": ["required": ["width": ["INT", ["min": 64, "max": 8192]]]]]]
    }
    private var prompt: WorkflowExposedInput {
        .init(name: "subject", label: "Subject", kind: .prompt, nodeID: "1", nodeType: "Text", inputKey: "text")
    }
    func testResolveDeclaredValuesAndKeepImagePreflightNonmutating() throws {
        let image = WorkflowExposedInput(name: "reference", label: "Reference", kind: .image, nodeID: "2", nodeType: "LoadImage", inputKey: "image")
        let reference = "asset:" + UUID().uuidString
        let resolved = try WorkflowInputResolver.resolve(["subject": .text("New subject"), "reference": .text(reference)], definitions: [prompt, image], graph: graph, objectInfo: info)
        XCTAssertEqual(((resolved.graph["1"] as? [String: Any])?["inputs"] as? [String: Any])?["text"] as? String, "New subject")
        XCTAssertEqual(((resolved.graph["2"] as? [String: Any])?["inputs"] as? [String: Any])?["image"] as? String, "existing.png")
        XCTAssertEqual(resolved.imageReferences, ["reference": reference])
        XCTAssertNil(image.publicSchema["nodeID"])
    }
    func testMissingUnknownAndWrongTypeInputsFail() {
        for values: [String: WorkflowInputValue] in [[:], ["subject": .integer(3)], ["undeclared": .text("value")]] {
            XCTAssertThrowsError(try WorkflowInputResolver.resolve(values, definitions: [prompt], graph: graph, objectInfo: info))
        }
    }
    func testDefaultsOptionalValuesAndSavedRanges() throws {
        var subject = prompt; subject.defaultValue = .text("Default")
        let width = WorkflowExposedInput(name: "width", label: "Width", kind: .width, nodeID: "3", nodeType: "Latent", inputKey: "width", required: false, minimum: 512, maximum: 2048, choices: [.integer(512), .integer(1024)])
        let resolved = try WorkflowInputResolver.resolve([:], definitions: [subject, width], graph: graph, objectInfo: info)
        XCTAssertEqual(resolved.effectiveValues, ["subject": .text("Default")])
        for value in [Int64(64), 768, 4096] {
            XCTAssertThrowsError(try WorkflowInputResolver.resolve(["width": .integer(value)], definitions: [subject, width], graph: graph, objectInfo: info))
        }
    }
    func testLinkedDuplicateAndChangedNodeBindingsFail() {
        var linked = graph; linked["1"] = ["class_type": "Text", "inputs": ["text": ["2", 0]]]
        XCTAssertThrowsError(try WorkflowInputResolver.validateDefinitions([prompt], graph: linked, objectInfo: info))
        XCTAssertThrowsError(try WorkflowInputResolver.validateDefinitions([prompt, prompt], graph: graph, objectInfo: info))
        var changed = prompt; changed.nodeType = "DifferentVersion"
        XCTAssertThrowsError(try WorkflowInputResolver.validateDefinitions([changed], graph: graph, objectInfo: info))
        changed = prompt; changed.name = "node.inputs.text"
        XCTAssertThrowsError(try WorkflowInputResolver.validateDefinitions([changed], graph: graph, objectInfo: info))
    }
    func testImageReferencesRejectPathsURLsAndDataURIs() {
        let image = WorkflowExposedInput(name: "reference", label: "Reference", kind: .image, nodeID: "2", nodeType: "LoadImage", inputKey: "image")
        for value in ["/tmp/private.png", "https://example.com/image.png", "data:image/png;base64,AAAA", "asset:invalid"] {
            XCTAssertThrowsError(try image.validateValue(.text(value)))
        }
    }
    func testPromptAndSeedRolesCannotExposeFileSelectorsOrBatchControls() {
        let unsafeGraph: [String: Any] = ["1": ["class_type": "SaveImage", "inputs": ["filename_prefix": "saved"]],
            "2": ["class_type": "Latent", "inputs": ["batch_size": 1]]]
        let unsafeInfo: [String: Any] = ["SaveImage": ["input": ["required": ["filename_prefix": ["STRING", [:]]]]],
            "Latent": ["input": ["required": ["batch_size": ["INT", [:]]]]]]
        let filename = WorkflowExposedInput(name: "subject", label: "Subject", kind: .prompt, nodeID: "1", nodeType: "SaveImage", inputKey: "filename_prefix")
        let batch = WorkflowExposedInput(name: "seed", label: "Seed", kind: .seed, nodeID: "2", nodeType: "Latent", inputKey: "batch_size")
        XCTAssertThrowsError(try WorkflowInputResolver.validateDefinitions([filename], graph: unsafeGraph, objectInfo: unsafeInfo))
        XCTAssertThrowsError(try WorkflowInputResolver.validateDefinitions([batch], graph: unsafeGraph, objectInfo: unsafeInfo))
    }
    func testJSONNumbersRejectBooleansFractionsAndUnsafeIntegerPrecision() throws {
        for value: Any in [true, 1.5, Double.infinity, 9_007_199_254_740_992.0, ["value": 1]] {
            XCTAssertThrowsError(try WorkflowInputValue.parse(value))
        }
        XCTAssertEqual(try WorkflowInputValue.parse(1024), .integer(1024))
    }
    func testSavedDefinitionsSurviveUpdateAndLegacyDecoding() throws {
        let original = SavedWorkflow(name: "Named", workflowJSON: Data("{}".utf8), exposedInputs: [prompt])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(SavedWorkflow.self, from: data).exposedInputs, [prompt])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "exposedInputs"); object.removeValue(forKey: "exposedInputVersion")
        let legacy = try JSONDecoder().decode(SavedWorkflow.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(legacy.exposedInputs.isEmpty)
        object["exposedInputVersion"] = 999
        XCTAssertThrowsError(try JSONDecoder().decode(SavedWorkflow.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testLibraryUpgradesEnvelopeAndPreservesMappingsOnRevision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workflows_v1.json")
        let original = SavedWorkflow(name: "Named", workflowJSON: Data("{}".utf8), exposedInputs: [prompt], outputNodeIDs: ["10", "20"])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original))
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "workflows": [encoded]]).write(to: url)
        var store = try WorkflowLibraryStore(fileURL: url)
        let updated = try store.save(original, replacingID: original.id)
        XCTAssertEqual(updated.revision, 2)
        XCTAssertEqual(updated.exposedInputs, [prompt])
        XCTAssertEqual(updated.outputNodeIDs, ["10", "20"])
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(envelope["schemaVersion"] as? Int, 2)
        XCTAssertEqual(try WorkflowLibraryStore(fileURL: url).workflows.first, updated)
    }
}
