// Descriptor tables — Kandinsky video models (Stage 2, Task 8).
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

    // MARK: kandinskyVideo
    //
    // kandinskyVideoJSONBuilder / kandinskyVideoParameterParser
    // View: buildKandinskyVideoParamsView
    // 2 registered ids: kandinsky5/text-to-video, kandinsky5/text-to-video/distill
    static let kandinskyVideo: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("3:2"), .string("1:1"), .string("2:3")], style: .segmented),
            defaultValue: .string("3:2"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("3:2")),
            // Kandinsky publishes no 16:9 at all — its widest is 3:2 — so the shared struct default
            // `aspectRatio: "16:9"` was rejected on every request. There is no near-equivalent to
            // substitute (3:2 is a different crop), so the key is omitted and the API's `3:2` default
            // applies, which is also what this table's own picker shows.
            allowedValues: [.string("1:1"), .string("2:3"), .string("3:2")]
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration (seconds)",
            help: nil,
            control: .picker(options: [.int(5), .int(10)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5)),
            allowedValues: [.int(5), .int(10)]
        ),

        ParamDescriptor(
            wireKey: "num_inference_steps",
            field: .numInferenceSteps,
            label: "Inference Steps",
            help: nil,
            control: .slider(range: 1...50, step: 1),
            defaultValue: .int(30),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(30))
        )
    ]

}
