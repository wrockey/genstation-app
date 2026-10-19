// WorkflowLibrary.swift — observable adapter around durable core persistence.
import Foundation
import SwiftUI
import GenStationCore

class WorkflowLibrary: ObservableObject {
    static let shared = WorkflowLibrary()
    @Published private(set) var workflows: [SavedWorkflow] = []
    @Published private(set) var storageError: String?
    private var store: WorkflowLibraryStore?

    init() {
        do {
            let loaded = try WorkflowLibraryStore(
                fileURL: AppStorageContext.current.supportDirectory.appendingPathComponent("workflows_v1.json"),
                legacyData: AppStorageContext.defaults.data(forKey: "savedComfyWorkflows"))
            store = loaded
            workflows = loaded.workflows
        } catch {
            storageError = "Workflow library could not be loaded. Existing data was left untouched. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveWorkflow(name: String, workflowJSON: [String: Any], promptNodeID: String?,
                      outputNodeID: String?, imageNodeIDs: Set<String>,
                      additionalInputs: [AdditionalInput] = [], replacingID: UUID? = nil,
                      exposedInputs: [WorkflowExposedInput]? = nil, outputNodeIDs: [String]? = nil) throws -> SavedWorkflow {
        let workflow = SavedWorkflow(name: name, workflowJSON: try JSONSerialization.data(withJSONObject: workflowJSON, options: .sortedKeys),
            promptNodeID: promptNodeID, outputNodeID: outputNodeID, imageNodeIDs: imageNodeIDs.sorted(),
            additionalInputs: additionalInputs.isEmpty ? nil : additionalInputs,
            exposedInputs: exposedInputs ?? replacingID.flatMap { id in workflows.first { $0.id == id }?.exposedInputs } ?? [],
            outputNodeIDs: outputNodeIDs ?? replacingID.flatMap { id in workflows.first { $0.id == id }?.outputNodeIDs } ?? [])
        return try mutate { try $0.save(workflow, replacingID: replacingID) }
    }

    func saveExposedInputs(_ definitions: [WorkflowExposedInput], for expected: SavedWorkflow,
                           preparedGraph: [String: Any], objectInfo: [String: Any], outputNodeIDs: [String]? = nil) throws {
        guard workflows.first(where: { $0.id == expected.id }) == expected else {
            throw AgentImageError("Workflow changed while editing inputs. Reopen the editor before saving.")
        }
        try WorkflowInputResolver.validateDefinitions(definitions, graph: preparedGraph, objectInfo: objectInfo)
        var updated = expected
        updated.exposedInputs = definitions
        if let outputNodeIDs {
            guard outputNodeIDs.count <= 4, Set(outputNodeIDs).count == outputNodeIDs.count,
                  outputNodeIDs.allSatisfy({ id in
                      guard let node = preparedGraph[id] as? [String: Any], let type = node["class_type"] as? String,
                            let info = objectInfo[type] as? [String: Any] else { return false }
                      return info["output_node"] as? Bool == true
                  }) else { throw AgentImageError("Select at most four server-declared output nodes.") }
            updated.outputNodeIDs = outputNodeIDs
        }
        try mutate { try $0.save(updated, replacingID: expected.id) }
    }

    func markAsUsed(_ workflow: SavedWorkflow) {
        do { try mutate { try $0.markUsed(id: workflow.id) } } catch { /* Published error is shown by the configuration view. */ }
    }
    func deleteWorkflow(_ workflow: SavedWorkflow) {
        do { try mutate { try $0.delete(id: workflow.id) } } catch { }
    }
    func renameWorkflow(_ workflow: SavedWorkflow, to name: String) {
        do { try mutate { try $0.rename(id: workflow.id, to: name) } } catch { }
    }
    func getWorkflowJSON(_ workflow: SavedWorkflow) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: workflow.workflowJSON) as? [String: Any]
    }
    var sortedWorkflows: [SavedWorkflow] { store?.sortedWorkflows ?? [] }
    var recentWorkflows: [SavedWorkflow] { store?.recentWorkflows ?? [] }

    private func mutate<T>(_ operation: (inout WorkflowLibraryStore) throws -> T) throws -> T {
        do {
            guard var next = store else { throw AgentImageError("Repair the unreadable workflow library before making changes.") }
            let result = try operation(&next)
            store = next
            workflows = next.workflows
            storageError = nil
            return result
        } catch {
            storageError = "Workflow library could not be saved. \(error.localizedDescription)"
            throw error
        }
    }
}
