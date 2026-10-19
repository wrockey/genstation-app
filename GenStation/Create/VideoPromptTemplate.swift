// VideoPromptTemplate.swift
// Data models for video prompt templates and form fields

import Foundation
import GenStationCore

// MARK: - Video Prompt Template

struct VideoPromptTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let suggestedSubject: String
    let suggestedAction: String
    let suggestedCamera: String
    let suggestedMood: String
    let suggestedLighting: String

    static let allTemplates: [VideoPromptTemplate] = [
        .cinematic,
        .productShowcase,
        .characterAnimation,
        .natureLandscape,
        .abstractArt,
        .socialMedia
    ]

    // MARK: - Predefined Templates

    static let cinematic = VideoPromptTemplate(
        id: "cinematic",
        name: "Cinematic Scene",
        icon: "film",
        description: "Epic movie-quality footage with dramatic camera work",
        suggestedSubject: "A lone figure standing at the edge of a cliff",
        suggestedAction: "gazing at the horizon as wind sweeps through their hair",
        suggestedCamera: "slow push-in",
        suggestedMood: "epic",
        suggestedLighting: "golden_hour"
    )

    static let productShowcase = VideoPromptTemplate(
        id: "product",
        name: "Product Showcase",
        icon: "cube.box",
        description: "Clean, professional product reveal and rotation",
        suggestedSubject: "A sleek modern smartphone",
        suggestedAction: "rotating slowly on a reflective surface",
        suggestedCamera: "orbital",
        suggestedMood: "calm",
        suggestedLighting: "studio"
    )

    static let characterAnimation = VideoPromptTemplate(
        id: "character",
        name: "Character Animation",
        icon: "person.fill",
        description: "Animated character performing an action",
        suggestedSubject: "An animated cartoon fox",
        suggestedAction: "dancing joyfully with arms raised",
        suggestedCamera: "static",
        suggestedMood: "playful",
        suggestedLighting: "soft"
    )

    static let natureLandscape = VideoPromptTemplate(
        id: "nature",
        name: "Nature & Landscape",
        icon: "mountain.2",
        description: "Breathtaking natural scenery with ambient motion",
        suggestedSubject: "A misty mountain valley",
        suggestedAction: "with clouds slowly drifting through the peaks",
        suggestedCamera: "drone",
        suggestedMood: "peaceful",
        suggestedLighting: "natural"
    )

    static let abstractArt = VideoPromptTemplate(
        id: "abstract",
        name: "Abstract & Artistic",
        icon: "paintpalette",
        description: "Creative, experimental visuals with flowing motion",
        suggestedSubject: "Colorful liquid forms",
        suggestedAction: "morphing and flowing into each other",
        suggestedCamera: "static",
        suggestedMood: "mysterious",
        suggestedLighting: "neon"
    )

    static let socialMedia = VideoPromptTemplate(
        id: "social",
        name: "Social Media",
        icon: "sparkles.rectangle.stack",
        description: "Short, eye-catching clips for social platforms",
        suggestedSubject: "A trendy coffee cup with latte art",
        suggestedAction: "with steam rising, being picked up by a hand",
        suggestedCamera: "push_in",
        suggestedMood: "energetic",
        suggestedLighting: "natural"
    )
}

// MARK: - Camera Movement Options

struct CameraMovement: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String

    static let allMovements: [CameraMovement] = [
        CameraMovement(id: "static", name: "Static", description: "Camera remains fixed"),
        CameraMovement(id: "pan_left", name: "Pan Left", description: "Horizontal rotation left"),
        CameraMovement(id: "pan_right", name: "Pan Right", description: "Horizontal rotation right"),
        CameraMovement(id: "tilt_up", name: "Tilt Up", description: "Vertical rotation upward"),
        CameraMovement(id: "tilt_down", name: "Tilt Down", description: "Vertical rotation downward"),
        CameraMovement(id: "push_in", name: "Push In / Dolly In", description: "Camera moves toward subject"),
        CameraMovement(id: "pull_out", name: "Pull Out / Dolly Out", description: "Camera moves away from subject"),
        CameraMovement(id: "tracking", name: "Tracking Shot", description: "Camera follows subject movement"),
        CameraMovement(id: "orbital", name: "Orbital / Arc", description: "Camera circles around subject"),
        CameraMovement(id: "crane_up", name: "Crane Up", description: "Camera rises vertically"),
        CameraMovement(id: "crane_down", name: "Crane Down", description: "Camera descends vertically"),
        CameraMovement(id: "zoom_in", name: "Zoom In", description: "Lens zooms closer"),
        CameraMovement(id: "zoom_out", name: "Zoom Out", description: "Lens zooms wider"),
        CameraMovement(id: "handheld", name: "Handheld", description: "Slight natural shake"),
        CameraMovement(id: "steadicam", name: "Steadicam / Gimbal", description: "Smooth floating motion"),
        CameraMovement(id: "drone", name: "Aerial / Drone", description: "Bird's eye view movement")
    ]
}

// MARK: - Style Presets for Video

struct VideoStylePreset: Identifiable, Hashable {
    let id: String
    let name: String

    static let allStyles: [VideoStylePreset] = [
        VideoStylePreset(id: "cinematic", name: "Cinematic"),
        VideoStylePreset(id: "documentary", name: "Documentary"),
        VideoStylePreset(id: "anime", name: "Anime"),
        VideoStylePreset(id: "3d_render", name: "3D Render"),
        VideoStylePreset(id: "photorealistic", name: "Photorealistic"),
        VideoStylePreset(id: "stylized", name: "Stylized"),
        VideoStylePreset(id: "vintage", name: "Vintage / Retro"),
        VideoStylePreset(id: "noir", name: "Film Noir"),
        VideoStylePreset(id: "fantasy", name: "Fantasy"),
        VideoStylePreset(id: "scifi", name: "Sci-Fi"),
        VideoStylePreset(id: "minimalist", name: "Minimalist"),
        VideoStylePreset(id: "surreal", name: "Surreal / Dreamlike")
    ]
}

// MARK: - Mood Options

struct VideoMood: Identifiable, Hashable {
    let id: String
    let name: String

    static let allMoods: [VideoMood] = [
        VideoMood(id: "dramatic", name: "Dramatic"),
        VideoMood(id: "peaceful", name: "Peaceful"),
        VideoMood(id: "energetic", name: "Energetic"),
        VideoMood(id: "mysterious", name: "Mysterious"),
        VideoMood(id: "joyful", name: "Joyful"),
        VideoMood(id: "melancholic", name: "Melancholic"),
        VideoMood(id: "tense", name: "Tense / Suspenseful"),
        VideoMood(id: "romantic", name: "Romantic"),
        VideoMood(id: "epic", name: "Epic"),
        VideoMood(id: "calm", name: "Calm"),
        VideoMood(id: "playful", name: "Playful"),
        VideoMood(id: "dark", name: "Dark / Ominous")
    ]
}

// MARK: - Lighting Options

struct VideoLighting: Identifiable, Hashable {
    let id: String
    let name: String

    static let allLighting: [VideoLighting] = [
        VideoLighting(id: "natural", name: "Natural Light"),
        VideoLighting(id: "golden_hour", name: "Golden Hour"),
        VideoLighting(id: "blue_hour", name: "Blue Hour"),
        VideoLighting(id: "studio", name: "Studio Lighting"),
        VideoLighting(id: "dramatic", name: "Dramatic / Chiaroscuro"),
        VideoLighting(id: "soft", name: "Soft / Diffused"),
        VideoLighting(id: "neon", name: "Neon / RGB"),
        VideoLighting(id: "candlelight", name: "Candlelight / Warm"),
        VideoLighting(id: "moonlight", name: "Moonlight"),
        VideoLighting(id: "overcast", name: "Overcast"),
        VideoLighting(id: "backlit", name: "Backlit / Silhouette"),
        VideoLighting(id: "high_key", name: "High Key (Bright)"),
        VideoLighting(id: "low_key", name: "Low Key (Dark)")
    ]
}

// MARK: - Video Prompt Guidance

/// Prompt-writing guidance for the Video Prompt Helper sheet. This replaces the old per-model-info
/// type, which also carried `displayName` (a second, substring-derived copy of the catalog's
/// presentation data), an image-to-video flag, a max-duration and an id. Stage 3 moved `displayName`
/// to `CatalogModel` — which now takes it from the API's own `info.name` — and deleted the other
/// three; they had no readers.
///
/// What is left is genuinely per-family prose, and it is still selected by substring match. That is
/// deliberate and it is remaining drift: the tips are guidance text, not identity, and
/// `CatalogModel` has no `tips` field to move them to. `guidance(for:)` cannot return nil, which is
/// what the old type's lookup also did in practice through its unconditional fallback.
struct VideoPromptGuidance {
    let supportsAudio: Bool
    let tips: [String]

    static func guidance(for modelId: String) -> VideoPromptGuidance {
        if let guide = VideoWorkflowGuide.guide(for: modelId) {
            return VideoPromptGuidance(supportsAudio: guide.supportsAudio, tips: guide.tips)
        }
        let lower = modelId.lowercased()

        // Google Veo models (all Veo 3.x support audio)
        if lower.contains("veo") {
            let isI2V = lower.contains("i2v") || lower.contains("image-to-video")
            let isFirstLast = lower.contains("first-last")
            let isReference = lower.contains("reference")

            var tips = [
                "Supports audio generation - describe sounds in your prompt",
                "Use detailed descriptions of motion and timing"
            ]

            if isFirstLast {
                tips.append("Requires 2 images: first frame and last frame")
            } else if isReference {
                tips.append("Use reference image to guide style")
            } else if isI2V {
                tips.append("Input image determines the starting frame")
            }

            tips.append("720p supports 1:1 aspect ratio; 1080p only 16:9 or 9:16")

            return VideoPromptGuidance(supportsAudio: true, tips: tips)
        }

        // OpenAI Sora 2 Pro I2V
        if lower.contains("sora") && lower.contains("i2v") {
            return VideoPromptGuidance(
                supportsAudio: true,
                tips: [
                    "Includes synchronized audio generation",
                    "Input image must match exact resolution (1280x720 or 1792x1024)",
                    "~1.5 minute processing time",
                    "Durations: 4s, 8s, or 12s only"
                ]
            )
        }

        // Alibaba Wan T2V models
        if lower.contains("wan") && (lower.contains("t2v") || lower.contains("text-to-video")) {
            let isWan26 = lower.contains("2.6") || lower.contains("26") || lower.contains("2-6")
            let isWan25 = lower.contains("2.5") || lower.contains("25") || lower.contains("2-5")
            let hasAudio = isWan25 || isWan26

            return VideoPromptGuidance(
                supportsAudio: hasAudio,
                tips: hasAudio ? [
                    "Supports native audio generation - describe sounds in your prompt",
                    "Multi-shot mode available for cinematic storytelling",
                    "Clear subject descriptions work best",
                    "Supports negative prompts for refinement"
                ] : [
                    "Best for stylized and artistic video generation",
                    "No audio - consider adding music in post",
                    "Clear subject descriptions work best",
                    "Supports negative prompts for refinement"
                ]
            )
        }

        // Alibaba Wan I2V
        if lower.contains("wan") && lower.contains("i2v") {
            let isWan26 = lower.contains("2.6") || lower.contains("26") || lower.contains("2-6")
            let isWan25 = lower.contains("2.5") || lower.contains("25") || lower.contains("2-5")
            let hasAudio = isWan25 || isWan26

            return VideoPromptGuidance(
                supportsAudio: hasAudio,
                tips: hasAudio ? [
                    "Animates a static image with native audio",
                    "Describe sounds alongside the motion you want",
                    "Works best with clear subjects",
                    "Can sync to provided audio via audio_url parameter"
                ] : [
                    "Animates a static image",
                    "Describe the motion you want to add",
                    "Works best with clear subjects",
                    "No audio generation"
                ]
            )
        }

        // Kling models
        if lower.contains("kling") {
            let isI2V = lower.contains("i2v") || lower.contains("image-to-video")
            let isKlingV3 = lower.contains("-v3-") || lower.contains("v3-")
            let isKling26 = lower.contains("2-6") || lower.contains("2.6") || lower.contains("v2-6")
            let isKlingO1 = lower.contains("-o1-") || lower.contains("o1-")
            let hasAudio = isKling26 || isKlingO1 || isKlingV3

            return VideoPromptGuidance(
                supportsAudio: hasAudio,
                tips: isKlingV3 ? [
                    "3-15s duration, native audio (Chinese + English)",
                    "Multi-shot: separate scenes with line breaks in prompt (up to 6)",
                    isI2V ? "First image = start frame, second image = end frame" : "Strong at realistic human motion",
                    "Pro tier: higher fidelity and richer detail"
                ] : hasAudio ? [
                    "Supports native audio generation - describe sounds",
                    "Strong at realistic human motion",
                    "Supports camera control parameters",
                    "Good for product videos"
                ] : [
                    "Strong at realistic human motion",
                    "Supports camera control parameters",
                    "Good for product videos",
                    "No audio - add separately"
                ]
            )
        }

        // PixVerse models (V5.5 supports optional audio)
        if lower.contains("pixverse") {
            return VideoPromptGuidance(
                supportsAudio: true,
                tips: [
                    "Supports optional audio generation",
                    "Multiple style presets: anime, 3D, comic, cyberpunk",
                    "Up to 1080p resolution",
                    "Negative prompt support for refinement"
                ]
            )
        }

        // MiniMax models
        if lower.contains("minimax") || lower.contains("hailuo") {
            return VideoPromptGuidance(
                supportsAudio: false,
                tips: [
                    "Requires first frame image",
                    "Good for character animations",
                    "Describe motion direction clearly",
                    "No audio generation"
                ]
            )
        }

        // LTX models (LTX V2 supports audio)
        if lower.contains("ltx") {
            let isV2 = lower.contains("ltxv-2") || lower.contains("ltxv/ltxv-2") || lower.contains("v2")
            return VideoPromptGuidance(
                supportsAudio: isV2,
                tips: isV2 ? [
                    "Supports audio generation - describe sounds",
                    "Up to 4K resolution (2160p)",
                    "First frame image optional",
                    "Fast processing: 1-2 minutes"
                ] : [
                    "Fast video generation",
                    "Good for quick iterations",
                    "Works well with simple prompts",
                    "No audio generation"
                ]
            )
        }

        // Default guidance for models with no family-specific tips
        return VideoPromptGuidance(
            supportsAudio: false,
            tips: [
                "Describe your scene clearly",
                "Include motion and action details",
                "Specify camera movement if desired"
            ]
        )
    }
}
