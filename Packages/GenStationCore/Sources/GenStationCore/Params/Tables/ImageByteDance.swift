// Descriptor tables — ByteDance image models (Stage 2, Task 10).
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

    // MARK: seedreamV4
    //
    // seedreamV4JSONBuilder / seedreamV4ParameterParser
    // View: buildSeedreamV4ParamsView
    // 5 registered ids: alibaba/z-image-turbo, bytedance/seedream-v4-text-to-image, bytedance/seedream/v4/text-to-image, z-image-turbo, z-image/turbo
    //
    // unverified: copied from the shared Seedream v4 view; no API schema exists to check it.
    static let seedreamV4: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "square_hd",
                              dimensions: [1024, 1080, 1920, 2048, 4096],
                              widthFallback: 1024,
                              heightFallback: 1024)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed",
            help: nil,
            control: .seed(range: 1...Int.max),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "num_images",
            field: .numImages,
            label: "Number of Images",
            help: nil,
            control: .picker(options: [.int(1), .int(2), .int(3), .int(4)], style: .menu),
            defaultValue: .int(1),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(1))
        ),

        ParamDescriptor(
            wireKey: "enable_safety_checker",
            field: .enableSafetyChecker,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        )
    ]

    // MARK: seedreamV4Edit
    //
    // seedreamV4EditJSONBuilder / seedreamV4EditParameterParser
    // View: buildSeedreamV4EditParamsView
    // 3 registered ids: bytedance/seedream-5-0-lite, bytedance/seedream-v4-edit, bytedance/seedream/v4/edit
    static let seedreamV4Edit: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "square_hd",
                              dimensions: [512, 768, 1024, 1536],
                              widthFallback: 1024,
                              heightFallback: 1024)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed",
            help: nil,
            control: .seed(range: 1...Int.max),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "num_images",
            field: .numImages,
            label: "Number of Images",
            help: nil,
            control: .picker(options: [.int(1), .int(2), .int(3), .int(4)], style: .menu),
            defaultValue: .int(1),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(1))
        ),

        ParamDescriptor(
            wireKey: "enable_safety_checker",
            field: .enableSafetyChecker,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        )
    ]

    // MARK: seedream45
    //
    // seedream45JSONBuilder / seedream45ParameterParser
    // View: buildSeedream45ParamsView
    // 1 registered id: bytedance/seedream-4-5
    static let seedream45: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["2K", "4K"],
                              presetFallback: "2K",
                              dimensions: [1440, 2048, 4096],
                              widthFallback: 2048,
                              heightFallback: 2048,
                              minimumDimension: 1440)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed",
            help: nil,
            control: .seed(range: 1...Int.max),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "watermark",
            field: .watermark,
            label: "Add Watermark",
            help: nil,
            control: .toggle,
            defaultValue: .bool(false),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(false))
        )
    ]

    // MARK: seedream50Pro
    //
    // Introduced 2026-08-11 for Seedream 5.0 Pro. Its published schema shares `seedream45`'s exact
    // key set (`image_size`, `seed`, `watermark`, plus `image_urls`/`response_format` at the body
    // level like every other i2i model here) — but NOT its `image_size` enum. Pro publishes
    // `["1.5K", "2K"]`, default `"1.5K"`, width/height 1024-2752; `seedream45` publishes
    // `["2K", "4K"]`. Before assuming reuse, the brief's own arbiter was checked: seedream-5-0-lite's
    // schema was re-captured live (not read from memory) and it still publishes only `["2K","4K"]`,
    // no `"1.5K"` — so widening `seedream45`'s shared preset list would be wrong for the two ids that
    // already share it (`bytedance/seedream-4-5`, `bytedance/seedream-5-0-lite`). Pro gets its own
    // copy instead, with its own preset list, range and default.
    // 1 registered id: bytedance/seedream-5-0-pro (+ alias bytedance/dola-seedream-5-0-pro)
    static let seedream50Pro: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["1.5K", "2K"],
                              presetFallback: "1.5K",
                              dimensions: [1024, 2048, 2752],
                              widthFallback: 2048,
                              heightFallback: 2048,
                              minimumDimension: 1024,
                              maximumDimension: 2752)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "seed",
            field: .seed,
            label: "Seed",
            help: nil,
            control: .seed(range: 1...Int.max),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "watermark",
            field: .watermark,
            label: "Add Watermark",
            help: nil,
            control: .toggle,
            defaultValue: .bool(false),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(false))
        )
    ]

}
