// Descriptor tables — Alibaba video models (Stage 2, Task 8).
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

    // MARK: alibabaWan21T2VPlus
    //
    // alibabaWan21T2VPlusJSONBuilder / alibabaWan21T2VPlusParameterParser
    // View: buildAlibabaWan21T2VPlusParamsView
    // 1 registered id: alibaba/wan2.1-t2v-plus
    //
    // `alibaba/wan2.2-t2v-plus` (both spellings) moved to `alibabaWan22T2VPlus` on 2026-07-28. The two
    // schemas are identical key for key and differ in exactly one place — `resolution` is `["720P"]`
    // for 2.1 and `["480P", "1080P"]` for 2.2, two **disjoint** sets. There is no option list and no
    // allowed set that can serve both, so this is a table split rather than a value edit.
    static let alibabaWan21T2VPlus: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("720P")], style: .menu),
            defaultValue: .string("720P"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("720P")),
            // The picker and the default were already right; the struct default `"720p"` was what
            // shipped. Case-only, so it is corrected to the one resolution this model publishes.
            allowedValues: [.string("720P")]
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("1:1"), .string("4:3"), .string("3:4")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: "Elements to avoid in the generated video",
            control: .text(placeholder: "Enter negative prompt"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .value(.string(""))
        ),

        ParamDescriptor(
            wireKey: "watermark",
            field: .watermark,
            label: "Watermark",
            help: nil,
            control: .toggle,
            defaultValue: .bool(false),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(false))
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed",
            help: nil,
            control: .seed(range: 0...Int(UInt32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enable Prompt Expansion",
            help: nil,
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        )
    ]

    // MARK: alibabaWan21T2VTurbo
    //
    // alibabaWan21T2VTurboJSONBuilder / alibabaWan21T2VTurboParameterParser
    // View: buildAlibabaWan21T2VTurboParamsView
    // 1 registered id: alibaba/wan2.1-t2v-turbo
    static let alibabaWan21T2VTurbo: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("720P"), .string("480P")], style: .menu),
            defaultValue: .string("720P"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("720P")),
            // Case-only: the struct default `"720p"` becomes the published `"720P"`.
            allowedValues: [.string("480P"), .string("720P")]
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("1:1"), .string("4:3"), .string("3:4")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: "Elements to avoid in the generated video",
            control: .text(placeholder: "Enter negative prompt"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .value(.string(""))
        ),

        ParamDescriptor(
            wireKey: "watermark",
            field: .watermark,
            label: "Watermark",
            help: nil,
            control: .toggle,
            defaultValue: .bool(false),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(false))
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed",
            help: nil,
            control: .seed(range: 0...Int(UInt32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enable Prompt Expansion",
            help: nil,
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        )
    ]

    // MARK: alibabaWan25T2VPreview
    //
    // alibabaWan25T2VPreviewJSONBuilder / alibabaWan25T2VPreviewParameterParser
    // View: buildAlibabaWan25T2VPreviewParamsView
    // 1 registered id: alibaba/wan2.5-t2v-preview
    static let alibabaWan25T2VPreview: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("480p"), .string("720p"), .string("1080p")], style: .menu),
            defaultValue: .string("720p"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("720p"))
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("1:1")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration (seconds)",
            help: nil,
            control: .picker(options: [.int(5), .int(10)], style: .menu),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: "Elements to avoid in the generated video",
            control: .text(placeholder: "Enter negative prompt"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .value(.string(""))
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed",
            help: nil,
            control: .seed(range: 0...Int(UInt32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enable Prompt Expansion",
            help: nil,
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        )
    ]

    // MARK: wan25I2V
    //
    // wan25I2VJSONBuilder / wan25I2VParameterParser
    // View: buildWan25I2VParamsView
    // 1 registered id: alibaba/wan2.5-i2v-preview
    //
    // `alibaba/wan2.2-i2v-plus` (both spellings) moved to `alibabaWan22I2VPlus` on 2026-07-28 — a 2.2
    // model on a 2.5 table, and the two families do not agree: 2.5 publishes `resolution` in lower case
    // with three values, 2.2 publishes two values in **upper** case, and 2.2 documents no `duration` at
    // all (it is on the undocumented-key baseline for exactly that reason). Drift ledger § A.14 already
    // recorded a wire-key problem in this table; this is the value half of it.
    static let wan25I2V: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: "An enumeration where the short side of the video frame determines the resolution.",
            control: .picker(options: [.string("480p"), .string("720p"), .string("1080p")], style: .menu),
            defaultValue: .string("720p"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("720p")),
            // Lower case here, and `720p` really is one of this model's three values — it was never
            // broken for `wan2.5-i2v-preview`, only for the 2.2 ids that were sharing the table.
            allowedValues: [.string("480p"), .string("720p"), .string("1080p")]
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: "The length of the output video in seconds.",
            control: .picker(options: [.int(5), .int(10)], style: .menu),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5)),
            allowedValues: [.int(5), .int(10)]
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: "The description of elements to avoid in the generated video.",
            control: .text(placeholder: "Elements to avoid"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enable Prompt Expansion",
            help: "Whether to enable prompt expansion.",
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
            control: .seed(range: 0...Int(Int32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        )
    ]

    // MARK: wan26Video
    //
    // wan26VideoJSONBuilder / wan26VideoParameterParser
    // View: buildWan26VideoParamsView
    // 6 registered ids: alibaba/happyhorse-1.0-t2v, alibaba/wan-2-6-t2v, alibaba/wan-2-7-t2v, alibaba/wan2.7-t2v, happyhorse-1.0-t2v, wan2.7-t2v
    //
    // unverified: copied from the shared Wan 2.6 view; no API schema exists to check it.
    static let wan26Video: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("1:1"), .string("4:3"), .string("3:4")], style: .menu),
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
            parseFallback: .value(.string("1080p"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(5), .int(10), .int(15)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(10))
        ),

        ParamDescriptor(
            wireKey: "shot_type",
            field: .shotType,
            label: "Shot Type",
            help: "Multi-shot creates cinematic storytelling with multiple camera angles",
            control: .picker(options: [.string("single"), .string("multi")], style: .segmented),
            defaultValue: .string("single"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("single"))
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Wan 2.6 supports native synchronized audio generation",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enhance Prompt",
            help: "Use AI to enhance your prompt for better results",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
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
            wireKey: "seed",
            field: .seed,
            label: "",
            help: nil,
            control: .none,
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor.info(
            label: "Input Image Required",
            text: "Provide an input image to animate into a video.",
            visibleWhen: .isImageToVideo
        ),

        ParamDescriptor.info(
            label: "Wan 2.6",
            text: "Latest Alibaba model with consistent characters, synchronized audio, and cinematic multi-shot storytelling."
        )
    ]

    // MARK: wan26VideoI2V
    //
    // wan26VideoI2VJSONBuilder / wan26VideoI2VParameterParser
    // View: buildWan26VideoParamsView
    // 14 registered ids: alibaba/happyhorse-1.0-i2v, alibaba/happyhorse-1.0-r2v, alibaba/wan-2-6-i2v, alibaba/wan-2-6-r2v, alibaba/wan-2-7-i2v, alibaba/wan-2-7-r2v, alibaba/wan2.6-i2v-flash, alibaba/wan2.7-i2v, alibaba/wan2.7-r2v, happyhorse-1.0-i2v, happyhorse-1.0-r2v, wan2.6-i2v-flash, wan2.7-i2v, wan2.7-r2v
    //
    // unverified: copied from the shared Wan 2.6 view; no API schema exists to check it.
    static let wan26VideoI2V: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("1:1"), .string("4:3"), .string("3:4")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: .isTextToVideo,
            alwaysEmit: false,
            // Not `.leaveUnchanged`: the i2v parser runs the shared t2v one and then explicitly
            // clears this field (`Legacy/Alibaba.swift:173-176`), so a decode that left the struct
            // default "16:9" in place would re-run a past generation with an aspect ratio the
            // payload never carried. Found by `HistoryReRunTests` against the live history file.
            parseFallback: .setNil
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
            parseFallback: .value(.string("1080p"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(5), .int(10), .int(15)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(10))
        ),

        ParamDescriptor(
            wireKey: "shot_type",
            field: .shotType,
            label: "Shot Type",
            help: "Multi-shot creates cinematic storytelling with multiple camera angles",
            control: .picker(options: [.string("single"), .string("multi")], style: .segmented),
            defaultValue: .string("single"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("single"))
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Wan 2.6 supports native synchronized audio generation",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enhance Prompt",
            help: "Use AI to enhance your prompt for better results",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
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
            wireKey: "seed",
            field: .seed,
            label: "",
            help: nil,
            control: .none,
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor.info(
            label: "Input Image Required",
            text: "Provide an input image to animate into a video.",
            visibleWhen: .isImageToVideo
        ),

        ParamDescriptor.info(
            label: "Wan 2.6",
            text: "Latest Alibaba model with consistent characters, synchronized audio, and cinematic multi-shot storytelling."
        )
    ]

    // MARK: alibabaWan22T2VPlus
    //
    // 2 registered ids: alibaba/wan2.2-t2v-plus, wan2.2-t2v-plus
    //
    // Split off `alibabaWan21T2VPlus` on 2026-07-28. Derived from it, replacing exactly the resolution
    // row: the two schemas are otherwise identical key for key, and `resolution` is the one place they
    // disagree — `["720P"]` for 2.1 against `["480P", "1080P"]` for 2.2, with no value in common.
    //
    // `defaultValue` moves 720P → 1080P **because 720P is not one of this model's resolutions**, so
    // leaving it would show the user a selection its own picker no longer offers. It is a display value
    // on a row that is not `alwaysEmit`, so it reaches neither the wire nor `ParamDecoder`; the decode
    // side of this table is byte-identical to the one it was split from.
    static let alibabaWan22T2VPlus: [ParamDescriptor] = alibabaWan21T2VPlus.map { row in
        guard row.wireKey == "resolution" else { return row }
        return ParamDescriptor(
            wireKey: row.wireKey,
            field: row.field,
            label: row.label,
            help: row.help,
            control: .picker(options: [.string("480P"), .string("1080P")], style: .menu),
            defaultValue: .string("1080P"),
            visibleWhen: row.visibleWhen,
            alwaysEmit: row.alwaysEmit,
            omitWhenEmpty: row.omitWhenEmpty,
            emitWhen: row.emitWhen,
            parseKey: row.parseKey,
            parseFallback: row.parseFallback,
            emitClamp: row.emitClamp,
            allowedValues: [.string("480P"), .string("1080P")]
        )
    }

    // MARK: alibabaWan22I2VPlus
    //
    // 2 registered ids: alibaba/wan2.2-i2v-plus, wan2.2-i2v-plus
    //
    // Split off `wan25I2V` on 2026-07-28 — a 2.2 model registered against a 2.5 table. Derived from it,
    // replacing two rows:
    //
    //   • `resolution` — 2.2 publishes `["480P", "1080P"]` in upper case; 2.5 publishes three values in
    //     lower case. Disjoint, so the struct default `"720p"` is omitted rather than case-corrected.
    //   • `duration` — 2.2 documents no `duration` at all, so it carries **no** `allowedValues`: an
    //     undocumented key has no enum, and constraining it with a sibling model's would be inventing a
    //     rule the vendor never published. The key still goes on the wire exactly as it did before, and
    //     stays on the undocumented-key baseline where it was already recorded.
    static let alibabaWan22I2VPlus: [ParamDescriptor] = wan25I2V.map { row in
        switch row.wireKey {
        case "resolution":
            return ParamDescriptor(
                wireKey: row.wireKey, field: row.field, label: row.label, help: row.help,
                control: .picker(options: [.string("480P"), .string("1080P")], style: .menu),
                defaultValue: .string("1080P"),
                visibleWhen: row.visibleWhen, alwaysEmit: row.alwaysEmit,
                omitWhenEmpty: row.omitWhenEmpty, emitWhen: row.emitWhen,
                parseKey: row.parseKey, parseFallback: row.parseFallback, emitClamp: row.emitClamp,
                allowedValues: [.string("480P"), .string("1080P")]
            )
        case "duration":
            return ParamDescriptor(
                wireKey: row.wireKey, field: row.field, label: row.label, help: row.help,
                control: row.control, defaultValue: row.defaultValue,
                visibleWhen: row.visibleWhen, alwaysEmit: row.alwaysEmit,
                omitWhenEmpty: row.omitWhenEmpty, emitWhen: row.emitWhen,
                parseKey: row.parseKey, parseFallback: row.parseFallback, emitClamp: row.emitClamp,
                allowedValues: nil
            )
        default:
            return row
        }
    }

}
