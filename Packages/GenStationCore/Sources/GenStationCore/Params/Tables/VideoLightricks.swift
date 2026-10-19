// Descriptor tables — Lightricks video models (Stage 2, Task 8).
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

    // MARK: ltxv2
    //
    // ltxv2JSONBuilder / ltxv2ParameterParser
    // View: buildLTXV2ParamsView
    // 9 registered ids: ltxv-2, ltxv-2-fast, ltxv-2/fast, ltxv-2/image-to-video, ltxv-2/image-to-video/fast, ltxv-2/text-to-video, ltxv-2/text-to-video/fast, ltxv/ltxv-2, ltxv/ltxv-2-fast
    static let ltxv2: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("1080p"), .string("1440p"), .string("2160p")], style: .menu),
            defaultValue: .string("1080p"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("1080p")),
            // The struct default `resolution: "720p"` is not in this family's vocabulary at all — LTXV-2
            // starts at 1080p — so it is omitted and the API's own default applies. All 8 ids agree.
            allowedValues: [.string("1080p"), .string("1440p"), .string("2160p")]
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(6), .int(8), .int(10)], style: .segmented),
            defaultValue: .int(6),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(6)),
            allowedValues: [.int(6), .int(8), .int(10)]
        ),

        ParamDescriptor(
            wireKey: "fps",
            field: .frameRate,
            label: "Frame Rate",
            help: nil,
            control: .picker(options: [.int(25), .int(50)], style: .segmented),
            defaultValue: .int(25),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(25)),
            // `frameRate` is one of the 17 non-nil struct defaults, at 30 — a value no LTXV-2 model
            // accepts. Same shape as `resolution`: the table's own default was already right and could
            // never apply.
            allowedValues: [.int(25), .int(50)]
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Enable audio generation with the video",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: nil,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor.info(
            label: "First Frame Image (Optional)",
            text: "Add an input image to use as the first frame. If no image is provided, the video will be generated from the text prompt only."
        )
    ]

}
