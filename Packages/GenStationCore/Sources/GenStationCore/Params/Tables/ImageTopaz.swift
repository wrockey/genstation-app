// Descriptor tables — Topaz image models (Stage 2, Task 10).
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

    // MARK: topazSharpen
    //
    // topazSharpenJSONBuilder / topazSharpenParameterParser
    // View: buildTopazSharpenParamsView
    // 1 registered id: topaz-labs/sharpen
    static let topazSharpen: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "mode",
            field: .topazMode,
            label: "Sharpen Mode",
            help: nil,
            control: .picker(options: [.string("Standard"), .string("Strong"), .string("Lens Blur"), .string("Lens Blur V2"), .string("Motion Blur"), .string("Natural"), .string("Refocus")], style: .menu),
            defaultValue: .string("Standard"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.string("Standard")),
            // `topazMode` is shared with the other Topaz tables, whose vocabularies do not overlap with
            // this one's — a mode chosen on `topaz-labs/upscale` travels here and is rejected. `mode` is
            // **required** by this model, so a rejected value falls back to `defaultValue` (see
            // `ParamEncoder`) instead of leaving the key off.
            allowedValues: [.string("Lens Blur"), .string("Lens Blur V2"), .string("Motion Blur"),
                            .string("Natural"), .string("Refocus"), .string("Standard"), .string("Strong")]
        ),

        ParamDescriptor(
            wireKey: "strength",
            field: .strength,
            label: "Strength",
            help: nil,
            control: .slider(range: 0.01...1, step: 0.01),
            defaultValue: .double(0.8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.5))
        ),

        ParamDescriptor(
            wireKey: "minor_denoise",
            field: .minorDenoise,
            label: "Minor Denoise",
            help: nil,
            control: .slider(range: 0.01...1, step: 0.01),
            defaultValue: .double(0.25),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.25))
        ),

        ParamDescriptor(
            wireKey: "subject_detection",
            field: .subjectDetection,
            label: "Subject Detection",
            help: nil,
            control: .picker(options: [.string("All"), .string("Foreground"), .string("Background")], style: .segmented),
            defaultValue: .string("All"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("All"))
        ),

        ParamDescriptor(
            wireKey: "face_enhancement",
            field: .faceEnhancement,
            label: "Face Enhancement",
            help: nil,
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "face_enhancement_strength",
            field: .faceEnhancementStrength,
            label: "Face Enhancement Strength",
            help: "How strongly detected faces are re-rendered. Applies only while Face Enhancement is on.",
            control: .slider(range: 0...1, step: 0.01),
            defaultValue: .double(0.8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.8))
        ),

        ParamDescriptor(
            wireKey: "face_enhancement_creativity",
            field: .faceEnhancementCreativity,
            label: "Face Enhancement Creativity",
            help: "How far the face may depart from the original. 0 keeps the likeness. Applies only while Face Enhancement is on.",
            control: .slider(range: 0...1, step: 0.01),
            defaultValue: .double(0.0),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.0))
        ),

        ParamDescriptor(
            wireKey: "output_format",
            field: .outputFormat,
            label: "Output Format",
            help: nil,
            control: .picker(options: [.string("png"), .string("jpeg")], style: .segmented),
            defaultValue: .string("png"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("png"))
        )
    ]

    // MARK: topazSharpenGen
    //
    // topazSharpenGenJSONBuilder / topazSharpenGenParameterParser
    // View: buildTopazSharpenGenParamsView
    // 1 registered id: topaz-labs/sharpen-gen
    static let topazSharpenGen: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "mode",
            field: .topazMode,
            label: "Generative Sharpen Mode",
            help: nil,
            control: .picker(options: [.string("Super Focus"), .string("Super Focus V2")], style: .segmented),
            defaultValue: .string("Super Focus"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.string("Super Focus")),
            // Same shared-`topazMode` problem as `topazSharpen`, and `mode` is required here too.
            allowedValues: [.string("Super Focus"), .string("Super Focus V2")]
        ),

        ParamDescriptor(
            wireKey: "strength",
            field: .strength,
            label: "Strength",
            help: nil,
            control: .slider(range: 0...1, step: 0.01),
            defaultValue: .double(0.8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.5))
        ),

        ParamDescriptor(
            wireKey: "focus_boost",
            field: .focusBoost,
            label: "Focus Boost",
            help: nil,
            control: .slider(range: 0.25...1, step: 0.01),
            defaultValue: .double(0.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.5))
        ),

        ParamDescriptor(
            wireKey: "subject_detection",
            field: .subjectDetection,
            label: "Subject Detection",
            help: nil,
            control: .picker(options: [.string("All"), .string("Foreground"), .string("Background")], style: .segmented),
            defaultValue: .string("All"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("All"))
        ),

        ParamDescriptor(
            wireKey: "face_enhancement",
            field: .faceEnhancement,
            label: "Face Enhancement",
            help: nil,
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "face_enhancement_strength",
            field: .faceEnhancementStrength,
            label: "Face Enhancement Strength",
            help: "How strongly detected faces are re-rendered. Applies only while Face Enhancement is on.",
            control: .slider(range: 0...1, step: 0.01),
            defaultValue: .double(0.8),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.8))
        ),

        ParamDescriptor(
            wireKey: "face_enhancement_creativity",
            field: .faceEnhancementCreativity,
            label: "Face Enhancement Creativity",
            help: "How far the face may depart from the original. 0 keeps the likeness. Applies only while Face Enhancement is on.",
            control: .slider(range: 0...1, step: 0.01),
            defaultValue: .double(0.0),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.0))
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
            wireKey: "output_format",
            field: .outputFormat,
            label: "Output Format",
            help: nil,
            control: .picker(options: [.string("png"), .string("jpeg")], style: .segmented),
            defaultValue: .string("png"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("png"))
        )
    ]

}
