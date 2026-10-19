import Foundation
import CryptoKit

/// Inspects literal positive prompt inputs, not arbitrary graph strings. Linked
/// text and custom prompt producers cannot be evaluated without executing nodes.
public enum WorkflowPromptSafety {
    public struct Blocked: LocalizedError {
        public let report: Report
        public var errorDescription: String? {
            "Workflow prompt was blocked by the content filter. No generation was submitted. Review positive prompt inputs: " + report.blocked.map { "\($0.nodeID).\($0.inputKey)" }.joined(separator: ", ")
        }
    }
    public struct Finding: Equatable, Sendable {
        public let nodeID: String
        public let inputKey: String
        public let prompt: String
        public let offendingPhrases: [String]
    }
    public struct Report: Sendable {
        public var blocked: [Finding] = []
        public var unresolved: [String] = []
        private var literalPrompts: [String: [String: String]] = [:]
        public var positivePromptFingerprint: String {
            let bytes = (try? JSONSerialization.data(withJSONObject: literalPrompts, options: [.sortedKeys])) ?? Data()
            return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        fileprivate mutating func recordPrompt(node: String, key: String, text: String) {
            literalPrompts[node, default: [:]][key] = text
        }
        public var isSafe: Bool { blocked.isEmpty }
        public var filterReasons: [PromptSafetyPolicy.FilterReason] {
            PromptSafetyPolicy.reasons(for: blocked.flatMap(\.offendingPhrases))
        }
    }

    @discardableResult
    public static func requireSafe(_ graph: [String: Any], selectedPromptNodeID: String? = nil) throws -> Report {
        let report = inspect(graph, selectedPromptNodeID: selectedPromptNodeID)
        guard report.isSafe else { throw Blocked(report: report) }
        return report
    }

    public static func inspect(_ graph: [String: Any], selectedPromptNodeID: String? = nil) -> Report {
        func linkedID(_ value: Any) -> String? {
            guard let pair = value as? [Any], pair.count == 2,
                  pair[1] is NSNumber else { return nil }
            return pair[0] as? String
        }
        func ancestors(_ roots: Set<String>) -> Set<String> {
            var visited = Set<String>(), pending = Array(roots)
            while let id = pending.popLast() {
                guard visited.insert(id).inserted,
                      let node = graph[id] as? [String: Any],
                      let inputs = node["inputs"] as? [String: Any] else { continue }
                pending.append(contentsOf: inputs.values.compactMap(linkedID))
            }
            return visited
        }
        var positiveRoots = Set<String>(), negativeRoots = Set<String>()
        for value in graph.values {
            guard let node = value as? [String: Any], let inputs = node["inputs"] as? [String: Any] else { continue }
            for (key, value) in inputs {
                guard let id = linkedID(value) else { continue }
                if key == "positive" { positiveRoots.insert(id) }
                if key == "negative" { negativeRoots.insert(id) }
            }
        }
        let positive = ancestors(positiveRoots), negative = ancestors(negativeRoots)
        var report = Report()
        for id in graph.keys.sorted() {
            guard let node = graph[id] as? [String: Any],
                  let type = node["class_type"] as? String,
                  let inputs = node["inputs"] as? [String: Any] else { continue }
            // A shared encoder feeding both branches still supplies positive text.
            if negative.contains(id) && !positive.contains(id) { continue }
            let knownEncoder = ["CLIPTextEncode", "CLIPTextEncodeSDXL", "CLIPTextEncodeSDXLRefiner", "CLIPTextEncodeFlux", "CLIPTextEncodeSD3"].contains(type)
            let selected = id == selectedPromptNodeID
            var inspected = false
            for key in inputs.keys.sorted() {
                let lower = key.lowercased()
                guard !lower.contains("negative") else { continue }
                let semantic = ["prompt", "positive", "positive_prompt"].contains(lower)
                let encoderText = knownEncoder && ["text", "text_g", "text_l", "clip_l", "clip_g", "t5xxl"].contains(lower)
                let selectedText = selected && ["text", "value"].contains(lower)
                guard semantic || encoderText || selectedText else { continue }
                inspected = true
                if let text = inputs[key] as? String {
                    report.recordPrompt(node: id, key: key, text: text)
                    let result = PromptSafetyPolicy.isPromptSafe(text)
                    if !result.isSafe {
                        report.blocked.append(Finding(nodeID: id, inputKey: key, prompt: text, offendingPhrases: result.offendingPhrases))
                    }
                } else {
                    report.unresolved.append("\(id).\(key): linked or nonliteral prompt")
                }
            }
            if (positive.contains(id) || selected) && !knownEncoder && !inspected,
               (type.lowercased().contains("text") || type.lowercased().contains("prompt")) {
                report.unresolved.append("\(id): custom prompt producer \(type)")
            }
        }
        return report
    }
}
