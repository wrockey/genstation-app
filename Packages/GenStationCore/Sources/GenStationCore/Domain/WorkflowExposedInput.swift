import Foundation
import CoreFoundation

public struct WorkflowInputBinding: Hashable, Sendable {
    public let nodeID: String
    public let inputKey: String
    public init(nodeID: String, inputKey: String) { self.nodeID = nodeID; self.inputKey = inputKey }
}

public enum WorkflowInputValue: Codable, Equatable, Sendable {
    case text(String)
    case integer(Int64)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) { self = .text(text) }
        else { self = .integer(try value.decode(Int64.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self { case .text(let text): try value.encode(text); case .integer(let number): try value.encode(number) }
    }
    public var json: Any {
        switch self { case .text(let value): return value; case .integer(let value): return value }
    }
    public static func parse(_ value: Any) throws -> Self {
        if let text = value as? String { return .text(text) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
           number.doubleValue.isFinite, abs(number.doubleValue) <= 9_007_199_254_740_991,
           number.doubleValue.rounded() == number.doubleValue { return .integer(number.int64Value) }
        throw AgentImageError("Workflow inputs accept only text or exact integers, never objects, paths or node overrides.")
    }
}

/// Authored and saved by the user. Agents see names/types, never node bindings.
public struct WorkflowExposedInput: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case prompt, negativePrompt, image, seed, width, height
        public var isText: Bool { self == .prompt || self == .negativePrompt || self == .image }
    }
    public var id: String { name }
    public var name: String
    public var label: String
    public var kind: Kind
    public var nodeID: String
    public var nodeType: String
    public var inputKey: String
    public var required: Bool
    public var defaultValue: WorkflowInputValue?
    public var minimum: Int64?
    public var maximum: Int64?
    public var choices: [WorkflowInputValue]?

    public init(name: String, label: String, kind: Kind, nodeID: String, nodeType: String, inputKey: String,
                required: Bool = true, defaultValue: WorkflowInputValue? = nil,
                minimum: Int64? = nil, maximum: Int64? = nil, choices: [WorkflowInputValue]? = nil) {
        self.name = name; self.label = label; self.kind = kind; self.nodeID = nodeID
        self.nodeType = nodeType; self.inputKey = inputKey; self.required = required
        self.defaultValue = defaultValue; self.minimum = minimum; self.maximum = maximum; self.choices = choices
    }

    public func validateValue(_ value: WorkflowInputValue) throws {
        switch (kind, value) {
        case (.prompt, .text(let text)), (.negativePrompt, .text(let text)):
            guard text.utf8.count <= 32_000, kind == .negativePrompt || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentImageError("Input \(name) must be prompt text of at most 32,000 UTF-8 bytes.")
            }
        case (.image, .text(let reference)):
            guard reference.hasPrefix("asset:"), UUID(uuidString: String(reference.dropFirst(6))) != nil else {
                throw AgentImageError("Input \(name) requires a scoped asset:<UUID> original, never a path or URL.")
            }
        case (.seed, .integer(let number)), (.width, .integer(let number)), (.height, .integer(let number)):
            let lower: Int64 = kind == .seed ? 0 : 64
            let upper: Int64 = kind == .seed ? 9_007_199_254_740_991 : 8192
            guard number >= max(lower, minimum ?? lower), number <= min(upper, maximum ?? upper) else {
                throw AgentImageError("Input \(name) is outside its saved numeric limits.")
            }
        default: throw AgentImageError("Input \(name) has the wrong type.")
        }
        if let choices, !choices.contains(value) { throw AgentImageError("Input \(name) is not one of its saved choices.") }
    }

    public var publicSchema: [String: Any] {
        var schema: [String: Any] = ["type": kind.isText ? "string" : "integer", "title": label, "kind": kind.rawValue]
        if let defaultValue { schema["default"] = defaultValue.json }
        if kind == .image { schema["pattern"] = "^asset:[0-9A-Fa-f-]{36}$" }
        else if kind.isText { schema["maxLength"] = 32_000; if kind == .prompt { schema["minLength"] = 1 } }
        else {
            schema["minimum"] = max(kind == .seed ? 0 : 64, minimum ?? 0)
            schema["maximum"] = min(kind == .seed ? 9_007_199_254_740_991 : 8192, maximum ?? Int64.max)
        }
        if let choices { schema["enum"] = choices.map(\.json) }
        return schema
    }
}

public enum WorkflowInputResolver {
    public struct Resolution {
        public var graph: [String: Any]
        public var imageReferences: [String: String]
        public var effectiveValues: [String: WorkflowInputValue]
    }
    public static func validateDefinitions(_ definitions: [WorkflowExposedInput], graph: [String: Any], objectInfo: [String: Any]) throws {
        guard definitions.count <= 12, Set(definitions.map(\.name)).count == definitions.count,
              Set(definitions.map { WorkflowInputBinding(nodeID: $0.nodeID, inputKey: $0.inputKey) }).count == definitions.count else {
            throw AgentImageError("Expose at most 12 uniquely named inputs with distinct bindings.")
        }
        for definition in definitions {
            guard definition.name.range(of: "^[a-z][a-z0-9_]{0,47}$", options: .regularExpression) != nil,
                  !definition.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, definition.label.count <= 120,
                  (definition.minimum ?? Int64.min) <= (definition.maximum ?? Int64.max),
                  definition.choices.map({ !$0.isEmpty && $0.count <= 100 }) ?? true,
                  let node = graph[definition.nodeID] as? [String: Any], node["class_type"] as? String == definition.nodeType,
                  let inputs = node["inputs"] as? [String: Any], let literal = inputs[definition.inputKey], !(literal is [Any]),
                  let nodeInfo = objectInfo[definition.nodeType] as? [String: Any],
                  let schema = nodeInfo["input"] as? [String: Any] else {
                throw AgentImageError("Input \(definition.name) has an invalid or changed binding. Linked inputs cannot be exposed.")
            }
            let fields = (schema["required"] as? [String: Any] ?? [:]).merging(schema["optional"] as? [String: Any] ?? [:]) { first, _ in first }
            guard let spec = fields[definition.inputKey] as? [Any], let type = spec.first else {
                throw AgentImageError("Input \(definition.name) is no longer declared by the server.")
            }
            let options = spec.count > 1 ? spec[1] as? [String: Any] ?? [:] : [:]
            let key = definition.inputKey.lowercased()
            switch definition.kind {
            case .prompt, .negativePrompt:
                guard type as? String == "STRING", literal is String else { throw AgentImageError("Prompt bindings require literal STRING inputs.") }
                let promptKeys: Set<String> = ["text", "prompt", "text_g", "text_l", "clip_l", "clip_g", "t5xxl", "caption", "string"]
                let roleKeys: Set<String> = definition.kind == .prompt ? ["positive", "positive_prompt"] : ["negative", "negative_prompt"]
                let textValue = key == "value" && ["text", "string", "prompt"].contains { definition.nodeType.lowercased().contains($0) }
                guard promptKeys.contains(key) || roleKeys.contains(key) || textValue else {
                    throw AgentImageError("Prompt roles cannot expose filenames, paths, URLs, credentials or unrelated STRING fields.")
                }
            case .image:
                guard literal is String, ((definition.nodeType == "LoadImage" && definition.inputKey == "image") || options["image_upload"] as? Bool == true),
                      options["multiselect"] as? Bool != true, type is [Any] || type as? String == "COMBO" else { throw AgentImageError("Image bindings require a server-declared image-upload choice.") }
            case .seed, .width, .height:
                guard type as? String == "INT", (try? WorkflowInputValue.parse(literal)) != nil else { throw AgentImageError("Seed/dimension bindings require literal INT inputs.") }
                let allowed: Set<String>
                switch definition.kind {
                case .seed: allowed = ["seed", "noise_seed"]
                case .width: allowed = ["width", "target_width", "image_width", "latent_width"]
                default: allowed = ["height", "target_height", "image_height", "latent_height"]
                }
                guard allowed.contains(key) else { throw AgentImageError("Seed and dimension roles cannot expose unrelated numeric controls.") }
            }
            if let value = definition.defaultValue { try definition.validateValue(value) }
            for value in definition.choices ?? [] { try definition.validateValue(value) }
        }
    }

    public static func resolve(_ values: [String: WorkflowInputValue], definitions: [WorkflowExposedInput],
                               graph: [String: Any], objectInfo: [String: Any]) throws -> Resolution {
        try validateDefinitions(definitions, graph: graph, objectInfo: objectInfo)
        guard Set(values.keys).isSubset(of: Set(definitions.map(\.name))) else { throw AgentImageError("Request contains an input that the user has not exposed.") }
        var result = Resolution(graph: graph, imageReferences: [:], effectiveValues: [:])
        for definition in definitions {
            guard let value = values[definition.name] ?? definition.defaultValue else {
                if definition.required { throw AgentImageError("Missing required workflow input: \(definition.name).") }
                continue
            }
            try definition.validateValue(value)
            result.effectiveValues[definition.name] = value
            if definition.kind == .image, case .text(let reference) = value {
                result.imageReferences[definition.name] = reference
                continue // Preflight never replaces this with a path or uploads.
            }
            var node = result.graph[definition.nodeID] as! [String: Any]
            var inputs = node["inputs"] as! [String: Any]
            inputs[definition.inputKey] = value.json
            node["inputs"] = inputs; result.graph[definition.nodeID] = node
        }
        try checkPromptValues(in: result.graph, definitions: definitions)
        return result
    }
    /// Also used by the legacy GUI after style/additional-text injection, without
    /// replacing the user's effective values with saved defaults.
    public static func checkPromptValues(in graph: [String: Any], definitions: [WorkflowExposedInput]) throws {
        for definition in definitions where definition.kind == .prompt {
            if let node = graph[definition.nodeID] as? [String: Any],
               let inputs = node["inputs"] as? [String: Any], let text = inputs[definition.inputKey] as? String {
                let check = PromptSafetyPolicy.isPromptSafe(text)
                if !check.isSafe {
                    var report = WorkflowPromptSafety.Report()
                    report.blocked = [.init(nodeID: definition.nodeID, inputKey: definition.inputKey, prompt: text, offendingPhrases: check.offendingPhrases)]
                    throw WorkflowPromptSafety.Blocked(report: report)
                }
            }
        }
    }

}
