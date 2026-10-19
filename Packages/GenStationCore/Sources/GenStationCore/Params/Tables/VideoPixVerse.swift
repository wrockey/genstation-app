// Descriptor tables — PixVerse video models (Stage 2, Task 8).
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

    // MARK: pixVerseV55T2V
    //
    // pixVerseV55T2VJSONBuilder / pixVerseV55T2VParameterParser
    // View: buildPixVerseV55T2VParamsView
    // 9 registered ids: pixverse/v5-5-image-to-video, pixverse/v5-5-text-to-video, pixverse/v5.5-image-to-video, pixverse/v5.5-text-to-video, pixverse/v5.5/image-to-video, pixverse/v5.5/text-to-video, pixverse/v5/image-to-video, pixverse/v5/text-to-video, pixverse/v5/transition
    static let pixVerseV55T2V: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("4:3"), .string("3:4"), .string("1:1")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: "Note: 1080p doesn't support 8-second videos",
            control: .picker(options: [.string("360p"), .string("540p"), .string("720p"), .string("1080p")], style: .menu),
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
            control: .picker(options: [.int(5), .int(8), .int(10)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "style",
            field: .stylePreset,
            label: "Style (Optional)",
            help: nil,
            control: .picker(options: [.string(""), .string("anime"), .string("3d_animation"), .string("clay"), .string("comic"), .string("cyberpunk")], style: .menu),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .setNil,
            // The picker's five options are exactly PixVerse's published `style` enum, and all 7 ids
            // agree on it. The value that was breaking generation is `"realistic"` — not offered here,
            // but `stylePreset` is shared across every model in `ModelParameters`, so selecting it on
            // some other model and then switching to PixVerse shipped it. That is precisely the stale
            // cross-model value this guard exists for; the empty sentinel is dropped earlier by
            // `omitWhenEmpty`.
            allowedValues: [.string("3d_animation"), .string("anime"), .string("clay"),
                            .string("comic"), .string("cyberpunk")]
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
            wireKey: "generate_audio_switch",
            field: .generateAudio,
            label: "Generate Audio",
            help: nil,
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(false))
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

}
