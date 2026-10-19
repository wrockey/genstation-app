// ParamDescriptor — one declarative row per model parameter (Stage 2, Task 6).
//
// A model's parameter list is written down three times today: as SwiftUI controls, as a
// `JSONBuilder`, and as a `ParameterParser`. Nothing makes them agree. `ParamDescriptor` is the one
// declaration that drives all three, so they cannot disagree.
//
// It is pure data and lives in `GenStationCore`, which bans SwiftUI — so the escape hatch for a
// bespoke control is `Control.custom`, carrying a **token** the app-side renderer resolves, not an
// `AnyView`. That is what keeps the per-model equivalence fixtures possible at all.

import Foundation

/// One parameter of one model: where it lives in `ModelParameters`, what it is called on the wire,
/// how it is rendered, and when it exists at all.
public struct ParamDescriptor: Sendable {

    /// The key this row occupies in the request body — e.g. `"cfg_scale"`. Empty for a UI-only row
    /// (`.info`), which never reaches the wire.
    public let wireKey: String

    /// The `ModelParameters` property this row reads and writes. **Not derivable from `wireKey` and
    /// never derive one from the other:** `cfg_scale` stores into `guidanceScale` for Kling 2.5-turbo
    /// but into `cfgScale` for the other Kling models, and Gemini 3 Pro's `resolution` stores into
    /// `geminiResolution`.
    ///
    /// `nil` for rows with no storage: `.info` panels, the `image_size` composite (which is fed by
    /// four fields), and literal constants some builders emit (`dict["aspect_ratio"] = "16:9"`).
    public let field: ParamField?

    public let label: String
    public let help: String?
    public let control: Control

    /// What the UI shows when the field is nil. **It is not a substitute value for encoding** — see
    /// `ParamEncoder`. It is also the value an `alwaysEmit` row falls back to, which is the one place
    /// it does reach the wire.
    public let defaultValue: ParamValue?

    /// `nil` means unconditional. A row whose predicate is false is **neither rendered nor emitted** —
    /// design § 3.2, the rule that kills the hidden-but-emitted bug class.
    public let visibleWhen: Condition?

    /// Emit even when the field is nil, falling back to `defaultValue`. Covers the 47 unconditional
    /// `dict["k"] = ...` assignments in the legacy builders — including the 14
    /// `enable_safety_checker` and 6 `safety_tolerance` rows that ship with no control anywhere.
    public let alwaysEmit: Bool

    /// Skip emission when the value is an empty string. 15 legacy builders gate a String this way
    /// (`negative_prompt`, PixVerse's `style`). This is emission-only: the control stays visible when
    /// the string is empty, because the user needs somewhere to type.
    public let omitWhenEmpty: Bool

    /// A further emission guard on the **stored value**, or `nil` for the rows that emit whatever they
    /// hold. Seven builders carry one, in three shapes — see `EmitGuard`.
    ///
    /// **Which way the visibility/emission implication runs.** `visibleWhen == false` forces omission
    /// (`ParamEncoder` checks it first, and that is the rule that kills the hidden-but-emitted bug
    /// class). The converse does **not** hold and must not be assumed: a visible row may still be
    /// omitted, by nilness, by `omitWhenEmpty`, or by this guard. Keeping the implication one-way is
    /// what lets a control be shown while its key stays off the wire — which is a real legacy shape, not
    /// an accident. Kling v3's `shot_type` is the reason this field is not folded into `visibleWhen`:
    /// its legacy view rendered the picker unconditionally
    /// (`Params View/KlingV3ParamsView.swift:111-119`, no `if`) while its builder emitted the key only
    /// at one of the two values (`Legacy/Kling.swift:71`,
    /// `if let s = params.shotType, s == "customize"`). Expressing that emission rule as `visibleWhen`
    /// hid the control at its own default, so it could never be moved off that default — the guard
    /// suppressed the very edit that would have satisfied it.
    public let emitWhen: EmitGuard?

    /// The key the **decoder** reads, when it is not `wireKey`. `nil` means "same as `wireKey`",
    /// which is every row but one.
    ///
    /// Emission and parsing are two wire contracts, and the legacy code does not always give them
    /// the same key. `wanImageEditJSONBuilder` builds the shared Wan image payload and then
    /// *removes* `num_images` (`Legacy/Alibaba.swift:202-206`), while the parser it shares with its
    /// t2i sibling still **reads** `num_images` (`:193`). So the row is emit-never, parse-`num_images`,
    /// and `wireKey: ""` alone would silently drop the field on history re-run.
    ///
    /// Design § 3.2 unifies **visibility and emission**; it deliberately says nothing about parsing,
    /// which is context-free (see `ParamDecoder`). This is that seam, named rather than fudged.
    public let parseKey: String?

    /// What the decoder does when the key is absent from a payload — or present with the wrong
    /// type, which the legacy `as?` cast treats identically.
    ///
    /// A row with **no** key at all always takes this: `wan26VideoI2VParameterParser` renders an
    /// aspect-ratio control that never reaches the wire and then explicitly clears the field
    /// (`Legacy/Alibaba.swift:173-176`), which is `.setNil` on a row with no key.
    ///
    /// This is a **separate value from `defaultValue`, and it has to be**: `alibaba/wan-2-6-t2v`
    /// shows "720p" in the UI (the struct default) but its parser substitutes "1080p" for an absent
    /// `resolution`. Design § 5 records that there are three defaults today and that they already
    /// disagree; a single field cannot freeze both behaviours, and Stage 2 freezes behaviour.
    public let parseFallback: ParseFallback

    /// A stale-value clamp applied on the way to the wire, or `nil` for the 24 of 29 video builders
    /// that emit the stored value untouched.
    ///
    /// Five legacy video builders do **not**: `sora2JSONBuilder`, `googleVeo31I2VFastJSONBuilder`,
    /// `seedance10ProJSONBuilder` and the two constant-valued rows (`ltxv2`'s `aspect_ratio`,
    /// `sora2`'s `resolution`) substitute a fallback when the stored value is outside the set the
    /// model accepts, so that a value left over from a previously selected model cannot ship. That
    /// is behaviour, not decoration — `duration: 5` reaches Veo 3.1 as `8` — and Stage 2 freezes
    /// behaviour, so the table has to carry it. Clamping applies to emission only; the legacy
    /// parsers never clamped, and neither does `ParamDecoder`.
    public let emitClamp: EmitClamp?

    /// The exact set of values this model's **published schema** accepts for `wireKey`, or `nil` for a
    /// key with no documented `enum`.
    ///
    /// This is the fix for a whole bug class, not a nicety. `ModelParameters` carries one
    /// `resolution`, one `duration`, one `style` and one `aspect_ratio` **shared across every model**,
    /// and 17 of its fields have non-nil struct defaults — `resolution: "720p"`, `duration: 5`,
    /// `frameRate: 30`. `ParamDefaults.merge` only fills fields that are *nil*, so for those 17 the
    /// model's own `defaultValue` can never apply (drift ledger § A.3/§ B.11). The consequence, found
    /// on 2026-07-28 and user-approved the same day: `googleVeo3T2V` already declared the correct
    /// `"720P"` picker and default, and still shipped `"720p"` on **every** request, because the
    /// struct default is the stored value and the stored value is what gets emitted. 42 registered
    /// models answered "Validation failed. Please check your request fields and values." with no user
    /// action needed to trigger it.
    ///
    /// So the correction cannot live in `defaultValue` — a stale value carried in from a *previously
    /// selected* model reproduces it immediately, and that path is reachable even once the defaults
    /// are right. It has to be enforced where the value reaches the wire. See `ParamEncoder` for the
    /// two-rule resolution: a case-only mismatch is corrected to the schema's spelling, and anything
    /// else omits the key so the API applies its own documented default.
    ///
    /// **Never substitute a different value here.** `720p` → `1080p` changes what the user is charged
    /// and `style: realistic` → `anime` changes what they get; omission cannot.
    public let allowedValues: [ParamValue]?

    /// Decode a retired control from saved history without displaying or submitting it.
    var historyOnly: ParamDescriptor {
        ParamDescriptor(wireKey: "", field: field, label: label, help: nil, control: .none,
            defaultValue: defaultValue, visibleWhen: nil, alwaysEmit: false,
            parseKey: parseKey ?? wireKey, parseFallback: parseFallback)
    }

    public init(wireKey: String,
                field: ParamField?,
                label: String,
                help: String?,
                control: Control,
                defaultValue: ParamValue?,
                visibleWhen: Condition?,
                alwaysEmit: Bool,
                omitWhenEmpty: Bool = false,
                emitWhen: EmitGuard? = nil,
                parseKey: String? = nil,
                parseFallback: ParseFallback = .leaveUnchanged,
                emitClamp: EmitClamp? = nil,
                allowedValues: [ParamValue]? = nil) {
        self.allowedValues = allowedValues
        self.parseKey = parseKey
        self.parseFallback = parseFallback
        self.emitClamp = emitClamp
        self.emitWhen = emitWhen
        self.wireKey = wireKey
        self.field = field
        self.label = label
        self.help = help
        self.control = control
        self.defaultValue = defaultValue
        self.visibleWhen = visibleWhen
        self.alwaysEmit = alwaysEmit
        self.omitWhenEmpty = omitWhenEmpty
    }

    /// A static explanatory panel: the 29 `Notes`/`… Required` blocks the legacy param views drew
    /// above or below their controls.
    ///
    /// It cannot reach the wire and the type says so — `wireKey` is empty and `field` is nil, which
    /// is the pair `ParamEncoder` skips — so adding one to a table is display-only by construction,
    /// not by convention.
    public static func info(label: String,
                            text: String,
                            visibleWhen: Condition? = nil) -> ParamDescriptor {
        ParamDescriptor(wireKey: "",
                        field: nil,
                        label: label,
                        help: nil,
                        control: .info(text: text),
                        defaultValue: nil,
                        visibleWhen: visibleWhen,
                        alwaysEmit: false)
    }

    /// The single visibility decision, shared by the renderer and the encoder. Both must call this —
    /// that identity *is* the design.
    public func isVisible(params: ModelParameters, context: ParamContext) -> Bool {
        guard let visibleWhen else { return true }
        return visibleWhen.holds(params: params, context: context)
    }
}

/// How a row is rendered. Only four SwiftUI primitives appear across all 61 legacy param views —
/// Picker, TextField, Slider, Toggle — plus two repeated composites and one info panel.
public enum Control: Sendable {

    public enum PickerStyle: Sendable {
        case menu
        case segmented
    }

    /// A token the app-side renderer maps to a bespoke view. Nested here rather than left at the
    /// package's top level, per the namespace rule (§ 4.1) and because a bare `CustomControl` would
    /// read ambiguously beside SwiftUI in the app target.
    public enum CustomControl: String, Sendable {
        /// Kling's camera-control block: a mode picker that reveals a movement type and an
        /// intensity slider, and collapses to a nested `camera_control` object on the wire.
        case klingCameraControl
    }

    case picker(options: [ParamValue], style: PickerStyle)
    case text(placeholder: String)
    case slider(range: ClosedRange<Double>, step: Double)
    case toggle
    /// Covers all 31 "randomize" buttons, which use six different ranges — so the range is data.
    case seed(range: ClosedRange<Int>)
    /// The `image_size` composite: one wire key fed by four fields and a mode switch that changes
    /// the emitted JSON *type* (preset String vs `{width, height}` object). The spec is per model —
    /// the 16 legacy builders that write this key do **not** agree on their fallbacks or their
    /// dimension arithmetic. See `ImageSizeSpec`.
    case imageSize(ImageSizeSpec)
    /// A static explanatory panel. UI only.
    case info(text: String)
    /// Emitted but not rendered.
    case none
    case custom(CustomControl)
}

/// How one model spells the `image_size` composite — the per-model half of `Control.imageSize`.
///
/// The composite looked uniform from the video side, where nothing uses it. It is not. The 16 legacy
/// builders that write `image_size` agree only on the *shape* (a preset String in "preset" mode, a
/// `{width, height}` object in "custom" mode) and disagree on everything else, so a single hard-coded
/// helper would have silently changed the payload of 13 of them:
///
/// | builders | preset fallback | w × h fallback | dimension arithmetic |
/// |---|---|---|---|
/// | `wanImage`, `wanImageEdit` (the shared `LegacyPayload.imageSizeValue`) | `landscape_4_3` | 1024 × 1024 | none |
/// | `fluxDev`, `fluxPro`, `fluxSchnell`, `fluxRealism`, `fluxSrpo`, `fluxSrpoI2i` | `landscape_4_3` | 1024 × **768** | none |
/// | `flux2Pro`, `flux2ProEdit` | `landscape_4_3` | 1024 × 1024 | round **up to a multiple of 32**, then **omit the key entirely** if either side exceeds 2048 |
/// | `recraftV3`, `seedreamV4`, `seedreamV4Edit`, `hunyuanImageV3`, `stableDiffusionV35Large`, `stableDiffusionV3Medium` | **`square_hd`** | 1024 × 1024 | none |
/// | `seedream45` | **`2K`** | **2048 × 2048** | raise each side to **at least 1440** |
///
/// `presets` and `dimensions` are the option lists the model's own view offers. They are display-only
/// — nothing on the wire reads them — but they are per-model too (`seedream45` offers `2K`/`4K` where
/// everyone else offers the six `square_hd`-family presets, and there are eight distinct dimension
/// lists), so the generic renderer needs them to reproduce what each legacy view showed.
public struct ImageSizeSpec: Sendable, Equatable {

    /// The preset picker's options, in the order the legacy view listed them. Display only.
    public let presets: [String]

    /// The preset emitted when `imageSizePreset` is nil — and, on the way back in, what an absent or
    /// unreadable `image_size` decodes to.
    public let presetFallback: String

    /// The width/height pickers' options. Display only.
    public let dimensions: [Int]

    public let widthFallback: Int
    public let heightFallback: Int

    /// Round each side **up** to a multiple of this. `flux2Pro` only.
    public let roundUpToMultipleOf: Int?

    /// Raise each side to at least this. `seedream45` only.
    public let minimumDimension: Int?

    /// If either side exceeds this, the whole key is **omitted** rather than clamped. `flux2Pro` only,
    /// and it really does drop the key — the model then gets no `image_size` at all.
    public let maximumDimension: Int?

    public init(presets: [String],
                presetFallback: String,
                dimensions: [Int],
                widthFallback: Int,
                heightFallback: Int,
                roundUpToMultipleOf: Int? = nil,
                minimumDimension: Int? = nil,
                maximumDimension: Int? = nil) {
        self.presets = presets
        self.presetFallback = presetFallback
        self.dimensions = dimensions
        self.widthFallback = widthFallback
        self.heightFallback = heightFallback
        self.roundUpToMultipleOf = roundUpToMultipleOf
        self.minimumDimension = minimumDimension
        self.maximumDimension = maximumDimension
    }
}

/// An emission guard on a row's stored value, beyond "is it nil".
///
/// Both cases are read out of a legacy builder, and both mean the same thing in practice: **the model
/// is sent nothing when the user leaves the control at its default.** Whether that is intentional
/// API-surface trimming or an accident is not knowable from this repository (design § 2), so Stage 2
/// freezes it and the ledger records it.
public enum EmitGuard: Sendable, Equatable {

    /// `if let x = params.f, x != v` — four rows: Kling Image O1's `aspect_ratio`/`resolution` and
    /// Gemini 3 Pro's, on both its t2i and its edit builder.
    case notEqualTo(ParamValue)

    /// `if let n = params.numImages, n > 1` (`.atLeast(2)`), `n > 0` (`.atLeast(1)`) and
    /// `if let seed = params.seed, seed >= 1` (`.atLeast(1)`). Ints only; a non-Int value passes,
    /// which cannot arise because every row carrying this guard names an Int field.
    case atLeast(Int)

    /// `if let x = params.f, x == v` — one row: Kling v3's `shot_type` (`Legacy/Kling.swift:71`),
    /// whose picker offers `intelligent` and `customize` but whose builder ships the key only for
    /// `customize`. The control is visible at both values; only one of them reaches the wire.
    case equalTo(ParamValue)

    func allows(_ value: ParamValue) -> Bool {
        switch self {
        case .notEqualTo(let excluded):
            return value != excluded
        case .equalTo(let required):
            return value == required
        case .atLeast(let minimum):
            guard case .int(let stored) = value else { return true }
            return stored >= minimum
        }
    }
}

/// The emit-time clamp of `ParamDescriptor.emitClamp`: an ordered list of rules, first match wins.
///
/// Ordering matters because one clamp is conditional on another field. Veo's aspect ratio is
/// `["16:9", "9:16", "1:1"]` at 720p and `["16:9", "9:16"]` otherwise, which is two rules — the 720p
/// one first, then an unconditional catch-all.
public struct EmitClamp: Sendable {

    public struct Rule: Sendable {
        /// `nil` matches unconditionally. A rule list should end with one, or a value outside every
        /// guarded rule's set is emitted unclamped.
        public let when: Condition?
        public let allowed: [ParamValue]
        public let fallback: ParamValue

        public init(when: Condition? = nil, allowed: [ParamValue], fallback: ParamValue) {
            self.when = when
            self.allowed = allowed
            self.fallback = fallback
        }
    }

    public let rules: [Rule]

    public init(_ rules: [Rule]) { self.rules = rules }

    /// `value` if the first matching rule allows it, that rule's fallback if not, and `value`
    /// untouched if no rule matches at all.
    func clamp(_ value: ParamValue, params: ModelParameters, context: ParamContext) -> ParamValue {
        guard let rule = rules.first(where: { $0.when?.holds(params: params, context: context) ?? true })
        else { return value }
        return rule.allowed.contains(value) ? value : rule.fallback
    }
}

/// The three shapes the 67 legacy `ParameterParser` functions use for a key that is not in the
/// payload. All three are load-bearing; see `ParamDescriptor.parseFallback`.
public enum ParseFallback: Equatable, Sendable {
    /// The parser does not touch this field. Leaves whatever the caller already had.
    case leaveUnchanged
    /// `params.x = json["k"] as? T` — a bare cast, so an absent key clears the field.
    case setNil
    /// `params.x = json["k"] as? T ?? v` — the parser's own default.
    case value(ParamValue)
}

/// The whole predicate vocabulary across all 61 legacy param views is three forms. Two are here; the
/// third (`mode == "preset"`) is internal to `Control.imageSize`.
public enum Condition: Sendable {
    case hasNoInputImages
    case fieldEquals(ParamField, ParamValue)
    /// Legacy `!model.isI2I`. Reads `ParamContext.isI2I` — the **static** registry flag.
    ///
    /// That flag is an unsound proxy for the real mode: Seedance sets `isI2I: true` on dual-mode
    /// T2V/I2V models, which is why its aspect-ratio gate never fires. Keying this on
    /// `context.hasInputImages` instead is the correction — and a deliberate later wave, recorded in
    /// the drift ledger, because it changes outgoing payloads and fails equivalence by design.
    case isTextToVideo

    /// Legacy `model.isI2I` — the complement of `.isTextToVideo`, and it reads the same **static**
    /// registry flag, with the same unsoundness.
    ///
    /// Only `.info` rows carry it: seven legacy views wrapped an "Input Image Required" panel in
    /// `if model.isI2I`, and a panel that has no wire key cannot be expressed as `.isTextToVideo` on
    /// some other row. Nothing that emits uses it, so it cannot move a payload.
    case isImageToVideo

    func holds(params: ModelParameters, context: ParamContext) -> Bool {
        switch self {
        case .fieldEquals(let field, let expected):
            return params[field] == expected
        case .hasNoInputImages:
            return !context.hasInputImages
        case .isTextToVideo:
            return !context.isI2I
        case .isImageToVideo:
            return context.isI2I
        }
    }
}

/// A typed parameter value. The four cases are exactly the JSON scalars the legacy builders emit.
public enum ParamValue: Equatable, Sendable {

    /// Which case a value carries, independent of its payload. `ParamField.kind` names the one case
    /// each storage property accepts.
    public enum Kind: Sendable, Equatable {
        case string, int, double, bool
    }

    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public var kind: Kind {
        switch self {
        case .string: return .string
        case .int:    return .int
        case .double: return .double
        case .bool:   return .bool
        }
    }

    /// The value as it goes into the request body.
    var jsonValue: Any {
        switch self {
        case .string(let v): return v
        case .int(let v):    return v
        case .double(let v): return v
        case .bool(let v):   return v
        }
    }
}

/// Everything the renderer and the encoder need to know about the model beyond its parameters.
public struct ParamContext: Sendable {
    public let modelId: String

    /// The **static** registry flag, carrying frozen legacy semantics. This is what `.isTextToVideo`
    /// evaluates against.
    public let isI2I: Bool

    /// The true mode — whether the user actually supplied input images. Carried because the renderer
    /// and later waves need it; **not consulted by `Condition` yet**, deliberately (see
    /// `Condition.isTextToVideo`).
    public let hasInputImages: Bool

    public init(modelId: String, isI2I: Bool, hasInputImages: Bool) {
        self.modelId = modelId
        self.isI2I = isI2I
        self.hasInputImages = hasInputImages
    }
}
