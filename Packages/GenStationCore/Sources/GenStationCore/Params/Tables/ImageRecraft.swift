// Descriptor tables — Recraft image models (Stage 2, Task 10).
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

    // MARK: recraftV3
    //
    // recraftV3JSONBuilder / recraftV3ParameterParser
    // View: buildRecraftV3ParamsView
    // 1 registered id: recraft-v3
    static let recraftV3: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "style",
            field: .stylePreset,
            label: "Style",
            help: "Vector styles output SVG format",
            control: .picker(options: [.string("realistic_image"), .string("realistic_image/b_and_w"), .string("realistic_image/hard_flash"), .string("realistic_image/hdr"), .string("realistic_image/natural_light"), .string("realistic_image/studio_portrait"), .string("realistic_image/enterprise"), .string("realistic_image/motion_blur"), .string("digital_illustration"), .string("digital_illustration/pixel_art"), .string("digital_illustration/hand_drawn"), .string("digital_illustration/grain"), .string("digital_illustration/infantile_sketch"), .string("digital_illustration/2d_art_poster"), .string("digital_illustration/handmade_3d"), .string("digital_illustration/hand_drawn_outline"), .string("digital_illustration/engraving_color"), .string("digital_illustration/2d_art_poster_2"), .string("vector_illustration"), .string("vector_illustration/engraving"), .string("vector_illustration/line_art"), .string("vector_illustration/line_circuit"), .string("vector_illustration/linocut"), .string("any")], style: .menu),
            defaultValue: .string("realistic_image"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("realistic_image")),
            // Recraft's style names are qualified — `realistic_image`, not `realistic` — so the bare
            // `"realistic"` that `stylePreset` picks up from a PixVerse-shaped model was rejected here.
            // Omitted rather than mapped to `realistic_image`: the two are not the same request, and
            // guessing which sub-style the user meant is exactly the substitution this must not do.
            // `digital_illustration` is added to the picker above; it is a published style the option
            // list was missing while offering eleven of its children.
            allowedValues: [.string("any"), .string("digital_illustration"),
                            .string("digital_illustration/2d_art_poster"),
                            .string("digital_illustration/2d_art_poster_2"),
                            .string("digital_illustration/engraving_color"),
                            .string("digital_illustration/grain"),
                            .string("digital_illustration/hand_drawn"),
                            .string("digital_illustration/hand_drawn_outline"),
                            .string("digital_illustration/handmade_3d"),
                            .string("digital_illustration/infantile_sketch"),
                            .string("digital_illustration/pixel_art"),
                            .string("realistic_image"), .string("realistic_image/b_and_w"),
                            .string("realistic_image/enterprise"), .string("realistic_image/hard_flash"),
                            .string("realistic_image/hdr"), .string("realistic_image/motion_blur"),
                            .string("realistic_image/natural_light"),
                            .string("realistic_image/studio_portrait"),
                            .string("vector_illustration"), .string("vector_illustration/engraving"),
                            .string("vector_illustration/line_art"),
                            .string("vector_illustration/line_circuit"),
                            .string("vector_illustration/linocut")]
        ),

        ParamDescriptor(
            wireKey: "image_size",
            field: nil,
            label: "Image Size",
            help: "Values must be multiples of 32",
            control: .imageSize(ImageSizeSpec(presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
                              presetFallback: "square_hd",
                              dimensions: [64, 256, 512, 768, 1024, 1280, 1536],
                              widthFallback: 1024,
                              heightFallback: 1024)),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: true,
            parseFallback: .leaveUnchanged
        )
    ]

}
