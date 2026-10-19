// Stage 2, Task 6 — the descriptor payload encoder.
//
// The central rule under test is design § 3.2: **visibility and emission are one decision**. A row
// whose `visibleWhen` predicate is false is neither rendered nor emitted. Today those are two
// independent decisions in two functions, which is how Seedance ships an `aspect_ratio` the user
// cannot see.

import XCTest
@testable import GenStationCore

final class ParamEncoderTests: XCTestCase {

    private func ctx(isI2I: Bool = false, hasInputImages: Bool = false) -> ParamContext {
        ParamContext(modelId: "x", isI2I: isI2I, hasInputImages: hasInputImages)
    }

    // MARK: - Visibility is emission

    func testAHiddenRowIsNotEmitted() {
        let d = ParamDescriptor(wireKey: "aspect_ratio", field: .aspectRatio, label: "Aspect Ratio",
                                help: nil, control: .picker(options: [.string("16:9")], style: .menu),
                                defaultValue: .string("16:9"), visibleWhen: .isTextToVideo, alwaysEmit: false)
        var p = ModelParameters(); p.aspectRatio = "16:9"
        let context = ParamContext(modelId: "x", isI2I: true, hasInputImages: true)
        XCTAssertNil(ParamEncoder.encode([d], params: p, context: context)["aspect_ratio"])
    }

    func testAVisibleRowIsEmitted() {
        let d = ParamDescriptor(wireKey: "aspect_ratio", field: .aspectRatio, label: "Aspect Ratio",
                                help: nil, control: .picker(options: [.string("16:9")], style: .menu),
                                defaultValue: .string("16:9"), visibleWhen: .isTextToVideo, alwaysEmit: false)
        var p = ModelParameters(); p.aspectRatio = "16:9"
        XCTAssertEqual(ParamEncoder.encode([d], params: p, context: ctx())["aspect_ratio"] as? String, "16:9")
    }

    /// `.isTextToVideo` reads the **static** registry flag, not the live mode. That flag is unsound for
    /// dual-mode models (drift ledger), but Task 8's tables freeze legacy behaviour, so the predicate
    /// must not consult `hasInputImages` yet.
    func testIsTextToVideoReadsTheStaticFlagNotTheLiveMode() {
        let d = ParamDescriptor(wireKey: "aspect_ratio", field: .aspectRatio, label: "", help: nil,
                                control: .none, defaultValue: nil, visibleWhen: .isTextToVideo,
                                alwaysEmit: false)
        var p = ModelParameters(); p.aspectRatio = "16:9"
        let staticT2V = ParamContext(modelId: "x", isI2I: false, hasInputImages: true)
        XCTAssertEqual(ParamEncoder.encode([d], params: p, context: staticT2V)["aspect_ratio"] as? String, "16:9",
                       "hasInputImages must not gate emission until the ledger fix lands")
    }

    func testAFieldEqualsConditionGatesEmission() {
        let d = ParamDescriptor(wireKey: "camera_movement_type", field: .cameraMovementType, label: "Movement",
                                help: nil, control: .picker(options: [.string("zoom")], style: .menu),
                                defaultValue: nil, visibleWhen: .fieldEquals(.cameraControl, .string("advanced")),
                                alwaysEmit: false)
        var p = ModelParameters(); p.cameraMovementType = "zoom"

        p.cameraControl = "simple"
        XCTAssertNil(ParamEncoder.encode([d], params: p, context: ctx())["camera_movement_type"])

        p.cameraControl = "advanced"
        XCTAssertEqual(ParamEncoder.encode([d], params: p, context: ctx())["camera_movement_type"] as? String, "zoom")
    }

    // MARK: - Emission rules

    func testAnAlwaysEmitRowShipsWithNoControl() {
        let d = ParamDescriptor(wireKey: "enable_safety_checker", field: .enableSafetyChecker,
                                label: "", help: nil, control: .none, defaultValue: .bool(true),
                                visibleWhen: nil, alwaysEmit: true)
        XCTAssertEqual(ParamEncoder.encode([d], params: ModelParameters(), context: ctx())["enable_safety_checker"] as? Bool, true)
    }

    func testAnAlwaysEmitRowPrefersTheStoredValueOverTheDefault() {
        let d = ParamDescriptor(wireKey: "enable_safety_checker", field: .enableSafetyChecker,
                                label: "", help: nil, control: .none, defaultValue: .bool(true),
                                visibleWhen: nil, alwaysEmit: true)
        var p = ModelParameters(); p.enableSafetyChecker = false
        XCTAssertEqual(ParamEncoder.encode([d], params: p, context: ctx())["enable_safety_checker"] as? Bool, false)
    }

    func testANilFieldWithNoDefaultIsOmitted() {
        let d = ParamDescriptor(wireKey: "seed", field: .seed, label: "Seed", help: nil,
                                control: .seed(range: 1...Int(Int32.max)), defaultValue: nil,
                                visibleWhen: nil, alwaysEmit: false)
        XCTAssertNil(ParamEncoder.encode([d], params: ModelParameters(), context: ctx())["seed"])
    }

    /// The descriptor's `defaultValue` is what the UI shows when the field is nil. It is **not** a
    /// substitute value for encoding. `flux/dev`'s `guidanceScale` has a nil struct default and its
    /// legacy builder emits the key only via `if let`, so the other answer breaks equivalence.
    func testANilFieldIsOmittedEvenWhenTheDescriptorHasADefault() {
        let d = ParamDescriptor(wireKey: "guidance_scale", field: .guidanceScale, label: "Guidance",
                                help: nil, control: .slider(range: 1...20, step: 0.5),
                                defaultValue: .double(3.5), visibleWhen: nil, alwaysEmit: false)
        let context = ParamContext(modelId: "flux/dev", isI2I: false, hasInputImages: false)
        XCTAssertNil(ParamEncoder.encode([d], params: ModelParameters(), context: context)["guidance_scale"])
    }

    /// 15 legacy builders gate a String on `!isEmpty` (`negative_prompt`, PixVerse `style`). The
    /// control stays visible when the string is empty — the user needs somewhere to type — so this is
    /// an emission-only refinement, not a `visibleWhen`.
    func testAnOmitWhenEmptyRowSkipsAnEmptyString() {
        let d = ParamDescriptor(wireKey: "negative_prompt", field: .negativePrompt, label: "Negative",
                                help: nil, control: .text(placeholder: ""), defaultValue: nil,
                                visibleWhen: nil, alwaysEmit: false, omitWhenEmpty: true)
        var p = ModelParameters(); p.negativePrompt = ""
        XCTAssertNil(ParamEncoder.encode([d], params: p, context: ctx())["negative_prompt"])

        p.negativePrompt = "blurry"
        XCTAssertEqual(ParamEncoder.encode([d], params: p, context: ctx())["negative_prompt"] as? String, "blurry")
    }

    func testAnEmptyStringIsEmittedWithoutOmitWhenEmpty() {
        let d = ParamDescriptor(wireKey: "negative_prompt", field: .negativePrompt, label: "Negative",
                                help: nil, control: .text(placeholder: ""), defaultValue: nil,
                                visibleWhen: nil, alwaysEmit: false)
        var p = ModelParameters(); p.negativePrompt = ""
        XCTAssertEqual(ParamEncoder.encode([d], params: p, context: ctx())["negative_prompt"] as? String, "",
                       "wan25I2VJSONBuilder emits an empty negative_prompt; only the isEmpty-gated builders do not")
    }

    /// `.info` panels are UI-only: no field, no wire key, nothing on the wire.
    func testAnInfoRowEmitsNothing() {
        let d = ParamDescriptor(wireKey: "", field: nil, label: "", help: nil,
                                control: .info(text: "This model always renders at 16:9."),
                                defaultValue: nil, visibleWhen: nil, alwaysEmit: false)
        XCTAssertTrue(ParamEncoder.encode([d], params: ModelParameters.fullyPopulatedProbe(), context: ctx()).isEmpty)
    }

    /// Three builders emit a literal the user cannot change (`dict["aspect_ratio"] = "16:9"`).
    func testAFieldlessAlwaysEmitRowShipsItsDefaultAsAConstant() {
        let d = ParamDescriptor(wireKey: "aspect_ratio", field: nil, label: "", help: nil,
                                control: .none, defaultValue: .string("16:9"), visibleWhen: nil,
                                alwaysEmit: true)
        XCTAssertEqual(ParamEncoder.encode([d], params: ModelParameters(), context: ctx())["aspect_ratio"] as? String, "16:9")
    }

    // MARK: - The image_size composite

    /// The shared helper's spec — `LegacyPayload.imageSizeValue`, used by `wanImage`/`wanImageEdit`.
    private static let sharedSpec = ImageSizeSpec(
        presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
        presetFallback: "landscape_4_3",
        dimensions: [512, 768, 1024, 1280, 1440],
        widthFallback: 1024, heightFallback: 1024)

    private func imageSizeRow(_ spec: ImageSizeSpec) -> ParamDescriptor {
        ParamDescriptor(wireKey: "image_size", field: nil, label: "Image Size", help: nil,
                        control: .imageSize(spec), defaultValue: nil, visibleWhen: nil, alwaysEmit: true)
    }

    private func imageSize(_ spec: ImageSizeSpec, _ params: ModelParameters) -> Any? {
        ParamEncoder.encode([imageSizeRow(spec)], params: params, context: ctx())["image_size"]
    }

    /// The one control whose emitted JSON *type* changes: a preset String, or a `{width, height}`
    /// object when the mode is "custom". **Both branches, explicitly** — three of the four probes in
    /// `ProbeSet` take the String branch, so the object branch has exactly one route to coverage.
    func testImageSizeEmitsAPresetStringOrADimensionObject() {
        var p = ModelParameters()
        p.imageSizeMode = "preset"; p.imageSizePreset = "square_hd"
        XCTAssertEqual(imageSize(Self.sharedSpec, p) as? String, "square_hd")

        p.imageSizeMode = "custom"; p.customWidth = 1280; p.customHeight = 720
        XCTAssertEqual(imageSize(Self.sharedSpec, p) as? [String: Int], ["width": 1280, "height": 720])
    }

    /// A nil mode reads as "preset" in all 16 builders; a nil preset and nil dimensions take the
    /// model's own fallbacks.
    ///
    /// This was pinned directly against `LegacyPayload.imageSizeValue` until Task 11 deleted it. The
    /// shared spec's behaviour is still covered against the real legacy helper — every probe of the
    /// `wanImage` / `wanImageEdit` recordings in `GoldenPayloads` was produced by it — so what is
    /// left here is the readable statement of the same fallbacks.
    func testImageSizeTakesTheModelsOwnFallbacks() {
        let fresh = ModelParameters()
        XCTAssertEqual(imageSize(Self.sharedSpec, fresh) as? String, "landscape_4_3")
        var custom = ModelParameters(); custom.imageSizeMode = "custom"
        XCTAssertEqual(imageSize(Self.sharedSpec, custom) as? [String: Int], ["width": 1024, "height": 1024])
    }

    /// The other five variants. Each one is a real builder that would have been silently rewritten had
    /// `Control.imageSize` stayed a single hard-coded helper.
    func testImageSizeCarriesEachModelsOwnFallbacksAndArithmetic() {
        var custom = ModelParameters(); custom.imageSizeMode = "custom"

        // Flux t2i family: a 768px *height* fallback where everyone else uses 1024.
        let flux = ImageSizeSpec(presets: Self.sharedSpec.presets, presetFallback: "landscape_4_3",
                                 dimensions: [512, 768, 1024, 1280, 1536],
                                 widthFallback: 1024, heightFallback: 768)
        XCTAssertEqual(imageSize(flux, custom) as? [String: Int], ["width": 1024, "height": 768])

        // Recraft / Seedream v4 / Hunyuan / SD: the square_hd preset fallback.
        let squareHD = ImageSizeSpec(presets: Self.sharedSpec.presets, presetFallback: "square_hd",
                                     dimensions: [768, 1024, 1280, 1536],
                                     widthFallback: 1024, heightFallback: 1024)
        XCTAssertEqual(imageSize(squareHD, ModelParameters()) as? String, "square_hd")

        // Seedream 4.5: a 2K preset fallback, 2048 dimensions, and a 1440 floor on each side.
        let seedream45 = ImageSizeSpec(presets: ["2K", "4K"], presetFallback: "2K",
                                       dimensions: [1440, 2048, 4096],
                                       widthFallback: 2048, heightFallback: 2048,
                                       minimumDimension: 1440)
        XCTAssertEqual(imageSize(seedream45, ModelParameters()) as? String, "2K")
        XCTAssertEqual(imageSize(seedream45, custom) as? [String: Int], ["width": 2048, "height": 2048])
        var undersized = custom; undersized.customWidth = 512; undersized.customHeight = 4096
        XCTAssertEqual(imageSize(seedream45, undersized) as? [String: Int], ["width": 1440, "height": 4096])

        // Flux 2 Pro: round each side up to a multiple of 32, then drop the key entirely over 2048.
        let flux2Pro = ImageSizeSpec(presets: Self.sharedSpec.presets, presetFallback: "landscape_4_3",
                                     dimensions: [512, 768, 1024, 1536, 2048],
                                     widthFallback: 1024, heightFallback: 1024,
                                     roundUpToMultipleOf: 32, maximumDimension: 2048)
        var odd = custom; odd.customWidth = 1280; odd.customHeight = 720
        XCTAssertEqual(imageSize(flux2Pro, odd) as? [String: Int], ["width": 1280, "height": 736],
                       "720 is not a multiple of 32 and must round up to 736")
        var oversized = custom; oversized.customWidth = 4096; oversized.customHeight = 1024
        XCTAssertNil(imageSize(flux2Pro, oversized),
                     "over 2048 the legacy builder emits no image_size at all — it does not clamp")
    }

    // MARK: - The emit guards

    /// `if let x = params.f, x != v` — Kling Image O1 and Gemini 3 Pro send nothing when the control
    /// sits at the value they treat as the default.
    func testANotEqualToGuardDropsTheRowAtThatValue() {
        let d = ParamDescriptor(wireKey: "aspect_ratio", field: .aspectRatio, label: "Aspect Ratio",
                                help: nil, control: .picker(options: [.string("1:1")], style: .menu),
                                defaultValue: .string("1:1"), visibleWhen: nil, alwaysEmit: false,
                                emitWhen: .notEqualTo(.string("1:1")))
        var p = ModelParameters(); p.aspectRatio = "1:1"
        XCTAssertNil(ParamEncoder.encode([d], params: p, context: ctx())["aspect_ratio"])
        p.aspectRatio = "16:9"
        XCTAssertEqual(ParamEncoder.encode([d], params: p, context: ctx())["aspect_ratio"] as? String, "16:9")
    }

    /// `if let n = params.numImages, n > 1` and `if let seed = params.seed, seed >= 1`.
    func testAnAtLeastGuardDropsTheRowBelowItsThreshold() {
        let d = ParamDescriptor(wireKey: "num_images", field: .numImages, label: "Number of Images",
                                help: nil, control: .picker(options: [.int(1)], style: .menu),
                                defaultValue: .int(1), visibleWhen: nil, alwaysEmit: false,
                                emitWhen: .atLeast(2))
        var p = ModelParameters(); p.numImages = 1
        XCTAssertNil(ParamEncoder.encode([d], params: p, context: ctx())["num_images"])
        p.numImages = 2
        XCTAssertEqual(ParamEncoder.encode([d], params: p, context: ctx())["num_images"] as? Int, 2)
    }

    // MARK: - The ParamField bridge

    /// `ParamField` is a 41-case get/set bridge over `ModelParameters` that nothing else verifies. One
    /// swapped case would silently corrupt one model's payload and pass every other test.
    func testEveryParamFieldRoundTripsThroughItsOwnAccessor() {
        for field in ParamField.allCases {
            var p = ModelParameters()
            guard let probe = field.probeValue else { XCTFail("no probe for \(field)"); continue }
            p[field] = probe
            XCTAssertEqual(p[field], probe, "\(field) does not read back what it wrote")
        }
        XCTAssertEqual(ParamField.allCases.count, 42)
    }

    func testNoTwoParamFieldsWriteTheSameStorage() {
        for a in ParamField.allCases {
            var p = ModelParameters()
            p[a] = a.probeValue!
            let touched = ParamField.allCases.filter { p[$0] != ModelParameters()[$0] }
            XCTAssertEqual(touched, [a], "\(a) also changed \(touched.filter { $0 != a })")
        }
    }

    /// Every probe must differ from the struct default, or the aliasing test above is vacuous for
    /// that field.
    func testEveryProbeValueDiffersFromTheStructDefault() {
        let fresh = ModelParameters()
        for field in ParamField.allCases {
            XCTAssertNotEqual(field.probeValue, fresh[field], "\(field)'s probe equals its struct default")
        }
    }

    func testEveryParamFieldsKindMatchesTheValueItStores() {
        for field in ParamField.allCases {
            XCTAssertEqual(field.kind, field.probeValue?.kind, "\(field) declares a kind its storage does not accept")
        }
    }

    /// A type-mismatched write must be ignored, not applied as nil — otherwise a table with one wrong
    /// `ParamValue` case would erase a user's setting instead of failing loudly in the harness.
    func testAMismatchedWriteIsIgnoredRatherThanClearingTheField() {
        var p = ModelParameters(); p.duration = 7
        p[.duration] = .string("8s")
        XCTAssertEqual(p.duration, 7)
    }

    /// `wireKey` and `field` are independent by construction: `cfg_scale` stores into `guidanceScale`
    /// for Kling 2.5-turbo but into `cfgScale` for the other Kling models.
    func testTheSameWireKeyCanAddressTwoDifferentFields() {
        var p = ModelParameters(); p.guidanceScale = 0.7; p.cfgScale = 0.3
        let turbo = ParamDescriptor(wireKey: "cfg_scale", field: .guidanceScale, label: "CFG", help: nil,
                                    control: .slider(range: 0...1, step: 0.1), defaultValue: nil,
                                    visibleWhen: nil, alwaysEmit: false)
        let other = ParamDescriptor(wireKey: "cfg_scale", field: .cfgScale, label: "CFG", help: nil,
                                    control: .slider(range: 0...1, step: 0.1), defaultValue: nil,
                                    visibleWhen: nil, alwaysEmit: false)
        XCTAssertEqual(ParamEncoder.encode([turbo], params: p, context: ctx())["cfg_scale"] as? Double, 0.7)
        XCTAssertEqual(ParamEncoder.encode([other], params: p, context: ctx())["cfg_scale"] as? Double, 0.3)
    }

    // MARK: - emitClamp (Task 8)

    /// `googleVeo31I2VFastJSONBuilder` sends `duration: 8` when the stored duration is 5, so a table
    /// that emitted the stored value would fail equivalence on the very first probe.
    private func durationClampedToVeoDurations() -> ParamDescriptor {
        ParamDescriptor(wireKey: "duration", field: .duration, label: "Duration", help: nil,
                        control: .picker(options: [.int(4), .int(6), .int(8)], style: .menu),
                        defaultValue: .int(8), visibleWhen: nil, alwaysEmit: false,
                        emitClamp: EmitClamp([.init(allowed: [.int(4), .int(6), .int(8)], fallback: .int(8))]))
    }

    func testAnAllowedValuePassesTheClampUntouched() {
        var p = ModelParameters(); p.duration = 6
        XCTAssertEqual(ParamEncoder.encode([durationClampedToVeoDurations()], params: p, context: ctx())["duration"] as? Int, 6)
    }

    func testADisallowedValueIsReplacedByTheClampsFallback() {
        var p = ModelParameters(); p.duration = 5
        XCTAssertEqual(ParamEncoder.encode([durationClampedToVeoDurations()], params: p, context: ctx())["duration"] as? Int, 8)
    }

    /// A clamp never *creates* a key: the emit decision is still "the field is non-nil, or
    /// `alwaysEmit`". Otherwise every clamped row would ship on the all-nil probe.
    func testAClampDoesNotEmitARowWhoseFieldIsNil() {
        var p = ModelParameters(); p.duration = nil
        XCTAssertNil(ParamEncoder.encode([durationClampedToVeoDurations()], params: p, context: ctx())["duration"])
    }

    /// Veo's aspect ratio allows 1:1 only at 720p — two rules, first match wins.
    func testAConditionalClampRulePicksItsAllowedSetFromAnotherField() {
        let d = ParamDescriptor(
            wireKey: "aspect_ratio", field: .aspectRatio, label: "Aspect Ratio", help: nil,
            control: .picker(options: [.string("16:9")], style: .menu), defaultValue: .string("16:9"),
            visibleWhen: nil, alwaysEmit: false,
            emitClamp: EmitClamp([
                .init(when: .fieldEquals(.resolution, .string("720p")),
                      allowed: [.string("16:9"), .string("9:16"), .string("1:1")], fallback: .string("16:9")),
                .init(allowed: [.string("16:9"), .string("9:16")], fallback: .string("16:9"))
            ]))
        var at720 = ModelParameters(); at720.resolution = "720p"; at720.aspectRatio = "1:1"
        XCTAssertEqual(ParamEncoder.encode([d], params: at720, context: ctx())["aspect_ratio"] as? String, "1:1")

        var at1080 = ModelParameters(); at1080.resolution = "1080p"; at1080.aspectRatio = "1:1"
        XCTAssertEqual(ParamEncoder.encode([d], params: at1080, context: ctx())["aspect_ratio"] as? String, "16:9")
    }

    // MARK: - The Kling camera-control composite (Task 8)

    private let cameraControl = ParamDescriptor(
        wireKey: "camera_control", field: .cameraControl, label: "Camera Control", help: nil,
        control: .custom(.klingCameraControl), defaultValue: .string("none"), visibleWhen: nil,
        alwaysEmit: false)

    func testCameraControlEmitsAPresetNameAsABareString() {
        var p = ModelParameters(); p.cameraControl = "down_back"
        XCTAssertEqual(ParamEncoder.encode([cameraControl], params: p, context: ctx())["camera_control"] as? String, "down_back")
    }

    func testCameraControlEmitsNothingForNoneOrNil() {
        var none = ModelParameters(); none.cameraControl = "none"
        XCTAssertNil(ParamEncoder.encode([cameraControl], params: none, context: ctx())["camera_control"])
        XCTAssertNil(ParamEncoder.encode([cameraControl], params: ModelParameters(), context: ctx())["camera_control"])
    }

    func testAdvancedCameraControlEmitsAMovementObject() {
        var p = ModelParameters()
        p.cameraControl = "advanced"; p.cameraMovementType = "zoom"; p.cameraMovementValue = -4
        let object = ParamEncoder.encode([cameraControl], params: p, context: ctx())["camera_control"] as? [String: Any]
        XCTAssertEqual(object?["movement_type"] as? String, "zoom")
        XCTAssertEqual(object?["movement_value"] as? Int, -4)
    }

    /// The legacy builder's advanced branch is `if let type, let value` — a half-configured advanced
    /// mode emits nothing at all rather than a partial object.
    func testAdvancedCameraControlEmitsNothingWhenEitherMovementFieldIsNil() {
        var p = ModelParameters(); p.cameraControl = "advanced"; p.cameraMovementType = "zoom"
        XCTAssertNil(ParamEncoder.encode([cameraControl], params: p, context: ctx())["camera_control"])
    }
}
