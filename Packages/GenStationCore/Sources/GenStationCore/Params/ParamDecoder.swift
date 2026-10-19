// ParamDecoder — a request body back into `ModelParameters` (Stage 2, Task 6b).
//
// Replaces the 67 hand-written `ParameterParser` functions. Three live consumers depend on this
// direction existing, and Task 11 deletes the legacy layer out from under all three:
//
//   • `MCPService.swift:585` — seeds a model's defaults by running its parser on `[:]` (`defaults`)
//   • `MCPService.swift:663` — applies an agent's parameter overrides
//   • `HistoryView.swift:2163` — **history re-run**. A history entry stores the literal submitted
//     payload and no parameters, so decoding it is the only way a past generation can be re-run.
//
// Decoding is deliberately context-free: a stored payload has no `ParamContext`, and the legacy
// parsers never had one either. `visibleWhen` gates rendering and emission, not reading.

import Foundation

public enum ParamDecoder {

    /// Reads every descriptor's key out of `json` — `parseKey` where the row names one, `wireKey`
    /// otherwise — and writes it to the field the descriptor names.
    ///
    /// A key that is missing — or present with a type the field cannot hold, which the legacy
    /// `as?` cast treats the same way — takes the row's `parseFallback`. So does a row with **no**
    /// key: a control that never reaches the wire is still something the legacy parser had an
    /// opinion about, and `.leaveUnchanged` (the default) is the row that has none.
    public static func decode(_ descriptors: [ParamDescriptor],
                              from json: [String: Any],
                              into params: inout ModelParameters) {
        for descriptor in descriptors {
            // The composites read one wire key and write several fields, so they have nothing to do
            // without one. Only `.info` rows reach this today.
            if case .imageSize(let spec) = descriptor.control {
                guard !descriptor.wireKey.isEmpty else { continue }
                decodeImageSize(json[descriptor.wireKey], spec: spec, into: &params)
                continue
            }

            if case .custom(.klingCameraControl) = descriptor.control {
                guard !descriptor.wireKey.isEmpty else { continue }
                decodeKlingCameraControl(json[descriptor.wireKey], into: &params)
                continue
            }

            guard let field = descriptor.field else { continue }

            let key = descriptor.parseKey ?? descriptor.wireKey
            if !key.isEmpty, let raw = json[key], let value = ParamValue(raw, as: field.kind) {
                params[field] = value
                continue
            }

            switch descriptor.parseFallback {
            case .leaveUnchanged:      break
            case .setNil:              params[field] = nil
            case .value(let fallback): params[field] = fallback
            }
        }
    }

    /// The parameters a model starts with: the descriptors applied to an empty payload. Exactly what
    /// `MCPService` gets today from running a model's `ParameterParser` on `[:]`.
    public static func defaults(_ descriptors: [ParamDescriptor]) -> ModelParameters {
        var params = ModelParameters()
        decode(descriptors, from: [:], into: &params)
        return params
    }

    /// The `image_size` composite, reproducing `LegacyPayload.parseImageSize` and the 15 copies of it
    /// inlined in the other builders' parsers: a String is a preset, an object is custom dimensions,
    /// and anything else — including an absent key — falls back to the model's own preset.
    ///
    /// That last fallback is the reason `spec` is threaded through here as well as into the encoder:
    /// the copies do not agree on it (`landscape_4_3`, `square_hd` and `2K` are all live), so a
    /// hard-coded `landscape_4_3` would have quietly changed what 7 models re-run a history entry as.
    private static func decodeImageSize(_ raw: Any?, spec: ImageSizeSpec, into params: inout ModelParameters) {
        if let preset = raw as? String {
            params.imageSizeMode = "preset"; params.imageSizePreset = preset
        } else if let object = raw as? [String: Int], let width = object["width"], let height = object["height"] {
            params.imageSizeMode = "custom"; params.customWidth = width; params.customHeight = height
        } else {
            params.imageSizeMode = "preset"; params.imageSizePreset = spec.presetFallback
        }
    }

    /// Kling's `camera_control` composite, reproducing `LegacyPayload.klingVideoParameterParser`: a
    /// String is a preset name, an object means the advanced mode and carries the two movement
    /// fields, and anything else — including an absent key — clears the mode.
    ///
    /// The scalar path could not do this: the key holds an object in one branch, which no
    /// `ParamField` can store, and it writes three fields from one key.
    private static func decodeKlingCameraControl(_ raw: Any?, into params: inout ModelParameters) {
        if let preset = raw as? String {
            params.cameraControl = preset
        } else if let object = raw as? [String: Any] {
            params.cameraControl = "advanced"
            params.cameraMovementType = object["movement_type"] as? String ?? "horizontal"
            params.cameraMovementValue = object["movement_value"] as? Int ?? 0
        } else {
            params.cameraControl = nil
        }
    }
}

extension ParamValue {
    /// Reads an untyped JSON value as the kind a field's storage accepts, or `nil` if it cannot be.
    ///
    /// `JSONSerialization` hands back `NSNumber` for every number, so an integral literal must still
    /// satisfy a Double field — which is what `as? Double` did in the legacy parsers. `Bool` is
    /// checked first and separately because `NSNumber` bridges to both `Bool` and `Int`.
    init?(_ raw: Any, as kind: Kind) {
        switch kind {
        case .string:
            guard let value = raw as? String else { return nil }
            self = .string(value)
        case .bool:
            guard let value = raw as? Bool else { return nil }
            self = .bool(value)
        case .int:
            guard !(raw is Bool), let value = raw as? Int else { return nil }
            self = .int(value)
        case .double:
            guard !(raw is Bool), let value = raw as? Double else { return nil }
            self = .double(value)
        }
    }
}
