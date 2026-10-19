import Foundation
import CoreFoundation

public struct AgentVideoContract {
    public let model: CatalogModel
    public let prompt: String
    public let inputImages: [String]
    public let requestID: String?
    public let parameters: [String: Any]

    public init(_ args: [String: Any], submitting: Bool) throws {
        guard Set(args.keys).isSubset(of: ["model", "prompt", "params", "input_images", "request_label", "request_id"]),
              let id = args["model"] as? String, let model = Catalog.model(for: id), model.isVideo,
              ReleaseModelPolicy.allows(model.id, task: .video), model.pollingEndpoint != nil,
              let prompt = args["prompt"] as? String, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              prompt.utf8.count <= 32_000,
              args["params"] == nil || args["params"] is [String: Any],
              args["input_images"] == nil || args["input_images"] is [String] else {
            throw AgentImageError("Use a supported AIML video model, prompt (1–32,000 UTF-8 bytes), optional params/input_images, and request_id for submission. Other fields are not accepted.")
        }
        self.model = model; self.prompt = prompt
        _ = try AgentJobDiscovery.label(args)
        if let value = args["request_id"] {
            guard let id = value as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.count <= 128 else { throw AgentImageError("request_id must contain 1–128 characters.") }
            requestID = id
        } else {
            guard !submitting else { throw AgentImageError("Video request_id is required. Preserve the same ID and exact arguments for reconnect/replay.") }
            requestID = nil
        }
        inputImages = args["input_images"] as? [String] ?? []
        guard inputImages.count <= model.maxInputImages, !model.requiresInputImage || !inputImages.isEmpty else { throw AgentImageError("Incorrect number of input images for this video model.") }
        let raw = args["params"] as? [String: Any] ?? [:]
        let properties = Self.schema(model)["properties"] as? [String: [String: Any]] ?? [:]
        for (key, value) in raw {
            guard let rule = properties[key] else { throw AgentImageError("Unknown video parameter: \(key). Discover parameter_schema first.") }
            let number = value as? NSNumber
            let isBool = number.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            let valid: Bool
            switch rule["type"] as? String {
            case "string": valid = value is String
            case "boolean": valid = isBool
            case "integer": valid = !isBool && number != nil && number!.doubleValue.isFinite && number!.doubleValue.rounded() == number!.doubleValue
            case "number": valid = !isBool && number != nil && number!.doubleValue.isFinite
            default: valid = false
            }
            guard valid else { throw AgentImageError("Invalid video parameter type: \(key).") }
            if let allowed = rule["enum"] as? [Any], !(allowed as NSArray).contains(value) { throw AgentImageError("Unsupported video parameter value: \(key).") }
            if let number, let min = rule["minimum"] as? NSNumber, number.doubleValue < min.doubleValue { throw AgentImageError("\(key) is below its minimum.") }
            if let number, let max = rule["maximum"] as? NSNumber, number.doubleValue > max.doubleValue { throw AgentImageError("\(key) exceeds its maximum.") }
        }
        let descriptors = ParamCatalog.descriptors(for: model)
        var values = ParamDecoder.defaults(descriptors)
        ParamDecoder.decode(descriptors, from: raw, into: &values)
        if let issue = VideoRequestPolicy.parameterIssue(model: model, params: values, imageCount: inputImages.count) { throw AgentImageError(issue) }
        let encoded = ParamEncoder.encode(descriptors, params: values, context: ParamCatalog.context(for: model, hasInputImages: !inputImages.isEmpty))
        for (key, value) in raw {
            guard let actual = encoded[key], (actual as AnyObject).isEqual(value) else { throw AgentImageError("\(key) cannot be applied with these video inputs. Omit it or choose supported values; it will not be silently changed.") }
        }
        parameters = encoded
        _ = try body(references: inputImages.indices.map { "[image_slot_\($0)]" })
    }
    public static func schema(_ model: CatalogModel) -> [String: Any] { AgentImageContract.schema(provider: .aimlapi, model: model.id) }
    public func body(references: [String]) throws -> [String: Any] {
        guard references.count == inputImages.count else { throw AgentImageError("Video input count changed after validation.") }
        var body = parameters
        body["model"] = model.id; body["prompt"] = prompt
        if let first = references.first {
            body[model.imageInputParam] = model.acceptsMultiImages ? references : first as Any
            if references.count > 1, !model.acceptsMultiImages, let second = model.secondImageParam { body[second] = references[1] }
        }
        if let issue = VideoRequestPolicy.payloadIssue(model: model, body: body) { throw AgentImageError(issue) }
        return body
    }
}
