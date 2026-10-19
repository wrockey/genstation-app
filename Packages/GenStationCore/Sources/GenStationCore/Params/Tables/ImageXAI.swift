// Descriptor tables — XAI image models (Stage 2, Task 10).
//
// GENERATED from the legacy triple, not transcribed: wire keys, conditionality, `alwaysEmit`, the
// emit clamps and the emit guards come from each `JSONBuilder`; controls, option lists, labels and
// help text from each `build*ParamsView`; `parseFallback` from each `ParameterParser`; and
// `defaultValue` is the effective default the app produces today — the `ModelParameters` struct
// default where it is non-nil, else the parser's (design § 5). `PayloadEquivalenceTests` proves each
// table emits what its builder emits, over five probes and both modes.
//
// Behaviour is frozen, drift included. Where a view hides a control the builder emits anyway, the
// row stays — the divergence is in the drift ledger, not silently corrected here.

import Foundation

extension ParamCatalog {

    // MARK: grokImagine
    //
    // grokImagineJSONBuilder / grokImagineParameterParser
    // View: buildGrokImagineParamsView
    // 2 registered ids: x-ai/grok-imagine-image, x-ai/grok-imagine-image-pro
    static let grokImagine: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("1:1"), .string("3:4"), .string("4:3"), .string("9:16"), .string("16:9"), .string("2:3"), .string("3:2"), .string("auto")], style: .menu),
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
            control: .picker(options: [.string("1k"), .string("2k")], style: .segmented),
            defaultValue: .string("2k"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("2k")),
            // Grok sizes images as `1k`/`2k`, so the shared video-shaped struct default `"720p"` has
            // no counterpart here and is omitted. Both ids publish the same pair.
            allowedValues: [.string("1k"), .string("2k")]
        ),

        ParamDescriptor(
            wireKey: "n",
            field: .numImages,
            label: "Number of Images",
            help: nil,
            control: .picker(options: [.int(1), .int(2), .int(3), .int(4), .int(5), .int(6), .int(7), .int(8), .int(9), .int(10)], style: .menu),
            defaultValue: .int(1),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(1))
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

}
