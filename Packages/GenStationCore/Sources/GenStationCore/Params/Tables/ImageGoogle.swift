// Descriptor tables — Google image models (Stage 2, Task 10).
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

    // MARK: googleImagen4Ultra
    //
    // googleImagen4UltraJSONBuilder / googleImagen4UltraParameterParser
    // View: buildGoogleImagen4UltraParamsView
    // 7 registered ids: google/imagen-3.0-generate-002, google/imagen-4.0-fast-generate-001, google/imagen-4.0-generate-001, google/imagen-4.0-ultra-generate-001, imagen-3.0-generate-002, imagen-4.0-generate-001, imagen-4.0-ultra-generate-001
    static let googleImagen4Ultra: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "num_images",
            field: .numImages,
            label: "Number of Images",
            help: nil,
            control: .picker(options: [.int(1), .int(2), .int(3), .int(4)], style: .segmented),
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
            control: .seed(range: 0...4_294_967_295),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "enhance_prompt",
            field: .enhancePrompt,
            label: "Enhance Prompt",
            help: "Uses an LLM to rewrite the prompt for higher quality (default: on)",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("1:1"), .string("9:16"), .string("16:9"), .string("3:4"), .string("4:3")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("1:1"))
        ),

        ParamDescriptor(
            wireKey: "add_watermark",
            field: .watermark,
            label: "Add Invisible Watermark",
            help: nil,
            control: .toggle,
            defaultValue: .bool(false),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(false))
        )
    ]

    // MARK: gemini25FlashImage
    //
    // gemini25FlashImageJSONBuilder / gemini25FlashImageParameterParser
    // View: buildGemini25FlashImageParamsView
    // 1 registered id: google/gemini-2.5-flash-image
    static let gemini25FlashImage: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "num_images",
            field: .numImages,
            label: "Number of Images",
            help: "Number of images to generate (1-4)",
            control: .picker(options: [.int(1), .int(2), .int(3), .int(4)], style: .menu),
            defaultValue: .int(1),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: .atLeast(2),
            parseFallback: .value(.int(1))
        )
    ]

    // MARK: gemini25FlashImageEdit
    //
    // gemini25FlashImageEditJSONBuilder / gemini25FlashImageEditParameterParser
    // View: buildGemini25FlashImageEditParamsView
    // 1 registered id: google/gemini-2.5-flash-image-edit
    static let gemini25FlashImageEdit: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "num_images",
            field: .numImages,
            label: "Number of Images",
            help: "How many variations to generate from your input image(s)",
            control: .picker(options: [.int(1), .int(2), .int(3), .int(4)], style: .segmented),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: .atLeast(1),
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor.info(
            label: "Image-to-Image Mode",
            text: "This model edits or generates new images based on your uploaded image(s) and prompt.\n\n• Upload 1–4 images via the input slots above.\n• The prompt will be used to guide the edit or variation."
        )
    ]

    // MARK: gemini3ProImagePreview
    //
    // gemini3ProImagePreviewJSONBuilder / gemini3ProImagePreviewParameterParser
    // View: buildGemini3ProImagePreviewParamsView
    // 2 registered ids: google/gemini-3-pro-image-preview, google/nano-banana-pro
    static let gemini3ProImagePreview: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("1:1"), .string("4:3"), .string("3:4"), .string("16:9"), .string("9:16")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: .notEqualTo(.string("1:1")),
            parseFallback: .value(.string("1:1")),
            // Five of the ten options this picker offered — `21:9`, `3:2`, `2:3`, `5:4`, `4:5` — are not
            // in either registered id's published enum, so choosing one produced a validation failure
            // rather than a differently-shaped image. Dropped from the list, and `allowedValues` stops
            // the same ratios arriving from another model through the shared `aspectRatio` field.
            allowedValues: [.string("1:1"), .string("3:4"), .string("4:3"), .string("9:16"), .string("16:9")]
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .geminiResolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("1K"), .string("2K"), .string("4K")], style: .menu),
            defaultValue: .string("1K"),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: .notEqualTo(.string("1K")),
            parseFallback: .value(.string("1K"))
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
            emitWhen: .atLeast(2),
            parseFallback: .value(.int(1))
        )
    ]

    // MARK: gemini3ProImagePreviewEdit
    //
    // gemini3ProImagePreviewEditJSONBuilder / gemini3ProImagePreviewEditParameterParser
    // View: buildGemini3ProImagePreviewEditParamsView
    // 2 registered ids: google/gemini-3-pro-image-preview-edit, google/nano-banana-pro-edit
    static let gemini3ProImagePreviewEdit: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("1:1"), .string("4:3"), .string("3:4"), .string("16:9"), .string("9:16")], style: .menu),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: .notEqualTo(.string("1:1")),
            parseFallback: .value(.string("1:1")),
            // Five of the ten options this picker offered — `21:9`, `3:2`, `2:3`, `5:4`, `4:5` — are not
            // in either registered id's published enum, so choosing one produced a validation failure
            // rather than a differently-shaped image. Dropped from the list, and `allowedValues` stops
            // the same ratios arriving from another model through the shared `aspectRatio` field.
            allowedValues: [.string("1:1"), .string("3:4"), .string("4:3"), .string("9:16"), .string("16:9")]
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .geminiResolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("1K"), .string("2K"), .string("4K")], style: .menu),
            defaultValue: .string("1K"),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: .notEqualTo(.string("1K")),
            parseFallback: .value(.string("1K"))
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
            emitWhen: .atLeast(2),
            parseFallback: .value(.int(1))
        )
    ]

    // MARK: nanoBanana2
    //
    // Written from the captured schema (2026-08-11), not from a legacy view — there is none.
    // `enable_web_search` is published (bool, default false) and deliberately unmodeled: no
    // `ParamField` carries it, and omitting an optional key defers to the vendor default.
    // `resolution` reads/writes `.geminiResolution`, not `.resolution`: `ModelParameters.resolution`'s
    // struct default is `"720p"`, which is not a member of this model's `["1K","2K","4K"]` enum and
    // would be silently omitted by `ParamEncoder`'s rule 5 on every probe that never touches the
    // control — the same class of bug this stage exists to eliminate. `.geminiResolution` is the field
    // the other two Gemini-image tables in this file already use for the same enum, and its struct
    // default (`"1K"`) is a member.
    // 2 registered ids: google/gemini-3.1-flash-image-preview (+ alias nano-banana-2)
    static let nanoBanana2: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: "auto lets the model choose; otherwise fixes the output shape",
            control: .picker(options: [.string("auto"), .string("21:9"), .string("1:1"),
                                       .string("4:3"), .string("3:2"), .string("2:3"),
                                       .string("5:4"), .string("4:5"), .string("3:4"),
                                       .string("16:9"), .string("9:16")], style: .menu),
            defaultValue: .string("auto"),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: nil,
            parseFallback: .leaveUnchanged,
            allowedValues: [.string("auto"), .string("21:9"), .string("1:1"), .string("4:3"),
                            .string("3:2"), .string("2:3"), .string("5:4"), .string("4:5"),
                            .string("3:4"), .string("16:9"), .string("9:16")]
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .geminiResolution,
            label: "Resolution",
            help: "Output resolution tier; 4K costs more",
            control: .picker(options: [.string("1K"), .string("2K"), .string("4K")], style: .segmented),
            defaultValue: .string("1K"),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: nil,
            parseFallback: .leaveUnchanged,
            allowedValues: [.string("1K"), .string("2K"), .string("4K")]
        )
    ]

    // MARK: nanoBanana2Lite
    //
    // Written from the captured schema (2026-08-11), not from a legacy view — there is none. Same
    // shape as `nanoBanana2` except: the aspect list is this model's own 5-value enum, and
    // `aspect_ratio` carries no `defaultValue` — the schema publishes none, and none is invented here.
    // `resolution` reuses `.geminiResolution` for the same reason as `nanoBanana2` above.
    // 1 registered id: google/gemini-3-1-flash-lite-image
    static let nanoBanana2Lite: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("1:1"), .string("9:16"), .string("16:9"),
                                       .string("3:4"), .string("4:3")], style: .menu),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: nil,
            parseFallback: .leaveUnchanged,
            allowedValues: [.string("1:1"), .string("9:16"), .string("16:9"),
                            .string("3:4"), .string("4:3")]
        ),

        ParamDescriptor(
            wireKey: "resolution",
            field: .geminiResolution,
            label: "Resolution",
            help: "Output resolution tier; 4K costs more",
            control: .picker(options: [.string("1K"), .string("2K"), .string("4K")], style: .segmented),
            defaultValue: .string("1K"),
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: nil,
            parseFallback: .leaveUnchanged,
            allowedValues: [.string("1K"), .string("2K"), .string("4K")]
        )
    ]

}
