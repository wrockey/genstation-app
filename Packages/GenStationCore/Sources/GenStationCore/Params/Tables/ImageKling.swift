// Descriptor tables — Kling image models (Stage 2, Task 10).
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

    // MARK: klingImageO1
    //
    // klingImageO1JSONBuilder / klingImageO1ParameterParser
    // View: buildKlingImageO1ParamsView
    // 1 registered id: klingai/image-o1
    static let klingImageO1: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("21:9"), .string("16:9"), .string("4:3"), .string("3:2"), .string("1:1"), .string("2:3"), .string("3:4"), .string("9:16")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: .notEqualTo(.string("16:9")),
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("1K"), .string("2K")], style: .menu),
            defaultValue: .string("1K"),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: .notEqualTo(.string("1K")),
            parseFallback: .value(.string("1K")),
            // `emitWhen: .notEqualTo("1K")` was the only thing standing between this row and the wire,
            // and the struct default `"720p"` sails straight through it — it is not `"1K"`, so the key
            // was emitted with a value this image model has no concept of. Omitted.
            allowedValues: [.string("1K"), .string("2K")]
        ),

        ParamDescriptor(
            wireKey: "num_images",
            field: .numImages,
            label: "Number of Images",
            help: nil,
            control: .picker(options: [.int(1), .int(2), .int(3), .int(4), .int(5), .int(6), .int(7), .int(8), .int(9)], style: .menu),
            defaultValue: .int(1),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: .atLeast(2),
            parseFallback: .value(.int(1))
        )
    ]

}
