import Foundation
import CoreFoundation

/// Validation for the deliberately bounded text/first-frame/first-last-frame release workflows.
public enum VideoRequestPolicy {
    public static func parameterIssue(model: CatalogModel, params: ModelParameters, imageCount: Int) -> String? {
        let descriptors = ParamCatalog.descriptors(for: model)
        // Reject invalid stored picker values before the encoder could omit them and change cost.
        for row in descriptors {
            guard let field = row.field, let value = params[field],
                  case .picker(let options, _) = row.control else { continue }
            if let condition = row.visibleWhen,
               !condition.holds(params: params, context: ParamCatalog.context(for: model, hasInputImages: imageCount > 0)) { continue }
            let matches = options.contains(value) || options.contains { option in
                if case .string(let lhs) = option, case .string(let rhs) = value { return lhs.lowercased() == rhs.lowercased() }
                return false
            }
            if !matches { return "Choose a supported \(row.label.lowercased()) for \(model.displayName) in Model Settings." }
        }
        if model.id.contains("veo-3.1"), let resolution = params.resolution?.lowercased(),
           ["1080p", "4k"].contains(resolution), params.duration != 8 {
            return "Veo 3.1 requires 8 seconds for 1080p or 4K. Choose 8 seconds or use 720p."
        }
        if model.id.contains("kling"), imageCount > 1, params.generateAudio != false {
            return "Kling cannot generate audio with a last frame. Turn off Generate Audio or remove the last frame."
        }
        return nil
    }

    public static func payloadIssue(model: CatalogModel, body: [String: Any]) -> String? {
        var allowed = Set(ParamCatalog.descriptors(for: model).map(\.wireKey).filter { !$0.isEmpty })
        allowed.formUnion(["model", "prompt"])
        if model.isI2I { allowed.insert(model.imageInputParam) }
        if let second = model.secondImageParam { allowed.insert(second) }
        let unsupported = Set(body.keys).subtracting(allowed)
        if !unsupported.isEmpty { return "This video workflow does not support: \(unsupported.sorted().joined(separator: ", ")). Reset the custom request and use Model Settings." }
        guard let prompt = body["prompt"] as? String, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter a video prompt." }
        if model.id == "alibaba/wan-3-0-video" && prompt.count > 20_000 { return "Wan 3.0 prompts must be at most 20,000 characters." }
        if model.id == "minimax/h3-max" && prompt.count > 50_000 { return "H3 Max prompts must be at most 50,000 characters." }
        guard let rawModel = body["model"] as? String, Catalog.canonicalID(for: rawModel) == model.id else {
            return "The video request must name the selected model. Reset the custom request."
        }
        for row in ParamCatalog.descriptors(for: model) {
            guard !row.wireKey.isEmpty, let raw = body[row.wireKey], let field = row.field else { continue }
            let number = raw as? NSNumber
            let isBool = number.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            let validType: Bool
            switch field.kind {
            case .string: validType = raw is String
            case .bool: validType = isBool
            case .int: validType = !isBool && number != nil && number!.doubleValue.rounded() == number!.doubleValue
            case .double: validType = !isBool && number != nil
            }
            if !validType { return "Invalid value type for \(row.label). Reset the custom request or use Model Settings." }
            switch row.control {
            case .slider(let range, _):
                if let n = number, !range.contains(n.doubleValue) { return "\(row.label) must be between \(range.lowerBound) and \(range.upperBound)." }
            case .seed(let range):
                if let n = number, n.doubleValue < Double(range.lowerBound) || n.doubleValue > Double(range.upperBound) { return "Choose a seed within the supported range." }
            default: break
            }
        }
        for key in [model.imageInputParam, model.secondImageParam].compactMap({ $0 }) where !key.isEmpty {
            if let raw = body[key], !(raw is String) { return "Frame inputs must be image URLs, not arrays or objects." }
        }
        let first = body[model.imageInputParam] as? String
        let last = model.secondImageParam.flatMap { body[$0] as? String }
        if model.requiresInputImage && (first?.isEmpty != false) { return "Add a first-frame image for this model." }
        if last != nil && (first?.isEmpty != false) { return "A last frame requires a first frame." }
        for input in [first, last].compactMap({ $0 }) {
            if input.hasPrefix("[image_slot_") { continue } // settings preview; final request is checked again
            if input.hasPrefix("data:image/") && model.acceptsBase64 { continue }
            guard let url = URL(string: input), url.scheme == "https", url.host != nil else { return "Frame inputs must be direct HTTPS image URLs\(model.acceptsBase64 ? " or image data URIs" : "")." }
        }
        if first != nil && ["bytedance/seedance-2-0", "bytedance/seedance-2-5"].contains(model.id), body["aspect_ratio"] != nil {
            return "Seedance frame inputs determine the aspect ratio. Remove aspect_ratio from the custom request."
        }
        var params = ParamDecoder.defaults(ParamCatalog.descriptors(for: model))
        ParamDecoder.decode(ParamCatalog.descriptors(for: model), from: body, into: &params)
        return parameterIssue(model: model, params: params, imageCount: (first == nil ? 0 : 1) + (last == nil ? 0 : 1))
    }
}
