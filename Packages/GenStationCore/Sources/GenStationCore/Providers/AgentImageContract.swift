import Foundation
import CoreFoundation

/// A deliberately small agent surface, using the same provider builders as interactive creation.
public struct AgentImageContract {
    public let provider: Provider
    public let model: String
    public let prompt: String
    public let parameters: [String: Any]
    public let inputCount: Int
    public static let geminiModels = ["gemini-3.1-flash-image-preview", "gemini-3-pro-image-preview", "gemini-2.5-flash-image"]
    public static let aspects = ["1:1", "3:2", "2:3", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]

    public static func models() -> [[String: Any]] {
        var entries: [[String: Any]] = []
        for provider in [Provider.aimlapi, .gemini, .grok] {
            let ids: [String]
            switch provider {
            case .aimlapi: ids = Catalog.all.filter { !$0.isVideo && ReleaseModelPolicy.allows($0.id) && (!$0.requiresInputImage || $0.acceptsBase64) }.map(\.id)
            case .gemini: ids = geminiModels
            default: ids = ["grok-imagine-image-2.0"]
            }
            for id in ids.sorted() {
                var entry: [String: Any] = ["id": id, "provider": provider.rawValue, "is_video": false,
                    "max_input_images": maxInputs(provider: provider, model: id),
                    "requires_input_image": provider == .aimlapi && (Catalog.model(for: id)?.requiresInputImage ?? false),
                    "parameter_schema": schema(provider: provider, model: id),
                    "price_status": "unknown", "approval": "individual_request"]
                if let row = Catalog.model(for: id), provider == .aimlapi {
                    entry["display_name"] = row.displayName
                    if Self.supportsBinaryEdits(row) {
                        // Model positioning: https://developers.openai.com/api/docs/guides/image-prompting
                        switch row.id {
                        case "openai/gpt-image-2.5-flare": entry["description"] = "GPT Image 2.5 variant for speed-priority image generation and editing."
                        case "openai/gpt-image-2.5-sunburst": entry["description"] = "GPT Image 2.5 variant for demanding image quality in generation and editing."
                        default: entry["description"] = "\(row.displayName) supports image generation and editing with optional reference images."
                        }
                    }
                }
                entries.append(entry)
            }
        }
        return entries
    }

    private static func supportsBinaryEdits(_ row: CatalogModel) -> Bool {
        row.isI2I && row.supportsMask && row.acceptsBinary && row.imageInputParam == "image"
    }

    private static func maxInputs(provider: Provider, model: String) -> Int {
        switch provider {
        case .aimlapi: return Catalog.model(for: model).map { ($0.acceptsBase64 || supportsBinaryEdits($0)) ? $0.maxInputImages : 0 } ?? 0
        case .gemini: return 3
        case .grok: return 1
        case .comfyUI: return 0
        }
    }

    public static func schema(provider: Provider, model: String) -> [String: Any] {
        var properties: [String: Any] = [:]
        if provider == .aimlapi, let row = Catalog.model(for: model) {
            for descriptor in ParamCatalog.descriptors(for: row) where !descriptor.wireKey.isEmpty {
                var property: [String: Any] = [:]
                if let field = descriptor.field {
                    switch field.kind {
                    case .string: property["type"] = "string"
                    case .int: property["type"] = "integer"
                    case .double: property["type"] = "number"
                    case .bool: property["type"] = "boolean"
                    }
                }
                if let allowed = descriptor.allowedValues { property["enum"] = allowed.map(\.jsonValue) }
                switch descriptor.control {
                case .picker(let options, _):
                    if descriptor.allowedValues == nil { property["enum"] = options.map(\.jsonValue) }
                case .slider(let range, _): property["minimum"] = range.lowerBound; property["maximum"] = range.upperBound
                case .seed(let range): property["minimum"] = range.lowerBound; property["maximum"] = range.upperBound
                case .imageSize(let spec): property = ["type": "string", "enum": spec.presets]
                default: break
                }
                if !property.isEmpty { properties[descriptor.wireKey] = property }
            }
            // One output per approval keeps this initial workflow bounded.
            for key in ["n", "num_images", "num_outputs"] where properties[key] != nil {
                properties[key] = ["type": "integer", "enum": [1]]
            }
        } else {
            properties["aspect_ratio"] = ["type": "string", "enum": aspects]
            if provider == .grok { properties["resolution"] = ["type": "string", "enum": ["1k", "2k"]] }
            if provider == .gemini && model != "gemini-2.5-flash-image" {
                properties["resolution"] = ["type": "string", "enum": ["1K", "2K", "4K"]]
            }
        }
        return ["type": "object", "properties": properties, "additionalProperties": false]
    }

    public init(provider: String, model: String, prompt: String, params: [String: Any], inputCount: Int) throws {
        guard let selected = Provider(rawValue: provider), Self.models().contains(where: { ($0["id"] as? String) == model && ($0["provider"] as? String) == provider }) else {
            throw AgentImageError("Unsupported provider/model. Call list_models for supported image models.")
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.utf8.count <= 32_000 else { throw AgentImageError("prompt must be nonempty and at most 32 KB.") }
        guard inputCount >= 0, inputCount <= Self.maxInputs(provider: selected, model: model) else { throw AgentImageError("Too many input images for this model.") }
        if selected == .aimlapi, Catalog.model(for: model)?.requiresInputImage == true, inputCount == 0 { throw AgentImageError("This model requires an input image.") }
        let properties = Self.schema(provider: selected, model: model)["properties"] as! [String: [String: Any]]
        for (key, value) in params {
            guard let rule = properties[key] else { throw AgentImageError("Unknown parameter: \(key). Call list_models for parameter_schema.") }
            let number = value as? NSNumber
            let isBool = number.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            let validType: Bool
            switch rule["type"] as? String {
            case "string": validType = value is String
            case "boolean": validType = isBool
            case "integer": validType = !isBool && number != nil && number!.doubleValue.isFinite && number!.doubleValue.rounded() == number!.doubleValue
            case "number": validType = !isBool && number != nil && number!.doubleValue.isFinite
            default: validType = false
            }
            guard validType else { throw AgentImageError("Invalid type for \(key).") }
            if let allowed = rule["enum"] as? [Any], !allowed.contains(where: { ($0 as AnyObject).isEqual(value) }) { throw AgentImageError("Unsupported value for \(key).") }
            if let number, let minimum = rule["minimum"] as? NSNumber, number.doubleValue < minimum.doubleValue { throw AgentImageError("\(key) is below its minimum.") }
            if let number, let maximum = rule["maximum"] as? NSNumber, number.doubleValue > maximum.doubleValue { throw AgentImageError("\(key) exceeds its maximum.") }
        }
        self.provider = selected; self.model = model; self.prompt = prompt; self.inputCount = inputCount
        if selected == .aimlapi, let row = Catalog.model(for: model) {
            let descriptors = ParamCatalog.descriptors(for: row)
            var values = ParamDecoder.defaults(descriptors)
            ParamDecoder.decode(descriptors, from: params, into: &values)
            let context = ParamCatalog.context(for: row, hasInputImages: inputCount > 0)
            var encoded = ParamEncoder.encode(descriptors, params: values, context: context)
            for (key, value) in params {
                // The UI omits certain defaults, but an explicit, schema-valid agent
                // choice must remain usable and reach the provider without substitution.
                if encoded[key] == nil,
                   let descriptor = descriptors.first(where: { $0.wireKey == key }),
                   descriptor.isVisible(params: values, context: context),
                   let stored = descriptor.field.flatMap({ values[$0] }),
                   let emissionGuard = descriptor.emitWhen, !emissionGuard.allows(stored),
                   (stored.jsonValue as AnyObject).isEqual(value) {
                    encoded[key] = value
                }
                guard let actual = encoded[key], (actual as AnyObject).isEqual(value) else {
                    throw AgentImageError("\(key) is not supported with these inputs; omit it to use the model default.")
                }
            }
            parameters = encoded
        } else { parameters = params }
    }

    public func request(apiKey: String, imageDataURIs: [String]) throws -> URLRequest {
        guard imageDataURIs.count == inputCount else { throw AgentImageError("Input image count changed after validation.") }
        var request: URLRequest
        let data: Data
        switch provider {
        case .gemini:
            // Header auth keeps credentials out of request URLs, history and error descriptions.
            request = URLRequest(url: GeminiClient.baseURL.appendingPathComponent("models/\(model):generateContent"))
            request.setValue(apiKey, forHTTPHeaderField: GeminiClient.apiKeyHeaderName)
            var parts = [GeminiClient.Part(text: prompt)]
            for uri in imageDataURIs {
                guard let comma = uri.firstIndex(of: ","), uri.hasPrefix("data:image/"), uri[..<comma].hasSuffix(";base64") else { throw AgentImageError("Invalid image data URI.") }
                let mime = String(uri.dropFirst(5).prefix(while: { $0 != ";" }))
                parts.append(.init(inlineData: .init(mimeType: mime, data: String(uri[uri.index(after: comma)...]))))
            }
            data = try JSONEncoder().encode(GeminiClient.GenerateContentRequest(contents: [.init(parts: parts)], generationConfig: .init(responseModalities: ["TEXT", "IMAGE"], imageConfig: .init(aspectRatio: parameters["aspect_ratio"] as? String ?? "1:1", imageSize: parameters["resolution"] as? String))))
        case .grok:
            request = URLRequest(url: inputCount == 0 ? GrokClient.imageGenerationsURL : GrokClient.imageEditsURL)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            data = try JSONSerialization.data(withJSONObject: GrokClient.imageRequestBody(model: model, prompt: prompt, aspectRatio: parameters["aspect_ratio"] as? String ?? "1:1", resolution: parameters["resolution"] as? String ?? "2k", imageDataURI: imageDataURIs.first))
        case .aimlapi:
            guard let row = Catalog.model(for: model), let url = URL(string: row.generationEndpoint) else { throw AgentImageError("Missing model endpoint.") }
            if inputCount > 0, Self.supportsBinaryEdits(row) {
                request = URLRequest(url: AIMLEndpoints.imageEndpoint(supportsMask: row.supportsMask, hasInputImages: true))
                request.httpMethod = "POST"; request.timeoutInterval = 180
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                let boundary = "GenStation-" + UUID().uuidString
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                var body = Data()
                func append(_ text: String) { body.append(Data(text.utf8)) }
                var fields = parameters
                fields["model"] = model; fields["prompt"] = prompt
                for key in fields.keys.sorted() {
                    append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(fields[key]!)\r\n")
                }
                for (index, uri) in imageDataURIs.enumerated() {
                    guard let comma = uri.firstIndex(of: ","), uri[..<comma].hasSuffix(";base64"),
                          let bytes = Data(base64Encoded: String(uri[uri.index(after: comma)...])), !bytes.isEmpty else {
                        throw AgentImageError("Invalid image data URI.")
                    }
                    let header = String(uri[..<comma])
                    let types = ["data:image/png;base64": ("image/png", "png"),
                                 "data:image/jpeg;base64": ("image/jpeg", "jpg"),
                                 "data:image/webp;base64": ("image/webp", "webp")]
                    guard let (mime, ext) = types[header] else { throw AgentImageError("Binary edits require PNG, JPEG or WebP image data.") }
                    append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"image_\(index).\(ext)\"\r\nContent-Type: \(mime)\r\n\r\n")
                    body.append(bytes); append("\r\n")
                }
                append("--\(boundary)--\r\n")
                request.httpBody = body
                return request
            }
            request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            var body = parameters
            body["model"] = model; body["prompt"] = prompt; body["response_format"] = "b64_json"
            if let first = imageDataURIs.first {
                body[row.imageInputParam] = row.acceptsMultiImages ? imageDataURIs : first as Any
                if imageDataURIs.count > 1, !row.acceptsMultiImages, let second = row.secondImageParam { body[second] = imageDataURIs[1] }
            }
            data = try JSONSerialization.data(withJSONObject: body)
        case .comfyUI: throw AgentImageError("ComfyUI is outside this image contract.")
        }
        request.httpMethod = "POST"; request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return request
    }
}
