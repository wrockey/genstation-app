// Descriptor tables — StabilityAI image models (Stage 2, Task 10).
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

    // MARK: stableDiffusionV35Large
    //
    // stableDiffusionV35LargeJSONBuilder / stableDiffusionV35LargeParameterParser
    // View: buildStableDiffusionV35LargeParamsView
    // 1 registered id: stable-diffusion-v35-large
    static let stableDiffusionV35Large: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: "The size of the generated image.",
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "square_hd",
                              dimensions: [768, 1024, 1280, 1536],
                              widthFallback: 1024,
                              heightFallback: 1024)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: "The description of elements to avoid in the generated image.",
            control: .text(placeholder: "Elements to avoid"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "The CFG (Classifier Free Guidance) scale is a measure of how close you want the model to stick to your prompt when looking for a related image to show you.",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(4.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(4.5))
        ),

        ParamDescriptor(
            wireKey: "num_inference_steps",
            field: .numInferenceSteps,
            label: "Num Inference Steps",
            help: "The number of inference steps to perform.",
            control: .slider(range: 1...50, step: 1),
            defaultValue: .int(40),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(40))
        ),

        ParamDescriptor(
            wireKey: "num_images",
            field: .numImages,
            label: "Number of Images",
            help: "The number of images to generate.",
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
            control: .seed(range: 1...Int(Int32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
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

    // MARK: stableDiffusionV3Medium
    //
    // stableDiffusionV3MediumJSONBuilder / stableDiffusionV3MediumParameterParser
    // View: buildStableDiffusionV3MediumParamsView
    // 1 registered id: stable-diffusion-v3-medium
    static let stableDiffusionV3Medium: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: "The size of the generated image.",
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "square_hd",
                              dimensions: [768, 1024, 1280, 1536],
                              widthFallback: 1024,
                              heightFallback: 1024)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: "The description of elements to avoid in the generated image.",
            control: .text(placeholder: "Elements to avoid"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "The CFG (Classifier Free Guidance) scale is a measure of how close you want the model to stick to your prompt when looking for a related image to show you.",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(5.0),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(5.0))
        ),

        ParamDescriptor(
            wireKey: "num_inference_steps",
            field: .numInferenceSteps,
            label: "Num Inference Steps",
            help: "The number of inference steps to perform.",
            control: .slider(range: 1...50, step: 1),
            defaultValue: .int(28),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(28))
        ),

        ParamDescriptor(
            wireKey: "num_images",
            field: .numImages,
            label: "Number of Images",
            help: "The number of images to generate.",
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
            control: .seed(range: 1...Int(Int32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
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
