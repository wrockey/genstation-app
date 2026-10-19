// Descriptor tables — Google video models (Stage 2, Task 8).
//
// GENERATED from the legacy triple, not transcribed: wire keys, conditionality, `alwaysEmit` and
// the emit clamps come from each `JSONBuilder`; controls, option lists, labels and help text from
// each `build*ParamsView`; `parseFallback` from each `ParameterParser`; and `defaultValue` is the
// effective default the app produces today — the `ModelParameters` struct default where it is
// non-nil, else the parser's (design § 5). `PayloadEquivalenceTests` proves each table emits what
// its builder emits, over four probes and both modes.
//
// Behaviour is frozen, drift included. Where a view hides a control the builder emits anyway, the
// row stays — the divergence is in the drift ledger, not silently corrected here.

import Foundation

extension ParamCatalog {

    // MARK: googleVeo31I2VFastVeo31
    //
    // googleVeo31I2VFastJSONBuilder / googleVeo31I2VFastParameterParser
    // View: buildGoogleVeo31I2VFastParamsView
    // 2 registered ids: google/veo-3.1-i2v, google/veo-3.1-i2v-fast
    //
    // `google/veo-3.1-reference-to-video` was registered here until 2026-07-28 and now has its own
    // table, `googleVeo31ReferenceToVideo`. It is the only Veo 3.1 model that spells its resolutions
    // in **lower** case (`720p`/`1080p`, no `4K`) and it accepts exactly one duration, so no single
    // `allowedValues` could be right for it and its two siblings at once.
    static let googleVeo31I2VFastVeo31: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: "Choose landscape or portrait. These Veo 3.1 workflows support 16:9 and 9:16.",
            control: .picker(options: [.string("16:9"), .string("9:16")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9")),
            emitClamp: EmitClamp([
                .init(when: .fieldEquals(.resolution, .string("720p")), allowed: [.string("16:9"), .string("9:16"), .string("1:1")], fallback: .string("16:9")),
                .init(allowed: [.string("16:9"), .string("9:16")], fallback: .string("16:9"))
            ])
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: "The length of the output video in seconds.",
            control: .picker(options: [.int(4), .int(6), .int(8)], style: .menu),
            defaultValue: .int(8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(8)),
            emitClamp: EmitClamp([
                .init(allowed: [.int(4), .int(6), .int(8)], fallback: .int(8))
            ]),
            allowedValues: [.int(4), .int(6), .int(8)]
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: "The resolution of the generated video.",
            control: .picker(options: [.string("720P"), .string("1080P"), .string("4K")], style: .menu),
            defaultValue: .string("720P"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("1080P")),
            // Veo 3.1 spells these in **upper** case, so the shared struct default `"720p"` differs
            // only in case and is corrected to `"720P"` on the way out — the user asked for 720 and
            // gets 720. `4K` is added to the picker: these two ids publish it and the option list was
            // hiding a capability the models have.
            allowedValues: [.string("720P"), .string("1080P"), .string("4K")]
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Whether to generate audio for the video.",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        )
    ]

    // MARK: googleVeo31ReferenceToVideo
    //
    // 1 registered id: google/veo-3.1-reference-to-video
    //
    // Split off `googleVeo31I2VFastVeo31` on 2026-07-28. Every row below is that table's row verbatim;
    // only the option lists and `allowedValues` differ, and only because this model's published schema
    // differs: `resolution` is `["720p", "1080p"]` in lower case where its siblings are upper case with
    // a `4K`, and `duration` is the single value `8`. Nothing about parsing or defaults changed, so it
    // decodes identically to the table it came from.
    static let googleVeo31ReferenceToVideo: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: "Choose landscape or portrait. These Veo 3.1 workflows support 16:9 and 9:16.",
            control: .picker(options: [.string("16:9"), .string("9:16")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9")),
            emitClamp: EmitClamp([
                .init(when: .fieldEquals(.resolution, .string("720p")), allowed: [.string("16:9"), .string("9:16"), .string("1:1")], fallback: .string("16:9")),
                .init(allowed: [.string("16:9"), .string("9:16")], fallback: .string("16:9"))
            ])
            // No `allowedValues`: this id does not document `aspect_ratio` at all (it is on the
            // undocumented-key baseline), and an undocumented key carries no enum to check against.
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: "The length of the output video in seconds.",
            control: .picker(options: [.int(8)], style: .menu),
            defaultValue: .int(8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(8)),
            emitClamp: EmitClamp([
                .init(allowed: [.int(4), .int(6), .int(8)], fallback: .int(8))
            ]),
            // 8 is the only duration this model publishes. The clamp above already substitutes 8 for
            // the struct default 5, so this guard never fires today — it is here so that widening the
            // clamp cannot quietly widen the wire.
            allowedValues: [.int(8)]
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: "The resolution of the generated video.",
            control: .picker(options: [.string("720p"), .string("1080p")], style: .menu),
            defaultValue: .string("720p"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("1080p")),
            allowedValues: [.string("720p"), .string("1080p")]
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Whether to generate audio for the video.",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        )
    ]

    // MARK: googleVeo3T2V
    //
    // googleVeo3T2VJSONBuilder / googleVeo3T2VParameterParser
    // View: buildGoogleVeo3T2VParamsView
    // 2 registered ids: google/veo-3.0-fast, google/veo3
    //
    // The two Veo **3.1** t2v ids moved to `googleVeo3T2V31` on 2026-07-28: they publish a `4K`
    // resolution that Veo 3.0 does not, and one shared option list cannot both offer 4K to the models
    // that have it and withhold it from the models that would reject it. The two tables are otherwise
    // identical and emit identical payloads.
    static let googleVeo3T2V: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16")], style: .segmented),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("720P"), .string("1080P")], style: .segmented),
            defaultValue: .string("720P"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("720P")),
            // This table already declared the correct upper-case picker **and** the correct default,
            // and still shipped `"720p"` on every single request — `resolution` is one of the 17
            // `ModelParameters` fields with a non-nil struct default, and `ParamDefaults.merge` only
            // fills fields that are nil, so a table's own default can never displace it. That is the
            // clearest evidence that this guard belongs at the point of emission and nowhere else.
            // Case-only, so it is corrected rather than omitted.
            allowedValues: [.string("720P"), .string("1080P")]
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(4), .int(6), .int(8)], style: .segmented),
            defaultValue: .int(8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(8)),
            // Not case-only and not near — the struct default 5 is simply not a Veo duration. Omitted,
            // so the API applies its documented default of 8, which is also what this picker shows.
            allowedValues: [.int(4), .int(6), .int(8)]
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt (Optional)",
            help: nil,
            control: .text(placeholder: "Elements to avoid"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enhance Prompt",
            help: "Automatically optimize your prompt for better video quality",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Generate audio with the video (Veo 3 feature)",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed",
            help: nil,
            control: .seed(range: 1...Int(Int32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        )
    ]

    // MARK: googleVeo3T2V31
    //
    // 2 registered ids: google/veo-3.1-t2v, google/veo-3.1-t2v-fast
    //
    // Split off `googleVeo3T2V` on 2026-07-28, for one reason: Veo 3.1 publishes a `4K` resolution and
    // Veo 3.0 does not. **Derived from that table rather than copied**, replacing exactly one row, so
    // the claim "these two tables differ only in the resolution row" is enforced by the compiler
    // instead of by a reviewer diffing seven rows. Every other row — including `duration`, the
    // parse fallbacks and the emitted payload — is literally the same value.
    // The native 3.1 schema supports uppercase resolutions but not the fallback-only
    // prompt rewrite/negative-prompt/seed fields. Do not mix those branches.
    static let googleVeo3T2V31: [ParamDescriptor] = googleVeo3T2V.map { row in
        if ["negative_prompt", "enhance_prompt", "seed"].contains(row.wireKey) { return row.historyOnly }
        guard row.wireKey == "resolution" else { return row }
        return ParamDescriptor(
            wireKey: row.wireKey,
            field: row.field,
            label: row.label,
            help: row.help,
            control: .picker(options: [.string("720P"), .string("1080P"), .string("4K")], style: .segmented),
            defaultValue: row.defaultValue,
            visibleWhen: row.visibleWhen,
            alwaysEmit: row.alwaysEmit,
            omitWhenEmpty: row.omitWhenEmpty,
            emitWhen: row.emitWhen,
            parseKey: row.parseKey,
            parseFallback: row.parseFallback,
            emitClamp: row.emitClamp,
            allowedValues: [.string("720P"), .string("1080P"), .string("4K")]
        )
    }

    // MARK: veo2
    //
    // veo2JSONBuilder / veo2ParameterParser
    // View: buildVeo2ParamsView
    // 4 registered ids: google/veo2, google/veo2-image-to-video, veo2, veo2/image-to-video
    static let veo2: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16")], style: .segmented),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("720p"), .string("1080p")], style: .segmented),
            defaultValue: .string("720p"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("720p"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(5), .int(6), .int(7), .int(8)], style: .segmented),
            defaultValue: .int(8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(8)),
            // Veo 2 publishes `[5, 6, 7, 8]`. The picker offered `4`, which it rejects, and withheld
            // `5` and `7`, which it accepts — so this list was wrong in both directions at once.
            allowedValues: [.int(5), .int(6), .int(7), .int(8)]
        ),

        ParamDescriptor.info(
            label: "Input Image Required",
            text: "Provide an input image to animate into a video.",
            visibleWhen: .isImageToVideo
        ),

        ParamDescriptor.info(
            label: "Veo 2",
            text: "Veo 2 generates videos without audio. For audio support, use Veo 3 or later."
        )
    ]

    // MARK: googleVeo31I2VFastVeo30
    //
    // googleVeo31I2VFastJSONBuilder / googleVeo31I2VFastParameterParser
    // View: buildGoogleVeo31I2VFastParamsView
    // 2 registered ids: google/veo-3.0-i2v, google/veo-3.0-i2v-fast
    static let googleVeo31I2VFastVeo30: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: "Choose landscape or portrait. These Veo 3.1 workflows support 16:9 and 9:16.",
            control: .picker(options: [.string("16:9"), .string("9:16")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9")),
            emitClamp: EmitClamp([
                .init(when: .fieldEquals(.resolution, .string("720p")), allowed: [.string("16:9"), .string("9:16"), .string("1:1")], fallback: .string("16:9")),
                .init(allowed: [.string("16:9"), .string("9:16")], fallback: .string("16:9"))
            ]),
            // `1:1` is dropped from the picker: the help text below promises it at 720p and the clamp
            // above lets it through, but **neither of these two ids publishes it** — the enum is
            // `["16:9", "9:16"]` — so choosing it produced a validation failure, not a square video.
            // The clamp is left exactly as recorded; `allowedValues` makes its 720p branch unreachable
            // rather than rewriting frozen behaviour.
            allowedValues: [.string("16:9"), .string("9:16")]
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: "The length of the output video in seconds.",
            control: .picker(options: [.int(8)], style: .menu),
            defaultValue: .int(8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(8)),
            emitClamp: EmitClamp([
                .init(allowed: [.int(4), .int(6), .int(8)], fallback: .int(8))
            ]),
            allowedValues: [.int(4), .int(6), .int(8)]
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: "The resolution of the generated video.",
            control: .picker(options: [.string("720P"), .string("1080P")], style: .menu),
            defaultValue: .string("720P"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("1080P")),
            // Veo 3.0 i2v spells its resolutions in upper case; `"720p"` is a case-only mismatch and is
            // corrected on the way out. No `4K` in this family.
            allowedValues: [.string("720P"), .string("1080P")]
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Whether to generate audio for the video.",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        )
    ]

    // MARK: veoFirstLastFrame
    //
    // veoFirstLastFrameJSONBuilder / veoFirstLastFrameParameterParser
    // View: buildVeoFirstLastFrameParamsView
    // 2 registered ids: google/veo-3.1-first-last-image-to-video, google/veo-3.1-first-last-image-to-video-fast
    //
    // `veo-3.1-lite-generate-001` (both spellings) moved to `veoLiteGenerate` on 2026-07-28 — same
    // reason as the `googleVeo3T2V` split: the two first/last-frame ids publish `4K` and the lite model
    // does not.
    static let veoFirstLastFrame: [ParamDescriptor] = [
        ParamDescriptor.info(
            label: "Two Images Required",
            text: "This model requires exactly 2 input images:\n\n• First image = Start frame\n• Second image = End frame\n\nThe video will interpolate between these two frames."
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16")], style: .segmented),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: "Images should be at least 720p resolution",
            control: .picker(options: [.string("720P"), .string("1080P"), .string("4K")], style: .segmented),
            defaultValue: .string("720P"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("1080P")),
            // Upper case, so `"720p"` is corrected rather than dropped. `4K` is added: both ids publish
            // it and the picker was withholding it.
            allowedValues: [.string("720P"), .string("1080P"), .string("4K")]
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(4), .int(6), .int(8)], style: .segmented),
            defaultValue: .int(8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(8)),
            allowedValues: [.int(4), .int(6), .int(8)]
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Generate audio with the video (Veo 3.1 feature)",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        )
    ]

    // MARK: veoLiteGenerate
    //
    // 2 registered ids: google/veo-3.1-lite-generate-001, veo-3.1-lite-generate-001
    //
    // Split off `veoFirstLastFrame` on 2026-07-28. Derived from it, replacing exactly the resolution
    // row, so the only difference between the two tables is the one the schemas actually have: no `4K`.
    // The "Two Images Required" panel comes along unchanged, as it did before the split.
    static let veoLiteGenerate: [ParamDescriptor] = veoFirstLastFrame.map { row in
        guard row.wireKey == "resolution" else { return row }
        return ParamDescriptor(
            wireKey: row.wireKey,
            field: row.field,
            label: row.label,
            help: row.help,
            control: .picker(options: [.string("720P"), .string("1080P")], style: .segmented),
            defaultValue: row.defaultValue,
            visibleWhen: row.visibleWhen,
            alwaysEmit: row.alwaysEmit,
            omitWhenEmpty: row.omitWhenEmpty,
            emitWhen: row.emitWhen,
            parseKey: row.parseKey,
            parseFallback: row.parseFallback,
            emitClamp: row.emitClamp,
            allowedValues: [.string("720P"), .string("1080P")]
        )
    }

}
