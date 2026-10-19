// Descriptor tables — Minimax video models (Stage 2, Task 8).
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

    // MARK: minimaxVideo01
    //
    // minimaxVideo01JSONBuilder / minimaxVideo01ParameterParser
    // View: buildMinimaxVideo01ParamsView
    // 2 registered ids: minimax/video-01, video-01
    static let minimaxVideo01: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enhance Prompt",
            help: "When enabled, automatically optimizes your prompt for better video quality",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor.info(
            label: "First Frame Image (Optional)",
            text: "Add an input image to use as the first frame of your video. If no image is provided, the video will be generated from the text prompt only."
        )
    ]

    // MARK: minimaxHailuo02
    //
    // minimaxHailuo02JSONBuilder / minimaxHailuo02ParameterParser
    // View: buildMinimaxHailuo02ParamsView
    // 1 registered id: minimax/hailuo-02
    static let minimaxHailuo02: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("768P"), .string("1080P")], style: .segmented),
            defaultValue: .string("768P"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("768P")),
            // Hailuo's short side is 768P, not 720P, so the struct default `"720p"` is not a case
            // mismatch — it is a resolution this model does not offer. Omitted, not corrected.
            allowedValues: [.string("768P"), .string("1080P")]
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(6), .int(10)], style: .segmented),
            defaultValue: .int(6),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(6)),
            allowedValues: [.int(6), .int(10)]
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enhance Prompt",
            help: "When enabled, automatically optimizes your prompt for better video quality",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor.info(
            label: "Frame Images (Optional)",
            text: "You can provide a first frame image and/or a last frame image to guide the video generation."
        )
    ]

    // MARK: hailuo23
    //
    // hailuo23JSONBuilder / hailuo23ParameterParser
    // View: buildHailuo23ParamsView
    // 2 registered ids: minimax/hailuo-2.3, minimax/hailuo-2.3-fast
    static let hailuo23: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("768P"), .string("1080P")], style: .segmented),
            defaultValue: .string("768P"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("768P")),
            // Both 2.3 ids publish the same pair; see `minimaxHailuo02` for why `"720p"` is omitted
            // rather than case-corrected.
            allowedValues: [.string("768P"), .string("1080P")]
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(6), .int(10)], style: .segmented),
            defaultValue: .int(6),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(6)),
            allowedValues: [.int(6), .int(10)]
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enhance Prompt",
            help: "Automatically optimize prompt for better quality. Disable for more precise control.",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor.info(
            label: "Input Image (Optional)",
            text: "Provide an image as the first frame. Supports JPG/PNG, aspect ratio 2:5 to 5:2, min 300px, max 20MB."
        ),

        ParamDescriptor.info(
            label: "Hailuo 2.3",
            text: "MiniMax's latest video generation model with improved motion and quality."
        )
    ]

}
