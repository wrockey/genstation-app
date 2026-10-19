// The 167 captured per-model OpenAPI 3.0 documents, and the only place that path is spelled.
//
// Captured 2026-07-27 from every served model's `info.docsJson` and committed at `b16f840` — see
// `Fixtures/README.md`. They are published documentation in machine-readable form, not a probe
// harness: fetching them cost no generation credits.
//
// Stage 3 PINS these; it does not verify against them. The full enum/default/required comparison is
// the separate docs-verification workstream (spec § 4.8). The one thing Stage 3 takes from them is
// the recorded baseline in `UndocumentedKeyBaselineTests`.

import Foundation
@testable import GenStationCore

enum AIMLSchemaFixture {

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/aiml-model-schemas.json")
            .standardizedFileURL
    }

    /// Lowercased served id -> the whole OpenAPI document.
    static func documents() throws -> [String: [String: Any]] {
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        guard let root = object as? [String: [String: Any]] else {
            throw NSError(domain: "AIMLSchemaFixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                                        "\(url.path) is not a dictionary of documents"])
        }
        return Dictionary(uniqueKeysWithValues: root.map { ($0.key.lowercased(), $0.value) })
    }

    /// Lowercased served id -> every request-body property the model's own schema documents, unioned
    /// across the operations the document declares.
    static func documentedProperties() throws -> [String: Set<String>] {
        try documents().mapValues { document in
            var names: Set<String> = []
            let paths = document["paths"] as? [String: Any] ?? [:]
            for operations in paths.values {
                for operation in (operations as? [String: Any] ?? [:]).values {
                    let body = (operation as? [String: Any])?["requestBody"] as? [String: Any]
                    let content = body?["content"] as? [String: Any]
                    let json = content?["application/json"] as? [String: Any]
                    let schema = json?["schema"] as? [String: Any]
                    let properties = schema?["properties"] as? [String: Any] ?? [:]
                    names.formUnion(properties.keys)
                }
            }
            return names
        }
    }

    /// Lowercased served id -> request-body key -> the set of values that key's schema permits,
    /// normalised by `EnumValue`. A key absent from the inner dictionary is **unconstrained** — either
    /// the model does not document it, or it documents it with no `enum`.
    ///
    /// Read only from the **request body** (`paths → * → post → requestBody → …`), never from the whole
    /// document: the response half of these files carries `properties` too, and a response enum has no
    /// bearing on what may be sent.
    ///
    /// `anyOf`/`oneOf` are honoured the way JSON Schema defines them — **a value satisfying any branch
    /// is valid**. So a property with one enum branch and one free-form branch is not constrained at
    /// all, and only a property whose every branch carries an `enum` yields a constraint (the union of
    /// them). Getting this backwards would invent violations: `image_size` is exactly this shape.
    static func requestBodyEnums() throws -> [String: [String: Set<EnumValue>]] {
        try documents().mapValues { document in
            var byKey: [String: Set<EnumValue>] = [:]
            var unconstrained: Set<String> = []
            let paths = document["paths"] as? [String: Any] ?? [:]
            for operations in paths.values {
                for operation in (operations as? [String: Any] ?? [:]).values {
                    let body = (operation as? [String: Any])?["requestBody"] as? [String: Any]
                    let content = body?["content"] as? [String: Any]
                    let json = content?["application/json"] as? [String: Any]
                    let schema = json?["schema"] as? [String: Any]
                    let properties = schema?["properties"] as? [String: Any] ?? [:]
                    for (key, propertySchema) in properties {
                        guard let allowed = allowedValues(propertySchema as? [String: Any] ?? [:]) else {
                            // Unconstrained under *this* operation, so unconstrained overall: the same
                            // permissive reading as `anyOf`, one level up.
                            unconstrained.insert(key)
                            continue
                        }
                        byKey[key, default: []].formUnion(allowed)
                    }
                }
            }
            for key in unconstrained { byKey[key] = nil }
            return byKey
        }
    }

    /// The values one property schema permits, or `nil` for "not enum-constrained".
    private static func allowedValues(_ schema: [String: Any]) -> Set<EnumValue>? {
        let branches = (schema["anyOf"] as? [Any]) ?? (schema["oneOf"] as? [Any])
        if let branches {
            var union: Set<EnumValue> = []
            for branch in branches {
                // One free-form branch frees the whole property.
                guard let allowed = allowedValues(branch as? [String: Any] ?? [:]) else { return nil }
                union.formUnion(allowed)
            }
            return union.isEmpty ? nil : union
        }
        guard let literals = schema["enum"] as? [Any] else { return nil }
        return Set(literals.map(EnumValue.init(json:)))
    }

    /// A JSON scalar compared for enum membership, with numeric spelling normalised so a Swift `Int`
    /// literal and a JSON integer are the same value — `duration: 5` must match an enum of `[3, 4, 5]`.
    /// Anything that is not a scalar (Kling's `camera_control` object) hashes as `.other` and can only
    /// equal itself, which is the correct answer: an object is never a member of a scalar enum.
    enum EnumValue: Hashable, CustomStringConvertible {
        case text(String)
        case number(Double)
        case flag(Bool)
        case other(String)

        init(json value: Any) {
            if let text = value as? String { self = .text(text); return }
            if let number = value as? NSNumber {
                // **Not `as? Bool`.** `NSNumber(1) as? Bool` succeeds and returns `true`, so an
                // integer `1` in an enum would be filed as a boolean and stop matching an emitted
                // `1`. `CFBooleanGetTypeID` is the only reliable discriminator, and both a JSON
                // `true` and a bridged Swift `Bool` are `__NSCFBoolean`.
                self = CFGetTypeID(number) == CFBooleanGetTypeID()
                    ? .flag(number.boolValue) : .number(number.doubleValue)
                return
            }
            if let flag = value as? Bool { self = .flag(flag); return }
            // Dictionary ordering is not stable across runs, so a composite value like Kling's
            // `camera_control` object has to be described in sorted key order or anything pinned
            // against it fails at random.
            if let object = value as? [String: Any] {
                let pairs = object.keys.sorted().map { "\($0): \(String(describing: object[$0]!))" }
                self = .other("[" + pairs.joined(separator: ", ") + "]")
                return
            }
            self = .other(String(describing: value))
        }

        var description: String {
            switch self {
            case .text(let v):   return "\"\(v)\""
            case .number(let v): return v == v.rounded() ? String(Int(v)) : String(v)
            case .flag(let v):   return String(v)
            case .other(let v):  return v
            }
        }
    }

    /// Lowercased spelling (id or alias) -> the lowercased canonical id the schemas are keyed by.
    static func canonicalIDBySpelling() throws -> [String: String] {
        var out: [String: String] = [:]
        for entry in try AIMLModelsFixture.response().data {
            let canonical = entry.id.lowercased()
            out[canonical] = canonical
            for alias in entry.aliases ?? [] {
                if out[alias.lowercased()] == nil { out[alias.lowercased()] = canonical }
            }
        }
        return out
    }
}
