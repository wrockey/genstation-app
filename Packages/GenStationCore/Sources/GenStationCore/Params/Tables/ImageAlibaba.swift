// Descriptor tables — Alibaba image models (Stage 2, Task 10).
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

    // MARK: alibabaQwenImageEdit
    //
    // alibabaQwenImageEditJSONBuilder / alibabaQwenImageEditParameterParser
    // View: buildAlibabaQwenImageEditParamsView
    // 1 registered id: alibaba/qwen-image-edit
    static let alibabaQwenImageEdit: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: "Elements to avoid in the generated video",
            control: .text(placeholder: "Enter negative prompt"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .value(.string(""))
        ),

        ParamDescriptor(
            wireKey: "watermark",
            field: .watermark,
            label: "Watermark",
            help: nil,
            control: .toggle,
            defaultValue: .bool(false),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(false))
        )
    ]

    // MARK: alibabaQwenImage
    //
    // alibabaQwenImageJSONBuilder / alibabaQwenImageParameterParser
    // View: buildAlibabaQwenImageParamsView
    // 1 registered id: alibaba/qwen-image
    static let alibabaQwenImage: [ParamDescriptor] = [
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
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "How closely the model follows the prompt",
            control: .slider(range: 1...20, step: 1),
            defaultValue: .double(7.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(7.5))
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: "Elements to avoid in the generated image",
            control: .text(placeholder: "Enter negative prompt"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .value(.string(""))
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

    // MARK: wanImage
    //
    // wanImageJSONBuilder / wanImageParameterParser
    // View: buildWanImageParamsView
    // 6 registered ids: alibaba/wan2.2-t2i-flash, alibaba/wan2.2-t2i-plus, alibaba/wan2.5-t2i-preview, wan2.2-t2i-flash, wan2.2-t2i-plus, wan2.5-t2i-preview
    static let wanImage: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "landscape_4_3",
                              dimensions: [512, 768, 1024, 1280, 1440],
                              widthFallback: 1024,
                              heightFallback: 1024)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
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
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: nil,
            control: .text(placeholder: "Optional"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .value(.string(""))
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enhance Prompt",
            help: "Let the model expand/rewrite the prompt.",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "watermark",
            field: .watermark,
            label: "Watermark",
            help: "Add a provider watermark to the output.",
            control: .toggle,
            defaultValue: .bool(false),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(false))
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

    // MARK: wanImageEdit
    //
    // wanImageEditJSONBuilder / wanImageParameterParser
    // View: buildWanImageParamsView
    // 8 registered ids: alibaba/qwen-image-2.0, alibaba/wan2.6-image, alibaba/wan2.7-image, alibaba/wan2.7-image-pro, qwen-image-2.0, wan2.6-image, wan2.7-image, wan2.7-image-pro
    static let wanImageEdit: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "landscape_4_3",
                              dimensions: [512, 768, 1024, 1280, 1440],
                              widthFallback: 1024,
                              heightFallback: 1024)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "",
            field: .numImages,
            label: "Number of Images",
            help: nil,
            control: .picker(options: [.int(1), .int(2), .int(3), .int(4)], style: .menu),
            defaultValue: nil,
            visibleWhen: .isTextToVideo,
            alwaysEmit: false,
            // Emit-never, parse-`num_images`: the edit builder removes the key the shared Wan image
            // builder wrote (`Legacy/Alibaba.swift:202-206`), but the parser it shares with its t2i
            // sibling still reads it (`:193`). One key for both directions would either put the key
            // back on the wire or drop the field on history re-run. Found by `HistoryReRunTests`.
            parseKey: "num_images",
            parseFallback: .value(.int(1))
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: nil,
            control: .text(placeholder: "Optional"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .value(.string(""))
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enhance Prompt",
            help: "Let the model expand/rewrite the prompt.",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "watermark",
            field: .watermark,
            label: "Watermark",
            help: "Add a provider watermark to the output.",
            control: .toggle,
            defaultValue: .bool(false),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(false))
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
