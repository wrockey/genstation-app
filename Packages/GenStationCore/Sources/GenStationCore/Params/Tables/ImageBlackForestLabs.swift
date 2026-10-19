// Descriptor tables — BlackForestLabs image models (Stage 2, Task 10).
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

    // MARK: fluxRealism
    //
    // fluxRealismJSONBuilder / fluxRealismParameterParser
    // View: buildFluxRealismParamsView
    // 1 registered id: flux-realism
    static let fluxRealism: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "landscape_4_3",
                              dimensions: [512, 768, 1024, 1536],
                              widthFallback: 1024,
                              heightFallback: 768)),
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
            defaultValue: .int(50),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(50))
        ),

        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "How closely the model follows the prompt",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(4.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(4.5))
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
            control: .seed(range: 1...Int(UInt32.max)),
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

    // MARK: fluxSrpo
    //
    // fluxSrpoJSONBuilder / fluxSrpoParameterParser
    // View: buildFluxSrpoParamsView
    // 1 registered id: flux/srpo
    static let fluxSrpo: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "landscape_4_3",
                              dimensions: [512, 768, 1024, 1536],
                              widthFallback: 1024,
                              heightFallback: 768)),
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
            defaultValue: .double(4.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(4.5))
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
            control: .seed(range: 1...Int(UInt32.max)),
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

    // MARK: fluxKontextProI2i
    //
    // fluxKontextProI2iJSONBuilder / fluxKontextProI2iParameterParser
    // View: buildFluxKontextProI2iParamsView
    // 1 registered id: flux/kontext-pro/image-to-image
    static let fluxKontextProI2i: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "The CFG (Classifier Free Guidance) scale is a measure of how close you want the model to stick to your prompt when looking for a related image to show you.",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(7.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("21:9"), .string("16:9"), .string("4:3"), .string("3:2"), .string("1:1"), .string("2:3"), .string("3:4"), .string("9:16"), .string("9:21")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
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
            wireKey: "safety_tolerance",
            field: .safetyTolerance,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .string("2"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("2"))
        )
    ]

    // MARK: flux2Pro
    //
    // flux2ProJSONBuilder / flux2ProParameterParser
    // View: buildFlux2ProParamsView
    // 5 registered ids: blackforestlabs/flux-2-pro, blackforestlabs/flux-pro-1.1, flux-2, flux-2-max, flux-pro/v1.1
    static let flux2Pro: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: "Each side is rounded up to a multiple of 32. If either side ends up above 2048, no size is sent at all and the model uses its own default.",
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "landscape_4_3",
                              dimensions: [512, 768, 1024, 1536, 2048],
                              widthFallback: 1024,
                              heightFallback: 1024,
                              roundUpToMultipleOf: 32,
                              maximumDimension: 2048)),
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
            emitWhen: .atLeast(1),
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
        ),

        ParamDescriptor(
            wireKey: "safety_tolerance",
            field: .safetyTolerance,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .string("2"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("2"))
        )
    ]

    // MARK: flux2ProEdit
    //
    // flux2ProEditJSONBuilder / flux2ProEditParameterParser
    // View: buildFlux2ProEditParamsView
    // 4 registered ids: blackforestlabs/flux-2-max-edit, blackforestlabs/flux-2-pro-edit, flux-2-max/edit, flux-2/edit
    static let flux2ProEdit: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: "Each side is rounded up to a multiple of 32. If either side ends up above 2048, no size is sent at all and the model uses its own default.",
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "landscape_4_3",
                              dimensions: [512, 768, 1024, 1536, 2048],
                              widthFallback: 1024,
                              heightFallback: 1024,
                              roundUpToMultipleOf: 32,
                              maximumDimension: 2048)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: nil,
            control: .slider(range: 7.5...20, step: 0.5),
            defaultValue: .double(19.0),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(3.5))
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
            emitWhen: .atLeast(1),
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "safety_tolerance",
            field: .safetyTolerance,
            label: "Safety Tolerance",
            help: nil,
            control: .picker(options: [.string("1"), .string("2"), .string("3"), .string("4"), .string("5")], style: .menu),
            defaultValue: .string("2"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("2"))
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

    // MARK: fluxPro
    //
    // fluxProJSONBuilder / fluxProParameterParser
    // View: buildFluxProParamsView
    // 1 registered id: flux-pro
    static let fluxPro: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "landscape_4_3",
                              dimensions: [256, 512, 768, 1024, 1280, 1440],
                              widthFallback: 1024,
                              heightFallback: 768)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "num_inference_steps",
            field: .numInferenceSteps,
            label: "Inference Steps",
            help: "Number of denoising steps (1-50)",
            control: .slider(range: 1...50, step: 1),
            defaultValue: .int(50),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(50))
        ),

        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "How closely the model follows the prompt (1-20)",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(3.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(3.5))
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
            control: .seed(range: 1...Int(UInt32.max)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "safety_tolerance",
            field: .safetyTolerance,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .string("2"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("2"))
        )
    ]

    // MARK: fluxDev
    //
    // fluxDevJSONBuilder / fluxDevParameterParser
    // View: buildFluxDevParamsView
    // 1 registered id: flux/dev
    static let fluxDev: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "landscape_4_3",
                              dimensions: [512, 768, 1024, 1280, 1536],
                              widthFallback: 1024,
                              heightFallback: 768)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "num_inference_steps",
            field: .numInferenceSteps,
            label: "Inference Steps",
            help: "Number of denoising steps (1-50)",
            control: .slider(range: 1...50, step: 1),
            defaultValue: .int(50),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(50))
        ),

        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "How closely the model follows the prompt (1-20)",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(3.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(3.5))
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
            control: .seed(range: 1...Int(UInt32.max)),
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

    // MARK: fluxKontextProT2i
    //
    // fluxKontextProT2iJSONBuilder / fluxKontextProT2iParameterParser
    // View: buildFluxKontextProT2iParamsView
    // 1 registered id: flux/kontext-pro/text-to-image
    static let fluxKontextProT2i: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "The CFG (Classifier Free Guidance) scale is a measure of how close you want the model to stick to your prompt when looking for a related image to show you.",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(7.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("21:9"), .string("16:9"), .string("4:3"), .string("3:2"), .string("1:1"), .string("2:3"), .string("3:4"), .string("9:16"), .string("9:21")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
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
            wireKey: "safety_tolerance",
            field: .safetyTolerance,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .string("2"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("2"))
        )
    ]

    // MARK: fluxKontextMaxT2i
    //
    // fluxKontextMaxT2iJSONBuilder / fluxKontextMaxT2iParameterParser
    // View: buildFluxKontextMaxT2iParamsView
    // 1 registered id: flux/kontext-max/text-to-image
    static let fluxKontextMaxT2i: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "The CFG (Classifier Free Guidance) scale is a measure of how close you want the model to stick to your prompt when looking for a related image to show you.",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(7.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("21:9"), .string("16:9"), .string("4:3"), .string("3:2"), .string("1:1"), .string("2:3"), .string("3:4"), .string("9:16"), .string("9:21")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("1:1"))
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
            wireKey: "safety_tolerance",
            field: .safetyTolerance,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .string("2"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("2"))
        )
    ]

    // MARK: fluxKontextMaxI2i
    //
    // fluxKontextMaxI2iJSONBuilder / fluxKontextMaxI2iParameterParser
    // View: buildFluxKontextMaxI2iParamsView
    // 1 registered id: flux/kontext-max/image-to-image
    static let fluxKontextMaxI2i: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "The CFG (Classifier Free Guidance) scale is a measure of how close you want the model to stick to your prompt when looking for a related image to show you.",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(7.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("21:9"), .string("16:9"), .string("4:3"), .string("3:2"), .string("1:1"), .string("2:3"), .string("3:4"), .string("9:16"), .string("9:21")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
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
            wireKey: "safety_tolerance",
            field: .safetyTolerance,
            label: "",
            help: nil,
            control: .none,
            defaultValue: .string("2"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("2"))
        )
    ]

    // MARK: fluxSchnell
    //
    // fluxSchnellJSONBuilder / fluxSchnellParameterParser
    // View: buildFluxSchnellParamsView
    // 1 registered id: flux/schnell
    static let fluxSchnell: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: "Values must be multiples of 32",
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "landscape_4_3",
                              dimensions: [64, 256, 512, 768, 1024, 1280, 1536],
                              widthFallback: 1024,
                              heightFallback: 768)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "num_inference_steps",
            field: .numInferenceSteps,
            label: "Inference Steps",
            help: "Number of denoising steps (Schnell uses fewer steps)",
            control: .slider(range: 1...10, step: 1),
            defaultValue: .int(4),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(4))
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
            control: .seed(range: 1...Int(UInt32.max)),
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
        ),

        ParamDescriptor.info(
            label: "Fast Generation",
            text: "Schnell is optimized for speed with fewer inference steps"
        )
    ]

    // MARK: fluxSrpoI2i
    //
    // fluxSrpoI2iJSONBuilder / fluxSrpoI2iParameterParser
    // View: buildFluxSrpoI2iParamsView
    // 1 registered id: flux/dev/image-to-image
    static let fluxSrpoI2i: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: nil,
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "landscape_4_3",
                              dimensions: [512, 768, 1024, 1536],
                              widthFallback: 1024,
                              heightFallback: 768)),
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
            defaultValue: .int(40),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(40))
        ),

        ParamDescriptor(
            wireKey: "guidance_scale",
            field: .guidanceScale,
            label: "Guidance Scale",
            help: "How closely the model follows the prompt",
            control: .slider(range: 1...20, step: 0.5),
            defaultValue: .double(4.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(4.5))
        ),

        ParamDescriptor(
            wireKey: "strength",
            field: .strength,
            label: "Strength",
            help: "Determines how much the prompt influences the generated image.",
            control: .slider(range: 0...1, step: 0.05),
            defaultValue: .double(0.8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.95))
        ),

        ParamDescriptor(
            wireKey: "acceleration",
            field: .acceleration,
            label: "Acceleration",
            help: nil,
            control: .picker(options: [.string("none"), .string("regular"), .string("high")], style: .menu),
            defaultValue: .string("regular"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("regular"))
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
            control: .seed(range: 1...Int(UInt32.max)),
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
