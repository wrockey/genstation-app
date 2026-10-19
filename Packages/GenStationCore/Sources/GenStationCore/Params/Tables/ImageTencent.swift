// Descriptor tables — Tencent image models (Stage 2, Task 10).
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

    // MARK: hunyuanImageV3
    //
    // hunyuanImageV3JSONBuilder / hunyuanImageV3ParameterParser
    // View: buildHunyuanImageV3ParamsView
    // 2 registered ids: hunyuan-image/v3/text-to-image, hunyuan/hunyuan-image-v3-text-to-image
    static let hunyuanImageV3: [ParamDescriptor] = [
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
            wireKey: "num_inference_steps",
            field: .numInferenceSteps,
            label: "Num Inference Steps",
            help: "The number of inference steps to perform",
            control: .slider(range: 1...50, step: 1),
            defaultValue: .int(28),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(28))
        ),

        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "How closely the model follows the prompt",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(7.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(7.5))
        ),

        ParamDescriptor(
            wireKey: "enable_prompt_expansion",
            field: .enhancePrompt,
            label: "Enable Prompt Expansion",
            help: nil,
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
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

}
