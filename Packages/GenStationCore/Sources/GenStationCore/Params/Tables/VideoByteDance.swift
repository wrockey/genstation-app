// Descriptor tables — ByteDance video models (Stage 2, Task 8).
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

    // MARK: omniHuman
    //
    // omniHumanJSONBuilder / omniHumanParameterParser
    // View: buildOmniHumanParamsView
    // 2 registered ids: bytedance/omnihuman, bytedance/omnihuman/v1.5
    static let omniHuman: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "audio_url",
            field: .audioURL,
            label: "Audio URL",
            help: "Direct link to an audio file for lip-sync animation. Must be under 30 seconds. Supports MP3, WAV, etc.",
            control: .text(placeholder: "https://example.com/audio.mp3"),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .setNil
        ),

        ParamDescriptor.info(
            label: "Reference Image (Required)",
            text: "Add an input image of a person. OmniHuman will animate them with lip-sync and natural gestures matching the audio."
        ),

        ParamDescriptor.info(
            label: "Note",
            text: "The prompt field is ignored by OmniHuman — generation is driven entirely by the image and audio inputs."
        )
    ]

    // MARK: seedanceVideo
    //
    // seedanceVideoJSONBuilder / seedanceVideoParameterParser
    // View: buildSeedanceVideoParamsView
    // 2 registered ids: bytedance/seedance-1-0-pro-fast, bytedance/seedance-1-5-pro
    static let seedanceVideo: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("480p"), .string("720p"), .string("1080p")], style: .segmented),
            defaultValue: .string("720p"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("1080p"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration (seconds)",
            help: nil,
            control: .picker(options: [.int(4), .int(5), .int(8), .int(10), .int(12)], style: .menu),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("4:3"), .string("1:1"), .string("3:4"), .string("9:16"), .string("21:9")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
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

    // MARK: seedance10Pro
    //
    // seedance10ProJSONBuilder / seedance10ProParameterParser
    // View: buildSeedance10ProParamsView
    // 1 registered id: bytedance/seedance-1-0-pro
    static let seedance10Pro: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("480p"), .string("720p"), .string("1080p")], style: .segmented),
            defaultValue: .string("720p"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("1080p"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration (seconds)",
            help: nil,
            control: .picker(options: [.int(5), .int(10)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.int(5)),
            emitClamp: EmitClamp([
                .init(allowed: [.int(5), .int(10)], fallback: .int(5))
            ])
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("4:3"), .string("1:1"), .string("3:4"), .string("9:16"), .string("21:9")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
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

    // MARK: seedance20
    //
    // seedance20JSONBuilder / seedance20ParameterParser
    // View: buildSeedance20ParamsView
    // 2 registered ids: bytedance/seedance-2-0, bytedance/seedance-2-0-fast
    static let seedance20: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("480p"), .string("720p"), .string("1080p"), .string("4k")], style: .segmented),
            defaultValue: .string("720p"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("720p"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration (seconds)",
            help: nil,
            control: .picker(options: [.int(4), .int(5), .int(6), .int(7), .int(8), .int(9), .int(10), .int(11), .int(12), .int(13), .int(14), .int(15)], style: .menu),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: "Frame images determine the aspect ratio when supplied.",
            control: .picker(options: [.string("16:9"), .string("4:3"), .string("1:1"), .string("3:4"), .string("9:16"), .string("21:9")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: .hasNoInputImages,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Whether to generate synchronized audio for the video (default on).",
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
            control: .seed(range: 1...Int(UInt32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        )
    ]

}
