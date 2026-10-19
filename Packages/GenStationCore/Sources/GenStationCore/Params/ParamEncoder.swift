// ParamEncoder — descriptors to a request body (Stage 2, Task 6).
//
// Replaces the 68 hand-written `JSONBuilder` functions. The equivalence harness (Task 7) asserts,
// per model and per probe, that what this produces is byte-for-byte what the legacy builder produced.

import Foundation

public enum ParamEncoder {

    /// Builds the parameter half of a request body.
    ///
    /// Three rules, in order:
    ///
    /// 1. **A row that is not visible is not emitted.** One predicate governs both, which is what
    ///    stops a hidden control shipping on the wire (design § 3.2).
    /// 2. **A row is emitted iff its field is non-nil** — unless `alwaysEmit`, which falls back to
    ///    `defaultValue`. `defaultValue` is otherwise a UI display value, *not* a substitute for
    ///    encoding: `flux/dev` carries a `guidance_scale` default but its legacy builder emits the
    ///    key only via `if let`, so treating the default as a substitute would emit a key the legacy
    ///    builder omits.
    /// 3. `omitWhenEmpty` then drops empty strings, reproducing the 15 `!isEmpty` builder gates.
    /// 4. `emitClamp` last, substituting a fallback for a value the model does not accept —
    ///    reproducing the five video builders that refuse to ship a stale value.
    /// 5. `allowedValues` last of all: a value the model's **published schema** does not accept is
    ///    corrected if the only difference is case, and otherwise **omitted** — see `schemaChecked`.
    public static func encode(_ descriptors: [ParamDescriptor],
                              params: ModelParameters,
                              context: ParamContext) -> [String: Any] {
        var dict: [String: Any] = [:]
        for descriptor in descriptors {
            guard descriptor.isVisible(params: params, context: context) else { continue }
            guard !descriptor.wireKey.isEmpty else { continue }   // `.info` and other UI-only rows

            if case .imageSize(let spec) = descriptor.control {
                // `nil` is a real outcome, not "no value": `flux2Pro` drops the key when a custom
                // dimension exceeds 2048.
                if let value = imageSizeValue(params, spec: spec),
                   let checked = schemaChecked(value, against: descriptor.allowedValues) {
                    dict[descriptor.wireKey] = checked
                }
                continue
            }

            if case .custom(.klingCameraControl) = descriptor.control {
                if let value = klingCameraControlValue(params),
                   let checked = schemaChecked(value, against: descriptor.allowedValues) {
                    dict[descriptor.wireKey] = checked
                }
                continue
            }

            let stored = descriptor.field.flatMap { params[$0] }
            guard var value = stored ?? (descriptor.alwaysEmit ? descriptor.defaultValue : nil) else { continue }
            if descriptor.omitWhenEmpty, case .string(let text) = value, text.isEmpty { continue }
            if let guard_ = descriptor.emitWhen, !guard_.allows(value) { continue }
            if let clamp = descriptor.emitClamp {
                value = clamp.clamp(value, params: params, context: context)
            }
            guard let checked = schemaChecked(value.jsonValue, against: descriptor.allowedValues) else {
                // A rejected value on an `alwaysEmit` row falls back to that row's own `defaultValue`
                // rather than omitting the key, because `alwaysEmit` means "this key is always
                // present" and some of those keys are **required** — `mode` is required by both Topaz
                // sharpen models, so dropping it trades one validation failure for another. This is
                // not the substitution the omission rule forbids: `defaultValue` is the value the row
                // already ships whenever its field is nil, and the value its own picker displays, so
                // the user sees what is sent. It still has to satisfy the schema, or the key goes.
                if descriptor.alwaysEmit, let fallback = descriptor.defaultValue,
                   let permitted = schemaChecked(fallback.jsonValue, against: descriptor.allowedValues) {
                    dict[descriptor.wireKey] = permitted
                }
                continue
            }
            dict[descriptor.wireKey] = checked
        }
        return dict
    }

    /// One published value per enum-constrained key, for **schema advertisement only** — never for a
    /// request body.
    ///
    /// `MCPService.paramSchema` synthesises the agent-facing schema by encoding two probes and taking
    /// the union of the keys they produce, and the gate that validates an agent's `params` is exactly
    /// that key set. Both probes carry the shared `ModelParameters` defaults, so for a model whose
    /// schema rejects those defaults, rule 5 now omits the key — and the key would vanish from the
    /// gate, rejecting a value an agent is entitled to send. `pixverse/*` is the clear case: no probe
    /// produces a valid `style`, so `style` would stop being accepted at all even though five styles
    /// are published.
    ///
    /// Restoring the key from its own `allowedValues` keeps the gate exactly as wide as it was and
    /// makes the advertised example **valid**, which the probe-derived one was not: agents were being
    /// shown `resolution: "720p"` for models that publish `["1k", "2k"]`.
    public static func enumExamples(_ descriptors: [ParamDescriptor]) -> [String: Any] {
        var out: [String: Any] = [:]
        for descriptor in descriptors where !descriptor.wireKey.isEmpty {
            guard let allowed = descriptor.allowedValues, let first = allowed.first else { continue }
            // The row's own default when the model accepts it, so the advertised value stays the one
            // the app would really send; otherwise the first value the model publishes.
            let preferred = descriptor.defaultValue.flatMap {
                schemaChecked($0.jsonValue, against: allowed)
            }
            out[descriptor.wireKey] = preferred ?? first.jsonValue
        }
        return out
    }

    /// Rule 5: reconcile a value with the model's published `enum`, or refuse to send it.
    ///
    /// Returns the value to emit, or `nil` to **omit the key entirely**. Three outcomes:
    ///
    /// 1. `allowed` is `nil` (the key has no documented enum) or already contains the value — emit
    ///    it untouched. This is every key on every model that was already correct, so the common
    ///    path cannot change a payload.
    /// 2. Exactly one allowed value differs from a `String` value **only in case** — emit that one,
    ///    in the schema's spelling. `"720p"` → `"720P"`. The user asked for 720-something and gets
    ///    720-something; nothing about the request's meaning, output or price moves, so this is the
    ///    one correction safe to make silently. Ambiguity (two allowed values differing only in case
    ///    from each other) falls through to omission rather than guessing.
    /// 3. Anything else — omit, and let the API apply its own documented default.
    ///
    /// **Omission, never substitution, is the rule for case 3**, and the asymmetry is deliberate.
    /// Substituting turns `resolution: "720p"` into `"1080p"` — a real cost increase the user did not
    /// ask for — or `style: "realistic"` into `"anime"`, which is simply a different picture. Omitting
    /// yields whatever the vendor documents as the default, which is the same thing the user would
    /// have got by never touching the control. The value was going to be rejected either way: this
    /// path is only ever reached by a value the API answers with "Validation failed".
    static func schemaChecked(_ value: Any, against allowed: [ParamValue]?) -> Any? {
        guard let allowed, !allowed.isEmpty else { return value }
        let permitted = allowed.map(\.jsonValue)
        if permitted.contains(where: { matches($0, value) }) { return value }

        guard let text = value as? String else { return nil }
        let equalIgnoringCase = allowed.compactMap { candidate -> String? in
            guard case .string(let option) = candidate,
                  option.compare(text, options: .caseInsensitive) == .orderedSame else { return nil }
            return option
        }
        return equalIgnoringCase.count == 1 ? equalIgnoringCase[0] : nil
    }

    /// Equality for two `Any` JSON scalars. `ParamValue` is `Equatable`, but one side of this
    /// comparison is the composite path's untyped `Any`, so the match is done on the payload values.
    private static func matches(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case (let l as String, let r as String): return l == r
        case (let l as Bool, let r as Bool):     return l == r
        case (let l as Int, let r as Int):       return l == r
        case (let l as Double, let r as Double): return l == r
        // The wire distinguishes `5` from `5.0` (`GoldenPayloadTests` asserts the dynamic types), but
        // a schema `enum` of `[4, 6, 8]` is about the *number*, so cross-type numeric comparison is
        // right here and only here.
        case (let l as Int, let r as Double):    return Double(l) == r
        case (let l as Double, let r as Int):    return l == Double(r)
        default: return false
        }
    }

    /// The `image_size` composite: one wire key fed by four fields, whose emitted JSON *type* depends
    /// on the mode. A nil mode reads as "preset" in every one of the 16 legacy builders; everything
    /// else about the composite is per-model and comes from `spec` (see `ImageSizeSpec` for the table
    /// of who disagrees with whom).
    ///
    /// Returns `nil` when the key is not emitted at all, which happens for exactly one reason:
    /// `flux2Pro`/`flux2ProEdit` build the object only `if w <= 2048 && h <= 2048` and then emit it
    /// `if let`, so an oversized custom size ships **no** `image_size`.
    static func imageSizeValue(_ params: ModelParameters, spec: ImageSizeSpec) -> Any? {
        guard (params.imageSizeMode ?? "preset") == "custom" else {
            return params.imageSizePreset ?? spec.presetFallback
        }

        var width = params.customWidth ?? spec.widthFallback
        var height = params.customHeight ?? spec.heightFallback
        if let multiple = spec.roundUpToMultipleOf {
            width = roundedUp(width, toMultipleOf: multiple)
            height = roundedUp(height, toMultipleOf: multiple)
        }
        if let minimum = spec.minimumDimension {
            width = max(width, minimum)
            height = max(height, minimum)
        }
        if let maximum = spec.maximumDimension, width > maximum || height > maximum { return nil }
        return ["width": width, "height": height]
    }

    /// Deliberately a private copy of `Int.nextMultipleOf` rather than a call to it: that extension
    /// came along with the legacy builders in Task 5 and goes away with them in Task 11, and the
    /// encoder must not be holding one of its hands when it does.
    private static func roundedUp(_ value: Int, toMultipleOf multiple: Int) -> Int {
        guard multiple != 0 else { return value }
        let remainder = value % multiple
        guard remainder != 0 else { return value }
        return value + (multiple - remainder)
    }

    /// Kling's `camera_control` composite, reproducing `LegacyPayload.klingVideoJSONBuilder`. It is
    /// the one video row whose emitted JSON is an object rather than a scalar, and the only reason
    /// `Control.custom` exists: three fields, three outcomes, one wire key.
    ///
    /// `"none"` emits nothing, `"advanced"` emits `{movement_type, movement_value}` — and only when
    /// **both** are set, matching the legacy `if let`,`let` — and any other value is a preset name
    /// emitted as a bare String.
    static func klingCameraControlValue(_ params: ModelParameters) -> Any? {
        guard let mode = params.cameraControl else { return nil }
        if mode == "advanced" {
            guard let type = params.cameraMovementType, let value = params.cameraMovementValue else { return nil }
            return ["movement_type": type, "movement_value": value] as [String: Any]
        }
        return mode == "none" ? nil : mode
    }
}
