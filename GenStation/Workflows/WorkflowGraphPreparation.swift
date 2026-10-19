import Foundation
import GenStationCore

/// GUI and MCP share graph preparation, prompt policy and live schema validation.
/// Only GET node-definition requests occur here; callers resolve local asset scope.
@MainActor enum WorkflowGraphPreparation {
    enum Failure: LocalizedError {
        case contentFiltered([PromptSafetyPolicy.FilterReason])
        case serverUnavailable(String)
        var errorDescription: String? {
            switch self {
            case .contentFiltered: return "Positive workflow prompt was blocked by the content filter. No upload or generation was submitted."
            case .serverUnavailable(let detail): return "Cannot read live ComfyUI node definitions. \(detail) No workflow was submitted."
            }
        }
    }
    struct Result {
        let saved: SavedWorkflow
        let server: String
        let url: URL
        let graph: [String: Any]
        let promptKey: String?
        let prompt: String?
        let nodes: [String]
        let promptInspectionLimitations: [String]
        let imageReferences: [String: String]
        let effectiveValues: [String: WorkflowInputValue]
        let usedLegacyOverride: Bool
    }
    static func prepare(saved: SavedWorkflow, serverURL: String, contract: AgentWorkflowContract) async throws -> Result {
        guard saved.id == contract.workflowID,
              let raw = try JSONSerialization.jsonObject(with: saved.workflowJSON) as? [String: Any] else { throw AgentImageError("Saved workflow is unavailable.") }
        guard contract.workflowRevision.map({ $0 == saved.revision }) ?? true,
              contract.workflowDigest.map({ $0 == saved.graphDigest }) ?? true else {
            throw AgentImageError("Workflow revision or graph changed. Rediscover and validate before requesting approval.")
        }
        if contract.prompt != nil && saved.exposedInputs.contains(where: { $0.kind == .prompt }) {
            throw AgentImageError("This workflow exposes named prompt inputs. Use inputs instead of the legacy prompt argument.")
        }
        if let prompt = contract.prompt, !PromptSafetyPolicy.isPromptSafe(prompt).isSafe {
            throw Failure.contentFiltered(PromptSafetyPolicy.filterReasons(prompt))
        }
        let server = try ComfyUITransport(serverURL: serverURL).serverURL
        guard let url = URL(string: server) else { throw AgentImageError("Invalid ComfyUI server.") }
        // GET-only preparation. Do not silently validate against empty/stale definitions.
        let info: [String: Any]
        do { info = try await ComfyUIFormatConverter.fetchAndCacheObjectInfo(serverURL: server) }
        catch { throw Failure.serverUnavailable(error.localizedDescription) }
        guard !info.isEmpty else { throw AgentImageError("The server returned no node definitions.") }
        var graph = try await ComfyUIFormatConverter.prepareWorkflowFetchingObjectInfoIfNeeded(json: raw, serverURL: server).workflow
        if let issue = ComfyUIFormatConverter.validateAPIShape(graph) { throw AgentImageError(issue) }
        graph = ComfyUIFormatConverter.backfillMissingDefaults(workflow: graph, objectInfo: info).workflow
        guard let reachable = ComfyUIFormatConverter.reachableFromOutputs(workflow: graph), !reachable.isEmpty else { throw AgentImageError("Workflow has no recognized output nodes.") }
        graph = graph.filter { reachable.contains($0.key) }
        let resolved: WorkflowInputResolver.Resolution
        do { resolved = try WorkflowInputResolver.resolve(contract.inputs, definitions: saved.exposedInputs, graph: graph, objectInfo: info) }
        catch let error as WorkflowPromptSafety.Blocked { throw Failure.contentFiltered(error.report.filterReasons) }
        graph = resolved.graph
        guard resolved.imageReferences.count <= 4 else { throw AgentImageError("Use at most four workflow reference images.") }
        var promptKey: String?
        if let id = saved.promptNodeID, let node = graph[id] as? [String: Any],
           let type = node["class_type"] as? String, let definition = info[type] as? [String: Any] {
            promptKey = AgentWorkflowContract.promptKey(node: node, definition: definition)
        }
        if let prompt = contract.prompt {
            guard PromptSafetyPolicy.isPromptSafe(prompt).0 else { throw Failure.contentFiltered(PromptSafetyPolicy.filterReasons(prompt)) }
            guard let id = saved.promptNodeID, let key = promptKey, var node = graph[id] as? [String: Any],
                  var inputs = node["inputs"] as? [String: Any] else {
                throw AgentImageError("Saved prompt node has no unambiguous editable STRING input. Configure the prompt node in the app or omit prompt to run saved values.")
            }
            inputs[key] = prompt; node["inputs"] = inputs; graph[id] = node
        }
        let safety = WorkflowPromptSafety.inspect(graph, selectedPromptNodeID: saved.promptNodeID)
        guard safety.isSafe else {
            throw Failure.contentFiltered(safety.filterReasons)
        }
        try AgentWorkflowContract.validate(graph, objectInfo: info, deferredImageInputs: Set(saved.exposedInputs.filter { resolved.imageReferences[$0.name] != nil }.map { WorkflowInputBinding(nodeID: $0.nodeID, inputKey: $0.inputKey) }))
        if let output = saved.outputNodeID, !output.isEmpty, graph[output] == nil {
            throw AgentImageError("The saved output node is unavailable. Update the workflow in the app.")
        }
        guard saved.outputNodeIDs.count <= 4, Set(saved.outputNodeIDs).count == saved.outputNodeIDs.count,
              saved.outputNodeIDs.allSatisfy({ id in
                  guard let node = graph[id] as? [String: Any], let type = node["class_type"] as? String,
                        let info = info[type] as? [String: Any] else { return false }
                  return info["output_node"] as? Bool == true
              }) else { throw AgentImageError("Selected output nodes changed or exceed the four-node limit.") }
        let nodes = graph.values.compactMap { ($0 as? [String: Any])?["class_type"] as? String }.sorted()
        let namedPrompts = saved.exposedInputs.filter { $0.kind == .prompt }.compactMap { definition -> String? in
            if case .text(let value)? = resolved.effectiveValues[definition.name] { return value }; return nil
        }
        let savedPrompt: String? = saved.promptNodeID.flatMap { id in
            guard let key = promptKey, let node = graph[id] as? [String: Any], let inputs = node["inputs"] as? [String: Any] else { return nil }
            return inputs[key] as? String
        }
        return Result(saved: saved, server: server, url: url, graph: graph, promptKey: promptKey,
            prompt: contract.prompt ?? (namedPrompts.isEmpty ? savedPrompt : namedPrompts.joined(separator: "\n")),
            nodes: nodes, promptInspectionLimitations: safety.unresolved, imageReferences: resolved.imageReferences, effectiveValues: resolved.effectiveValues, usedLegacyOverride: contract.prompt != nil)
    }
}
