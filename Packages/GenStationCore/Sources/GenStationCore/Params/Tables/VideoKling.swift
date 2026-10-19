// Descriptor tables — Kling video models (Stage 2, Task 8).
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

    // MARK: klingv25TurboVideo
    //
    // klingv25TurboVideoJSONBuilder / klingv25TurboVideoParameterParser
    // View: buildKlingv25TurboVideoParamsView
    // 2 registered ids: kling-video/v2.5-turbo/pro/image-to-video, klingai/v2.5-turbo/pro/image-to-video
    static let klingv25TurboVideo: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: "The length of the output video in seconds.",
            control: .picker(options: [.int(5), .int(10)], style: .menu),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: "The description of elements to avoid in the generated video.",
            control: .text(placeholder: "Elements to avoid"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "cfg_scale",
            field: .guidanceScale,
            label: "CFG Scale",
            help: "The CFG (Classifier Free Guidance) scale is a measure of how close you want the model to stick to your prompt. Maximum value is 1.",
            control: .slider(range: 0...1, step: 0.1),
            defaultValue: .double(0.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.5))
        )
    ]

    // MARK: klingVideo
    //
    // klingVideoJSONBuilder / klingVideoParameterParser
    // View: buildKlingVideoParamsView
    // 23 registered ids: kling-video/v1.6/pro/image-to-video, kling-video/v1.6/pro/text-to-video, kling-video/v1.6/standard/image-to-video, kling-video/v1.6/standard/text-to-video, kling-video/v1/pro/image-to-video, kling-video/v1/pro/text-to-video, kling-video/v1/standard/image-to-video, kling-video/v1/standard/text-to-video, kling-video/v2.1/master/image-to-video, kling-video/v2.1/master/text-to-video, kling-video/v2.1/pro/image-to-video, kling-video/v2.1/standard/image-to-video, kling-video/v2.5-turbo/pro/text-to-video, kling-video/v2/master/image-to-video, kling-video/v2/master/text-to-video, klingai/v1-standard/text-to-video, klingai/v2-master-image-to-video, klingai/v2-master-text-to-video, klingai/v2.1-master-image-to-video, klingai/v2.1-master-text-to-video, klingai/v2.5-turbo/pro/text-to-video, klingai/video-o1-image-to-video, klingai/video-o1-reference-to-video
    //
    // unverified: copied from the shared Kling video view; no API schema exists to check it.
    static let klingVideo: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("1:1")], style: .segmented),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(5), .int(10)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "cfg_scale",
            field: .cfgScale,
            label: "CFG Scale",
            help: "How closely to follow the prompt (0 = creative, 1 = strict)",
            control: .slider(range: 0...1, step: 0.05),
            defaultValue: .double(0.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.5))
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt (Optional)",
            help: nil,
            control: .text(placeholder: "Elements to avoid"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "camera_control",
            field: .cameraControl,
            label: "Camera Control",
            help: "Range: -10 (left/down/out) to 10 (right/up/in)",
            control: .custom(.klingCameraControl),
            defaultValue: nil,
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .setNil
        ),

        ParamDescriptor(
            wireKey: "",
            field: .cameraMovementType,
            label: "Camera Control",
            help: "Range: -10 (left/down/out) to 10 (right/up/in)",
            control: .picker(options: [.string("horizontal"), .string("vertical"), .string("pan"), .string("tilt"), .string("roll"), .string("zoom")], style: .menu),
            defaultValue: nil,
            visibleWhen: .fieldEquals(.cameraControl, .string("advanced")),
            alwaysEmit: false,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor(
            wireKey: "",
            field: .cameraMovementValue,
            label: "Camera Control",
            help: "Range: -10 (left/down/out) to 10 (right/up/in)",
            control: .slider(range: -10...10, step: 1),
            defaultValue: nil,
            visibleWhen: .fieldEquals(.cameraControl, .string("advanced")),
            alwaysEmit: false,
            parseFallback: .leaveUnchanged
        ),

        ParamDescriptor.info(
            label: "Input Image Required",
            text: "Provide an input image to animate into a video.",
            visibleWhen: .isImageToVideo
        )
    ]

    // MARK: kling26
    //
    // kling26JSONBuilder / kling26ParameterParser
    // View: buildKling26ParamsView
    // 4 registered ids: kling-video/v2.6/pro/image-to-video, kling-video/v2.6/pro/text-to-video, klingai/video-v2-6-pro-image-to-video, klingai/video-v2-6-pro-text-to-video
    static let kling26: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("1:1")], style: .segmented),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: nil,
            control: .picker(options: [.int(5), .int(10)], style: .segmented),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "cfg_scale",
            field: .cfgScale,
            label: "CFG Scale",
            help: "How closely to follow the prompt (0 = creative, 1 = strict)",
            control: .slider(range: 0...1, step: 0.05),
            defaultValue: .double(0.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.5))
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Kling 2.6 supports native audio generation with your video",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt (Optional)",
            help: nil,
            control: .text(placeholder: "Elements to avoid"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .setNil
        ),

        ParamDescriptor.info(
            label: "Input Image Required",
            text: "Provide an input image to animate into a video.",
            visibleWhen: .isImageToVideo
        ),

        ParamDescriptor.info(
            label: "Kling 2.6 Pro",
            text: "Flagship model with native audio."
        )
    ]

    // MARK: klingV3
    //
    // klingV3JSONBuilder / klingV3ParameterParser
    // View: buildKlingV3ParamsView
    // 8 registered ids: kling-video/v3/pro/image-to-video, kling-video/v3/pro/text-to-video, kling-video/v3/standard/image-to-video, kling-video/v3/standard/text-to-video, klingai/video-v3-pro-image-to-video, klingai/video-v3-pro-text-to-video, klingai/video-v3-standard-image-to-video, klingai/video-v3-standard-text-to-video
    static let klingV3: [ParamDescriptor] = [
        ParamDescriptor(
            wireKey: "aspect_ratio",
            field: .aspectRatio,
            label: "Aspect Ratio",
            help: nil,
            control: .picker(options: [.string("16:9"), .string("9:16"), .string("1:1")], style: .segmented),
            defaultValue: .string("16:9"),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.string("16:9"))
        ),

        ParamDescriptor(
            wireKey: "duration",
            field: .duration,
            label: "Duration",
            help: "Single-prompt duration. Multi-shot prompts default to 5s per shot (15s max total).",
            control: .slider(range: 3...15, step: 1),
            defaultValue: .int(5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.int(5))
        ),

        ParamDescriptor(
            wireKey: "cfg_scale",
            field: .cfgScale,
            label: "CFG Scale",
            help: "Lower = more creative, higher = follows prompt more closely",
            control: .slider(range: 0...1, step: 0.05),
            defaultValue: .double(0.5),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.double(0.5))
        ),

        ParamDescriptor(
            wireKey: "generate_audio",
            field: .generateAudio,
            label: "Generate Audio",
            help: "Native audio in Chinese and English. Describe sounds in your prompt for best results.",
            control: .toggle,
            defaultValue: .bool(true),
            visibleWhen: nil,
            alwaysEmit: false,
            parseFallback: .value(.bool(true))
        ),

        ParamDescriptor(
            wireKey: "shot_type",
            field: .shotType,
            label: "Shot Type",
            help: "Controls camera angles for multi-shot videos. Intelligent lets the AI decide.",
            control: .picker(options: [.string("intelligent"), .string("customize")], style: .segmented),
            defaultValue: .string("intelligent"),
            // Visible at both values, emitted at only one. The legacy view rendered this picker
            // unconditionally (`Params View/KlingV3ParamsView.swift:111-119`); the `== "customize"`
            // test is the *builder's* (`Legacy/Kling.swift:71`), so it belongs in `emitWhen`. As
            // `visibleWhen` it hid the control whenever `shot_type` was anything but `customize` —
            // including its own default — leaving no way to ever reach `customize`.
            visibleWhen: nil,
            alwaysEmit: false,
            emitWhen: .equalTo(.string("customize")),
            parseFallback: .value(.string("intelligent"))
        ),

        ParamDescriptor(
            wireKey: "negative_prompt",
            field: .negativePrompt,
            label: "Negative Prompt",
            help: nil,
            control: .text(placeholder: "Elements to avoid"),
            defaultValue: .string(""),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .setNil
        ),

        ParamDescriptor.info(
            label: "Input Image",
            text: "First image slot = first frame. Optional second image slot = end frame.",
            visibleWhen: .isImageToVideo
        ),

        ParamDescriptor.info(
            label: "Kling v3",
            text: "Multi-shot storyboard: separate scenes with line breaks in the prompt (up to 6 shots, 15s total). Single paragraph = single shot.\n\nPer-shot duration: add duration at the end of each line, e.g. \"a cat wakes up 5s\". Shots without a duration split the remaining time evenly. Min 3s per shot."
        )
    ].map { $0.wireKey == "shot_type" ? $0.historyOnly : $0 }

}
