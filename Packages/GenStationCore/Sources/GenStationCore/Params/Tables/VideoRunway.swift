// Descriptor tables — Runway video models (Stage 2, Task 8).
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

    // MARK: runwayGen3Turbo
    //
    // runwayGen3TurboJSONBuilder / runwayGen3TurboParameterParser
    // View: buildRunwayGen3TurboParamsView
    // 2 registered ids: gen3a_turbo, runway/gen3a_turbo
    static let runwayGen3Turbo: [ParamDescriptor] = [
        ParamDescriptor.info(
            label: "Input Image Required",
            text: "Provide an input image to use as the first frame of the video."
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
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(5), .int(10)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed",
            help: "Range: 0 to 4,294,967,295",
            control: .seed(range: 0...Int(UInt32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor.info(
            label: "Tail Image (Optional)",
            text: "Add a second input image to use as the last frame of the video."
        )
    ]

    // MARK: runwayGen4
    //
    // runwayGen4JSONBuilder / runwayGen4ParameterParser
    // View: buildRunwayGen4ParamsView
    // 1 registered id: runway/gen4_turbo
    static let runwayGen4: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("4:3"), .string("3:4"), .string("1:1"), .string("21:9")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(5), .int(10)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed (Optional)",
            help: "Use a seed to get reproducible results",
            control: .seed(range: 0...Int(UInt32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor.info(
            label: "Input Images",
            text: "• First image = Start frame (required)\n• Second image = End frame (optional)"
        ),

        ParamDescriptor.info(
            label: "Runway Gen-4",
            text: "Faster, higher quality video generation with realistic motion and coherent subjects across frames."
        )
    ]

    // MARK: runwayGen4Aleph
    //
    // runwayGen4JSONBuilder / runwayGen4ParameterParser
    // View: buildRunwayGen4AlephParamsView
    // 1 registered id: runway/gen4_aleph
    static let runwayGen4Aleph: [ParamDescriptor] = [
        ParamDescriptor.info(
            label: "Video Input Required",
            text: "Gen4 Aleph is a video-to-video model. It requires a video URL as input, not images.\n\nUse Custom Payload to provide video_url parameter."
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(5)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5)),
            // `10` is not a duration this model publishes — it accepts `5` and nothing else.
            allowedValues: [.int(5)]
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed (Optional)",
            help: nil,
            control: .seed(range: 0...Int(UInt32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor.info(
            label: "Runway Gen4 Aleph",
            text: "Video-to-video model capable of modifying input video or generating the next shot in a story."
        )
    ]

}
