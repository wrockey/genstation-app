// Descriptor tables — OpenAI video models (Stage 2, Task 8).
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

    // MARK: sora2ProI2V
    //
    // sora2ProI2VJSONBuilder / sora2ProI2VParameterParser
    // View: buildSora2ProI2VParamsView
    // 4 registered ids: openai/sora-2-pro-i2v, openai/sora-2-pro-t2v, sora-2-pro-i2v, sora-2-pro-t2v
    static let sora2ProI2V: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16")], style: .menu),
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
            label: "Duration (seconds)",
            help: nil,
            control: .picker(options: [.int(4), .int(8), .int(12)], style: .menu),
            defaultValue: .int(8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(8)),
            // Sora's durations are 4/8/12; the shared struct default `duration: 5` is none of them, so
            // every request shipped a rejected value. Omitted — the API's documented default is 4.
            allowedValues: [.int(4), .int(8), .int(12)]
        ),

        ParamDescriptor.info(
            label: "Notes",
            text: "• Includes synced audio\n• Input image must be exactly 1280x720 or 1792x1024"
        )
    ]

    // MARK: sora2
    //
    // sora2JSONBuilder / sora2ParameterParser
    // View: buildSora2ParamsView
    // 4 registered ids: openai/sora-2-i2v, openai/sora-2-t2v, sora-2-i2v, sora-2-t2v
    static let sora2: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9")),
            emitClamp: EmitClamp([
                .init(allowed: [.string("16:9"), .string("9:16")], fallback: .string("16:9"))
            ])
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration (seconds)",
            help: nil,
            control: .picker(options: [.int(4), .int(8), .int(12)], style: .menu),
            defaultValue: .int(8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(8)),
            // Same as `sora2ProI2V`: the struct default 5 is not one of Sora's 4/8/12.
            allowedValues: [.int(4), .int(8), .int(12)]
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .string("720p"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged,
            emitClamp: EmitClamp([
                .init(allowed: [.string("720p")], fallback: .string("720p"))
            ])
        ),

        ParamDescriptor.info(
            label: "Notes",
            text: "• 720p output (1080p requires Sora 2 Pro)\n• Includes synced audio"
        )
    ]

}
