// Stage 3 Task 9 — record what ModelRegistry ACTUALLY RETURNS, by running it.
//
// Compiled together with GenStation/Catalog/ModelRegistry.swift into one throwaway binary, so
// `ModelRegistry.registry` (internal) is visible. Writes the fixture the package test asserts
// against. This is a recording of the OLD path, exactly like GoldenPayloads: never regenerate it
// from Catalog.
import Foundation

/// Unregistered ids, chosen to cover every branch of the synthesis path at
/// ModelRegistry.swift:2091-2120 — which no test exercises today. `RegistryEndpointTests:71-72`
/// explicitly skips it (`!line.contains("defaultGenerationEndpoint")`), so these nine rows are
/// the first coverage that branch has ever had.
let unregisteredProbes = [
    "alibaba/qwen-image-3",          // image, not i2i — the id that failed live in Stage 2
    "minimax/hailuo-99-i2v",         // i2v: isVideo + isI2I, requiresInputImage false
    "kuaishou/kling-99-t2v",         // t2v: isVideo, not i2i
    "runwayml/gen9-video",           // the "video" token rather than i2v/t2v
    "openai/gpt-image-9-edit",       // "edit": isI2I + requiresInputImage, image
    "flux/dev-9/image-to-image",     // "image-to-image", and a three-component id
    "bytedance/seedream-9-i2i",      // "i2i"
    "sora-9-t2v",                    // no "/" — provider becomes the whole id
    "MiniMax/MiniMax-Text-01",       // mixed case, no capability token at all
]

var out: [String] = []
out.append("// RegistryCapabilities — what ModelRegistry.enhancedModelFor(id:)?.base returned,")
out.append("// recorded by RUNNING it (tools/stage3-catalog-gen/recorder/main.swift).")
out.append("//")
out.append("// This is the Phase-A equivalence gate's expected side. It is a recording of the OLD")
out.append("// path, in the same chain Stage 2 used for GoldenPayloads: record, then assert.")
out.append("// **Do not regenerate it from Catalog** — that makes the assertion circular and")
out.append("// destroys the only record of what the registry did before it was deleted.")
out.append("//")
out.append("// The two sides are independently derived: Catalog/Models/ comes from PARSING the")
out.append("// reg() blocks as text, this file comes from EXECUTING them. A parse bug in the")
out.append("// generator therefore shows up as a mismatch rather than as agreement with itself.")
out.append("//")
out.append("// GENERATED. Do not hand-edit.")
out.append("")
out.append("enum RegistryCapabilities {")
out.append("")
out.append("    /// One `enhancedModelFor(id:)` result. Field names and types are the registry's,")
out.append("    /// not the catalog's — `isVideo` rather than `task`, `id` as the registry spelled it.")
out.append("    struct Row: Hashable {")
out.append("        let queriedID: String")
out.append("        let isRegistered: Bool")
out.append("        let id: String")
out.append("        let isVideo: Bool")
out.append("        let isI2I: Bool")
out.append("        let requiresInputImage: Bool")
out.append("        let supportsMask: Bool")
out.append("        let maxInputImages: Int")
out.append("        let imageInputParam: String")
out.append("        let secondImageParam: String?")
out.append("        let acceptsMultiImages: Bool")
out.append("        let acceptsBase64: Bool")
out.append("        let acceptsPublicURL: Bool")
out.append("        let acceptsBinary: Bool")
out.append("        let generationEndpoint: String")
out.append("        let pollingEndpoint: String?")
out.append("    }")
out.append("")
out.append("    static let rows: [Row] = [")

func quoted(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "nil" }

let queried = ModelRegistry.registry.keys.sorted() + unregisteredProbes
for id in queried {
    guard let m = ModelRegistry.enhancedModelFor(id: id)?.base else {
        FileHandle.standardError.write(Data("ABORT: enhancedModelFor returned nil for \(id)\n".utf8))
        exit(1)
    }
    out.append("        Row(queriedID: \(quoted(id)), isRegistered: \(ModelRegistry.isRegistered(id)),")
    out.append("            id: \(quoted(m.id)), isVideo: \(m.isVideo), isI2I: \(m.isI2I),")
    out.append("            requiresInputImage: \(m.requiresInputImage), supportsMask: \(m.supportsMask),")
    out.append("            maxInputImages: \(m.maxInputImages), imageInputParam: \(quoted(m.imageInputParam)),")
    out.append("            secondImageParam: \(quoted(m.secondImageParam)), acceptsMultiImages: \(m.acceptsMultiImages),")
    out.append("            acceptsBase64: \(m.acceptsBase64), acceptsPublicURL: \(m.acceptsPublicURL),")
    out.append("            acceptsBinary: \(m.acceptsBinary), generationEndpoint: \(quoted(m.generationEndpoint)),")
    out.append("            pollingEndpoint: \(quoted(m.pollingEndpoint))),")
}
out.append("    ]")
out.append("}")

let path = CommandLine.arguments[1]
try! (out.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
print("recorded \(queried.count) rows (\(ModelRegistry.registry.count) registered + \(unregisteredProbes.count) synthesis probes) to \(path)")
