// Descriptor tables — Luma video models (Stage 2, Task 8).
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

    // MARK: lumaRay2
    //
    // lumaRay2JSONBuilder / lumaRay2ParameterParser
    // View: buildLumaRay2ParamsView
    // 2 registered ids: luma/ray-2, luma/ray-flash-2
    static let lumaRay2: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("540p"), .string("720p"), .string("1080p"), .string("4k")], style: .menu),
            defaultValue: .string("720p"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("1080p"))
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("1:1"), .string("4:3"), .string("3:4"), .string("21:9"), .string("9:21")], style: .menu),
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
            control: .picker(options: [.int(5), .int(9)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "loop",
            field: .loop,
            label: "Loop Video",
            help: "Create a seamlessly looping video",
            control: .toggle,
            defaultValue: .bool(false),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(false))
        )
    ]

}
