import Foundation
import CoreFoundation

/// Bounded agent edits: select an existing workflow and replace a single literal prompt.
/// Never accept graphs, server URLs, arbitrary node edits or input file paths from agents.
public struct AgentWorkflowContract {
    public let workflowID: UUID
    public let prompt: String?
    public let requestID: String?
    public let inputs: [String: WorkflowInputValue]
    public let workflowRevision: Int?
    public let workflowDigest: String?

    public init(_ arguments: [String: Any], submitting: Bool) throws {
        guard Set(arguments.keys).isSubset(of: ["workflow_id", "prompt", "request_label", "request_id", "inputs", "workflow_revision", "workflow_digest"]),
              let id = arguments["workflow_id"] as? String, let uuid = UUID(uuidString: id) else {
            throw AgentImageError("Use a saved workflow_id from list_workflows, optional prompt, and request_id for execution. Inline graphs, paths, node overrides and server URLs are not accepted.")
        }
        workflowID = uuid
        if let raw = arguments["inputs"] {
            guard let values = raw as? [String: Any], values.count <= 12 else { throw AgentImageError("inputs must be a map of at most 12 exposed names.") }
            inputs = try values.mapValues(WorkflowInputValue.parse)
        } else { inputs = [:] }
        if let raw = arguments["workflow_revision"] {
            guard case .integer(let value) = try WorkflowInputValue.parse(raw), value > 0, value <= Int.max else {
                throw AgentImageError("workflow_revision must be a positive integer from discovery.")
            }
            workflowRevision = Int(value)
        } else { workflowRevision = nil }
        if let raw = arguments["workflow_digest"] {
            guard let value = raw as? String, value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
                throw AgentImageError("workflow_digest must be the SHA-256 value from discovery.")
            }
            workflowDigest = value
        } else { workflowDigest = nil }
        if arguments["inputs"] != nil && (workflowRevision == nil || workflowDigest == nil) {
            throw AgentImageError("Named inputs require workflow_revision and workflow_digest from list_workflows.")
        }
        if let value = arguments["prompt"] {
            guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf8.count <= 32_000 else { throw AgentImageError("prompt must contain 1–32,000 UTF-8 bytes.") }
            prompt = text
        } else { prompt = nil }
        _ = try AgentJobDiscovery.label(arguments)
        if let value = arguments["request_id"] {
            guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.count <= 128 else { throw AgentImageError("request_id must contain 1–128 characters.") }
            requestID = text
        } else {
            guard !submitting else { throw AgentImageError("request_id is required; preserve it and the exact arguments for reconnects.") }
            requestID = nil
        }
    }

    /// Only an unambiguous, declared STRING prompt input on the user-selected node is editable.
    public static func promptKey(node: [String: Any], definition: [String: Any]) -> String? {
        guard let inputs = node["inputs"] as? [String: Any],
              let schema = definition["input"] as? [String: Any] else { return nil }
        let fields = (schema["required"] as? [String: Any] ?? [:]).merging(schema["optional"] as? [String: Any] ?? [:]) { a, _ in a }
        let candidates = inputs.keys.filter { key in
            let name = key.lowercased()
            guard !name.contains("negative"), inputs[key] is String,
                  let spec = fields[key] as? [Any], spec.first as? String == "STRING" else { return false }
            return name == "text" || name == "prompt" || name == "positive" || name == "positive_prompt" || name == "value"
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// Validate reachable inputs, literal types/ranges/enums and linked output types.
    public static func validate(_ workflow: [String: Any], objectInfo: [String: Any], deferredImageInputs: Set<WorkflowInputBinding> = []) throws {
        guard !workflow.isEmpty, !objectInfo.isEmpty else { throw AgentImageError("Workflow and live node definitions are required.") }
        var visiting = Set<String>(), visited = Set<String>()
        func visit(_ id: String) throws {
            guard !visiting.contains(id) else { throw AgentImageError("Workflow contains a cycle at node \(id).") }
            if visited.contains(id) { return }
            visiting.insert(id)
            if let node = workflow[id] as? [String: Any], let inputs = node["inputs"] as? [String: Any] {
                for value in inputs.values {
                    if let link = value as? [Any], link.count == 2, let source = link[0] as? String {
                        try visit(source)
                    }
                }
            }
            visiting.remove(id); visited.insert(id)
        }
        for id in workflow.keys { try visit(id) }
        for (id, rawNode) in workflow {
            guard let node = rawNode as? [String: Any], let kind = node["class_type"] as? String,
                  let definition = objectInfo[kind] as? [String: Any],
                  let schema = definition["input"] as? [String: Any],
                  let inputs = node["inputs"] as? [String: Any] else {
                throw AgentImageError("Node \(id) is malformed or unavailable on the configured server.")
            }
            let required = schema["required"] as? [String: Any] ?? [:]
            let fields = required.merging(schema["optional"] as? [String: Any] ?? [:]) { a, _ in a }
            for key in required.keys where inputs[key] == nil {
                throw AgentImageError("Node \(id) is missing required input \(key).")
            }
            for (key, value) in inputs {
                guard let spec = fields[key] as? [Any], let type = spec.first else {
                    throw AgentImageError("Node \(id) input \(key) is not declared by the server.")
                }
                if deferredImageInputs.contains(WorkflowInputBinding(nodeID: id, inputKey: key)) {
                    let options = spec.count > 1 ? spec[1] as? [String: Any] ?? [:] : [:]
                    guard value is String, (type is [Any] || type as? String == "COMBO"),
                          (kind == "LoadImage" && key == "image") || options["image_upload"] as? Bool == true else {
                        throw AgentImageError("Only validated image-upload fields may await an approved upload.")
                    }
                    continue
                }
                if let link = value as? [Any], link.count == 2, let sourceID = link[0] as? String,
                   let index = link[1] as? NSNumber, CFGetTypeID(index) != CFBooleanGetTypeID(),
                   index.doubleValue == Double(index.intValue), index.intValue >= 0 {
                    guard let source = workflow[sourceID] as? [String: Any], let sourceKind = source["class_type"] as? String,
                          let sourceDefinition = objectInfo[sourceKind] as? [String: Any],
                          let outputs = sourceDefinition["output"] as? [String], index.intValue < outputs.count,
                          let expected = type as? String,
                          expected == "*" || outputs[index.intValue] == "*" || expected.split(separator: ",").contains(Substring(outputs[index.intValue])) else {
                        throw AgentImageError("Node \(id) input \(key) has an invalid or incompatible link.")
                    }
                    continue
                }
                if let choices = type as? [Any] {
                    guard (choices as NSArray).contains(value) else {
                        throw AgentImageError("Node \(id) input \(key) is not an available server option.")
                    }
                    continue
                }
                let options = spec.count > 1 ? spec[1] as? [String: Any] ?? [:] : [:]
                switch type as? String {
                case "COMBO":
                    guard let choices = options["options"] as? [Any],
                          options["multiselect"] as? Bool != true,
                          (choices as NSArray).contains(value) else {
                        throw AgentImageError("Node \(id) input \(key) is not an available single server option.")
                    }
                case "STRING":
                    guard value is String else { throw AgentImageError("Node \(id) input \(key) must be text.") }
                case "BOOLEAN":
                    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                        throw AgentImageError("Node \(id) input \(key) must be boolean.")
                    }
                case "INT", "FLOAT":
                    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                          (type as? String != "INT" || number.doubleValue.rounded() == number.doubleValue),
                          (options["min"] as? NSNumber).map({ number.doubleValue >= $0.doubleValue }) ?? true,
                          (options["max"] as? NSNumber).map({ number.doubleValue <= $0.doubleValue }) ?? true else {
                        throw AgentImageError("Node \(id) input \(key) is outside its numeric schema.")
                    }
                default: throw AgentImageError("Node \(id) input \(key) requires a supported connection; arbitrary literal objects are not accepted.")
                }
            }
        }
    }
}
