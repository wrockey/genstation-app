// ModelParameters.swift
import Foundation

/// The single parameter bag every AI/ML model's `JSONBuilder` and `ParameterParser` reads and writes.
///
/// Moved verbatim from the app target in Stage 2 — it was `GenStation/Catalog/ModelParameters.swift`,
/// a path that no longer exists (`git show 3eee34c:GenStation/Catalog/` for the last state) — so the
/// legacy payload layer and the Stage 2 descriptor tables can be compared under `swift test`. **Nothing
/// about its behaviour changed in the move** — the 41 stored properties, their types, their defaults
/// and its `CodingKeys` are exactly what the app shipped, including the known drift recorded in the
/// Stage 2 drift ledger (see the note on `CodingKeys` below).
public struct ModelParameters: Codable, Equatable {
    public var seed: Int?
    public var numImages: Int?
    public var enableSafetyChecker: Bool?
    public var negativePrompt: String? = ""
    public var imageSizeMode: String?
    public var imageSizePreset: String?
    public var customWidth: Int?
    public var customHeight: Int?
    public var guidanceScale: Double? = nil
    public var duration: Int? = 5
    public var frameRate: Int? = 30 // Default 30fps for video models
    public var numInferenceSteps: Int? = nil
    public var stylePreset: String? // Optional style preset (e.g., "anime", "realistic")
    public var resolution: String? = "720p" // New: Resolution for models like Veo 3
    public var geminiResolution: String? = "1K"
    public var cameraControl: String? // JSON-like string for camera params (e.g., {"pan": "left"})
    public var generateAudio: Bool? = true // New: Generate audio for video models like Veo 3
    public var strength: Double? = 0.8
    public var watermark: Bool? = false
    public var enhancePrompt: Bool? = true
    public var aspectRatio: String? = "16:9"
    public var acceleration: String? = "regular"
    public var safetyTolerance: String? = "2"
    public var size: String? = "1024x1024"
    public var background: String? = "auto"
    // nil by default; the gpt-image extended parser defaults this to "auto" (docs default).
    public var moderation: String? = nil
    public var quality: String? = "medium"
    public var loop: Bool? = false  // For Luma Ray looping videos
    public var cfgScale: Double? = 0.5  // For Kling cfg_scale (0-1)
    public var cameraMovementType: String?  // For Kling advanced camera control
    public var cameraMovementValue: Int?  // For Kling advanced camera control (-10 to 10)
    public var shotType: String?  // For Wan 2.6 shot type (single/multi)
    public var topazMode: String?  // For Topaz sharpen/sharpen-gen mode
    public var subjectDetection: String?  // For Topaz: All/Foreground/Background
    public var faceEnhancement: Bool?  // For Topaz face enhancement toggle
    public var faceEnhancementCreativity: Double?  // For Topaz face enhancement creativity 0-1
    public var faceEnhancementStrength: Double?  // For Topaz face enhancement strength 0-1
    public var focusBoost: Double?  // For Topaz sharpen-gen focus boost 0.25-1
    public var minorDenoise: Double?  // For Topaz sharpen minor denoise 0.01-1
    public var outputFormat: String?  // For Topaz output format (jpeg/png/tiff)
    public var promptExpansionMode: String? = nil
    public var audioURL: String?  // For OmniHuman audio lip-sync URL

    /// Reproduces the memberwise initializer the compiler synthesized while this struct lived in the
    /// app target. Swift only synthesizes an `internal` memberwise init, so moving the struct into
    /// the package would otherwise have made `ModelParameters()` and the two labelled call sites
    /// (`ConfigurationSection.swift`, `GenStationApp.swift`) unreachable from the app. Every default
    /// here is the property's own declared default, so this init is behaviourally identical to the
    /// synthesized one it replaces — do not "tidy" a default without changing the property too.
    public init(
        seed: Int? = nil,
        numImages: Int? = nil,
        enableSafetyChecker: Bool? = nil,
        negativePrompt: String? = "",
        imageSizeMode: String? = nil,
        imageSizePreset: String? = nil,
        customWidth: Int? = nil,
        customHeight: Int? = nil,
        guidanceScale: Double? = nil,
        duration: Int? = 5,
        frameRate: Int? = 30,
        numInferenceSteps: Int? = nil,
        stylePreset: String? = nil,
        resolution: String? = "720p",
        geminiResolution: String? = "1K",
        cameraControl: String? = nil,
        generateAudio: Bool? = true,
        strength: Double? = 0.8,
        watermark: Bool? = false,
        enhancePrompt: Bool? = true,
        aspectRatio: String? = "16:9",
        acceleration: String? = "regular",
        safetyTolerance: String? = "2",
        size: String? = "1024x1024",
        background: String? = "auto",
        moderation: String? = nil,
        quality: String? = "medium",
        loop: Bool? = false,
        cfgScale: Double? = 0.5,
        cameraMovementType: String? = nil,
        cameraMovementValue: Int? = nil,
        shotType: String? = nil,
        topazMode: String? = nil,
        subjectDetection: String? = nil,
        faceEnhancement: Bool? = nil,
        faceEnhancementCreativity: Double? = nil,
        faceEnhancementStrength: Double? = nil,
        focusBoost: Double? = nil,
        minorDenoise: Double? = nil,
        outputFormat: String? = nil,
        audioURL: String? = nil
    ) {
        self.seed = seed
        self.numImages = numImages
        self.enableSafetyChecker = enableSafetyChecker
        self.negativePrompt = negativePrompt
        self.imageSizeMode = imageSizeMode
        self.imageSizePreset = imageSizePreset
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.guidanceScale = guidanceScale
        self.duration = duration
        self.frameRate = frameRate
        self.numInferenceSteps = numInferenceSteps
        self.stylePreset = stylePreset
        self.resolution = resolution
        self.geminiResolution = geminiResolution
        self.cameraControl = cameraControl
        self.generateAudio = generateAudio
        self.strength = strength
        self.watermark = watermark
        self.enhancePrompt = enhancePrompt
        self.aspectRatio = aspectRatio
        self.acceleration = acceleration
        self.safetyTolerance = safetyTolerance
        self.size = size
        self.background = background
        self.moderation = moderation
        self.quality = quality
        self.loop = loop
        self.cfgScale = cfgScale
        self.cameraMovementType = cameraMovementType
        self.cameraMovementValue = cameraMovementValue
        self.shotType = shotType
        self.topazMode = topazMode
        self.subjectDetection = subjectDetection
        self.faceEnhancement = faceEnhancement
        self.faceEnhancementCreativity = faceEnhancementCreativity
        self.faceEnhancementStrength = faceEnhancementStrength
        self.focusBoost = focusBoost
        self.minorDenoise = minorDenoise
        self.outputFormat = outputFormat
        self.audioURL = audioURL
    }

    // Carried over unchanged. Two known defects live here and are deliberately preserved — they are
    // drift-ledger items for a later, reviewed wave, not something to fix during a file move:
    //   1. `acceleration` has no entry, so it never round-trips (pinned by
    //      `ModelParametersTests.testAccelerationIsAbsentFromCodingKeys`).
    //   2. Several names disagree with the wire keys the JSON builders actually emit
    //      (`frame_rate` vs the real `fps`; `num_images` vs `n` for DALL·E).
    // Neither matters today: nothing in the repo encodes or decodes `ModelParameters`, so `Codable`
    // here is dead code. It is kept because removing it would be an unverifiable behaviour change.
    enum CodingKeys: String, CodingKey {
        case seed
        case numImages = "num_images"
        case enableSafetyChecker = "enable_safety_checker"
        case negativePrompt = "negative_prompt"
        case imageSizeMode
        case imageSizePreset
        case customWidth
        case customHeight
        case guidanceScale = "guidance_scale"
        case duration
        case frameRate = "frame_rate"
        case numInferenceSteps = "num_inference_steps"
        case stylePreset = "style_preset"
        case resolution
        case geminiResolution = "gemini_resolution"
        case cameraControl = "camera_control"
        case generateAudio = "generate_audio"
        case strength
        case watermark
        case enhancePrompt = "enhance_prompt"
        case aspectRatio = "aspect_ratio"
        case safetyTolerance = "safety_tolerance"
        case size
        case background
        case moderation
        case quality
        case loop
        case cfgScale = "cfg_scale"
        case cameraMovementType = "camera_movement_type"
        case cameraMovementValue = "camera_movement_value"
        case shotType = "shot_type"
        case topazMode = "topaz_mode"
        case subjectDetection = "subject_detection"
        case faceEnhancement = "face_enhancement"
        case faceEnhancementCreativity = "face_enhancement_creativity"
        case faceEnhancementStrength = "face_enhancement_strength"
        case focusBoost = "focus_boost"
        case minorDenoise = "minor_denoise"
        case outputFormat = "output_format"
        case audioURL = "audio_url"
    }
}

extension ModelParameters {
    /// Every optional field set to a benign non-nil value, so running a model's
    /// JSONBuilder on it surfaces the complete set of accepted parameter keys —
    /// including those whose real default is nil (seed, negative_prompt,
    /// guidance_scale, …) and so are omitted when the builder runs on defaults.
    /// Used by the MCP layer to build the full parameter schema for validation
    /// and list_models advertisement.
    public static func fullyPopulatedProbe() -> ModelParameters {
        var p = ModelParameters()
        p.seed = 0
        p.numImages = 1
        p.enableSafetyChecker = true
        p.negativePrompt = "sample"
        p.imageSizeMode = "preset"
        p.imageSizePreset = "square_hd"
        p.customWidth = 1024
        p.customHeight = 1024
        p.guidanceScale = 3.5
        p.duration = 5
        p.frameRate = 30
        p.numInferenceSteps = 28
        p.stylePreset = "realistic"
        p.resolution = "720p"
        p.geminiResolution = "1K"
        p.cameraControl = "{}"
        p.generateAudio = true
        p.strength = 0.8
        p.watermark = false
        p.enhancePrompt = true
        p.aspectRatio = "16:9"
        p.acceleration = "regular"
        p.safetyTolerance = "2"
        p.size = "1024x1024"
        p.background = "auto"
        p.moderation = "auto"
        p.quality = "medium"
        p.loop = false
        p.cfgScale = 0.5
        p.cameraMovementType = "zoom"
        p.cameraMovementValue = 0
        p.shotType = "single"
        p.topazMode = "sharpen"
        p.subjectDetection = "All"
        p.faceEnhancement = true
        p.faceEnhancementCreativity = 0.5
        p.faceEnhancementStrength = 0.5
        p.focusBoost = 0.5
        p.minorDenoise = 0.5
        p.outputFormat = "png"
        p.audioURL = "https://example.com/audio.mp3"
        return p
    }
}
