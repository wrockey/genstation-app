// Descriptor tables — OpenAI image models (Stage 2, Task 10).
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

    // MARK: openAIGPTImage1Extended
    //
    // openAIGPTImage1ExtendedJSONBuilder / openAIGPTImage1ExtendedParameterParser
    // View: buildOpenAIGPTImage1ExtendedParamsView
    // 4 registered ids: gpt-image-1, gpt-image-1-mini, openai/gpt-image-1, openai/gpt-image-1-mini
    static let openAIGPTImage1Extended: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "background",
            field: .background,
            label: "Background",
            help: nil,
            control: .picker(options: [.string("transparent"), .string("opaque"), .string("auto")], style: .menu),
            defaultValue: .string("auto"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.string("auto")),
            emitClamp: EmitClamp([
                .init(allowed: [.string("transparent"), .string("opaque"), .string("auto")], fallback: .string("auto"))
            ])
        ),

        ParamDescriptor(
            wireKey: "quality",
            field: .quality,
            label: "Quality",
            help: nil,
            control: .picker(options: [.string("low"), .string("medium"), .string("high")], style: .menu),
            defaultValue: .string("medium"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.string("medium")),
            emitClamp: EmitClamp([
                .init(allowed: [.string("low"), .string("medium"), .string("high")], fallback: .string("medium"))
            ])
        ),

        ParamDescriptor(
            wireKey: "size",
            field: .size,
            label: "Size",
            help: nil,
            control: .picker(options: [.string("1024x1024"), .string("1024x1536"), .string("1536x1024")], style: .menu),
            defaultValue: .string("1024x1024"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.string("1024x1024")),
            emitClamp: EmitClamp([
                .init(allowed: [.string("1024x1024"), .string("1024x1536"), .string("1536x1024")], fallback: .string("1024x1024"))
            ])
        ),

        ParamDescriptor(
            wireKey: "moderation",
            field: .moderation,
            label: "Moderation",
            help: nil,
            control: .picker(options: [.string("auto"), .string("low")], style: .menu),
            defaultValue: .string("auto"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.string("auto")),
            emitClamp: EmitClamp([
                .init(allowed: [.string("low"), .string("auto")], fallback: .string("auto"))
            ])
        ),

        ParamDescriptor(
            wireKey: "output_format",
            field: .outputFormat,
            label: "Output Format",
            help: nil,
            control: .picker(options: [.string("png"), .string("jpeg"), .string("webp")], style: .menu),
            defaultValue: .string("png"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.string("png")),
            emitClamp: EmitClamp([
                .init(allowed: [.string("png"), .string("jpeg"), .string("webp")], fallback: .string("png"))
            ])
        )
    ]

    // MARK: openAIGPTImage1
    //
    // openAIGPTImage1JSONBuilder / openAIGPTImage1ParameterParser
    // View: buildOpenAIGPTImage1ParamsView
    // 5 registered ids: gpt-image-1.5, gpt-image-2, openai/gpt-image-1-5, openai/gpt-image-1.5, openai/gpt-image-2
    static let openAIGPTImage1: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "background",
            field: .background,
            label: "Background",
            help: nil,
            control: .picker(options: [.string("transparent"), .string("opaque"), .string("auto")], style: .menu),
            defaultValue: .string("auto"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.string("auto")),
            emitClamp: EmitClamp([
                .init(allowed: [.string("transparent"), .string("opaque"), .string("auto")], fallback: .string("auto"))
            ])
        ),

        ParamDescriptor(
            wireKey: "quality",
            field: .quality,
            label: "Quality",
            help: nil,
            control: .picker(options: [.string("low"), .string("medium"), .string("high")], style: .menu),
            defaultValue: .string("medium"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.string("medium")),
            emitClamp: EmitClamp([
                .init(allowed: [.string("low"), .string("medium"), .string("high")], fallback: .string("medium"))
            ])
        ),

        ParamDescriptor(
            wireKey: "size",
            field: .size,
            label: "Size",
            help: nil,
            control: .picker(options: [.string("1024x1024"), .string("1024x1536"), .string("1536x1024")], style: .menu),
            defaultValue: .string("1024x1024"),
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .value(.string("1024x1024")),
            emitClamp: EmitClamp([
                .init(allowed: [.string("1024x1024"), .string("1024x1536"), .string("1536x1024")], fallback: .string("1024x1024"))
            ])
        )
    ]

}
