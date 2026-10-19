// Golden MCP schema fixtures (Stage 2, Task 11).
//
// `MCPService.paramSchema(for:)` is **both** the schema `list_models` advertises and the agent
// validation gate — a `generate_image` / `generate_video` call is rejected for any `params` key
// absent from it. Task 10b's rule was: publish richer schema if you like, but do **not** narrow
// the gate, because rejecting a key an agent may send today is a user-visible change that needs
// its own release note.
//
// This is the pre-Task-10b schema, synthesized from the legacy builder/parser pair and recorded
// at `92e07cf` before they were deleted. `MCPSchemaGateTests` asserts the descriptor path still
// produces the same key set (the gate) and the same values (the advertisement), for all 209 ids.
//
// GENERATED. Do not hand-edit — this file is the definition of "as permissive as it used to be".

import Foundation

enum GoldenSchemas {

    /// Table name -> the schema `list_models` advertised, and the key set the agent
    /// validation gate accepted, before Task 10b.
    static let byTable: [String: [String: Any]] = [
        "alibabaQwenImage": [
            "enable_safety_checker": true,
            "guidance_scale": 7.5,
            "negative_prompt": "sample",
            "num_images": 1,
            "seed": 0,
        ],
        "alibabaQwenImageEdit": [
            "negative_prompt": "sample",
            "watermark": false,
        ],
        "alibabaWan21T2VPlus": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "negative_prompt": "sample",
            "resolution": "720P",
            "seed": 0,
            "watermark": false,
        ],
        "alibabaWan21T2VTurbo": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "negative_prompt": "sample",
            "resolution": "720P",
            "seed": 0,
            "watermark": false,
        ],
        "alibabaWan25T2VPreview": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "sample",
            "resolution": "720p",
            "seed": 0,
        ],
        "flux2Pro": [
            "enable_safety_checker": true,
            "image_size": "landscape_4_3",
            "safety_tolerance": "2",
        ],
        "flux2ProEdit": [
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "image_size": "landscape_4_3",
            "safety_tolerance": "2",
        ],
        "fluxDev": [
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "image_size": "landscape_4_3",
            "num_images": 1,
            "num_inference_steps": 50,
            "seed": 0,
        ],
        "fluxKontextMaxI2i": [
            "aspect_ratio": "16:9",
            "guidance_scale": 3.5,
            "num_images": 1,
            "safety_tolerance": "2",
            "seed": 0,
        ],
        "fluxKontextMaxT2i": [
            "aspect_ratio": "1:1",
            "guidance_scale": 3.5,
            "num_images": 1,
            "safety_tolerance": "2",
            "seed": 0,
        ],
        "fluxKontextProI2i": [
            "aspect_ratio": "16:9",
            "guidance_scale": 3.5,
            "num_images": 1,
            "safety_tolerance": "2",
            "seed": 0,
        ],
        "fluxKontextProT2i": [
            "aspect_ratio": "16:9",
            "guidance_scale": 3.5,
            "num_images": 1,
            "safety_tolerance": "2",
            "seed": 0,
        ],
        "fluxPro": [
            "guidance_scale": 3.5,
            "image_size": "landscape_4_3",
            "num_images": 1,
            "num_inference_steps": 50,
            "safety_tolerance": "2",
            "seed": 0,
        ],
        "fluxRealism": [
            "enable_safety_checker": true,
            "guidance_scale": 4.5,
            "image_size": "landscape_4_3",
            "num_images": 1,
            "num_inference_steps": 50,
            "seed": 0,
        ],
        "fluxSchnell": [
            "enable_safety_checker": true,
            "image_size": "landscape_4_3",
            "num_images": 1,
            "num_inference_steps": 4,
            "seed": 0,
        ],
        "fluxSrpo": [
            "enable_safety_checker": true,
            "guidance_scale": 4.5,
            "image_size": "landscape_4_3",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
        ],
        "fluxSrpoI2i": [
            "acceleration": "regular",
            "enable_safety_checker": true,
            "guidance_scale": 4.5,
            "image_size": "landscape_4_3",
            "num_images": 1,
            "num_inference_steps": 40,
            "seed": 0,
            "strength": 0.95,
        ],
        "gemini25FlashImage": [:],
        "gemini25FlashImageEdit": [
            "num_images": 1,
        ],
        "gemini3ProImagePreview": [
            "aspect_ratio": "16:9",
        ],
        "gemini3ProImagePreviewEdit": [
            "aspect_ratio": "16:9",
        ],
        "googleImagen4Ultra": [
            "add_watermark": false,
            "aspect_ratio": "1:1",
            "enhance_prompt": true,
            "num_images": 1,
            "seed": 0,
        ],
        "googleVeo31I2VFastVeo30": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "1080p",
        ],
        "googleVeo31I2VFastVeo31": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "1080p",
        ],
        "googleVeo3T2V": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "enhance_prompt": true,
            "generate_audio": true,
            "negative_prompt": "sample",
            "resolution": "720P",
            "seed": 0,
        ],
        "grokImagine": [
            "aspect_ratio": "16:9",
            "n": 1,
            "resolution": "2k",
            "seed": 0,
        ],
        "hailuo23": [
            "duration": 6,
            "enhance_prompt": true,
            "resolution": "768P",
        ],
        "hunyuanImageV3": [
            "enable_prompt_expansion": true,
            "enable_safety_checker": true,
            "guidance_scale": 7.5,
            "image_size": "square_hd",
            "negative_prompt": "sample",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
        ],
        "kandinskyVideo": [
            "aspect_ratio": "3:2",
            "duration": 5,
            "num_inference_steps": 30,
        ],
        "kling26": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
            "generate_audio": true,
            "negative_prompt": "sample",
        ],
        "klingImageO1": [
            "resolution": "720p",
        ],
        "klingV3": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
            "generate_audio": true,
            "negative_prompt": "sample",
        ],
        "klingVideo": [
            "aspect_ratio": "16:9",
            "camera_control": "{}",
            "cfg_scale": 0.5,
            "duration": 5,
            "negative_prompt": "sample",
        ],
        "klingv25TurboVideo": [
            "cfg_scale": 0.5,
            "duration": 5,
            "negative_prompt": "sample",
        ],
        "ltxv2": [
            "aspect_ratio": "16:9",
            "duration": 6,
            "fps": 25,
            "generate_audio": true,
            "resolution": "1080p",
        ],
        "lumaRay2": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "loop": false,
            "resolution": "1080p",
        ],
        "minimaxHailuo02": [
            "duration": 6,
            "enhance_prompt": true,
            "resolution": "768P",
        ],
        "minimaxVideo01": [
            "enhance_prompt": true,
        ],
        // Task 5 addition (2026-08-11): recorded from the descriptor path itself (`descriptorSchema`
        // in `MCPSchemaGateTests`), not from a legacy builder/parser pair — there is none for these
        // ids. Both rows resolve the same way regardless of `isI2I`, and to the same value on the
        // struct-default, fully-populated and enum-example passes alike.
        "nanoBanana2": [
            "aspect_ratio": "16:9",
            "resolution": "1K",
        ],
        "nanoBanana2Lite": [
            "aspect_ratio": "16:9",
            "resolution": "1K",
        ],
        "noParameters": [:],
        "omniHuman": [
            "audio_url": "https://example.com/audio.mp3",
        ],
        "openAIGPTImage1": [
            "background": "auto",
            "quality": "medium",
            "size": "1024x1024",
        ],
        "openAIGPTImage1Extended": [
            "background": "auto",
            "moderation": "auto",
            "output_format": "png",
            "quality": "medium",
            "size": "1024x1024",
        ],
        "pixVerseV55T2V": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "generate_audio_switch": false,
            "negative_prompt": "sample",
            "resolution": "720p",
            "seed": 0,
            "style": "realistic",
        ],
        "recraftV3": [
            "image_size": "square_hd",
            "style": "realistic_image",
        ],
        "reveImage": [
            "aspect_ratio": "3:2",
        ],
        "runwayGen3Turbo": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "seed": 0,
        ],
        "runwayGen4": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "seed": 0,
        ],
        "runwayGen4Aleph": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "seed": 0,
        ],
        "seedance10Pro": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "1080p",
            "seed": 0,
        ],
        "seedance20": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "generate_audio": true,
            "resolution": "720p",
            "seed": 0,
        ],
        "seedanceVideo": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "1080p",
            "seed": 0,
        ],
        "seedream45": [
            "image_size": "2K",
            "seed": 0,
            "watermark": false,
        ],
        // Task 6 addition (2026-08-11), recorded from the same `descriptorSchema` algorithm as
        // every row above — no legacy builder/parser pair exists for this id either.
        "seedream50Pro": [
            "image_size": "1.5K",
            "seed": 0,
            "watermark": false,
        ],
        "seedreamV4": [
            "enable_safety_checker": true,
            "image_size": "square_hd",
            "num_images": 1,
            "seed": 0,
        ],
        "seedreamV4Edit": [
            "enable_safety_checker": true,
            "image_size": "square_hd",
            "num_images": 1,
            "seed": 0,
        ],
        "sora2": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "resolution": "720p",
        ],
        "sora2ProI2V": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "resolution": "1080p",
        ],
        "stableDiffusionV35Large": [
            "enable_safety_checker": true,
            "guidance_scale": 4.5,
            "image_size": "square_hd",
            "negative_prompt": "sample",
            "num_images": 1,
            "num_inference_steps": 40,
            "seed": 0,
        ],
        "stableDiffusionV3Medium": [
            "enable_safety_checker": true,
            "guidance_scale": 5.0,
            "image_size": "square_hd",
            "negative_prompt": "sample",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
        ],
        "topazSharpen": [
            "face_enhancement": true,
            "face_enhancement_creativity": 0.0,
            "face_enhancement_strength": 0.8,
            "minor_denoise": 0.25,
            "mode": "Standard",
            "output_format": "png",
            "strength": 0.5,
            "subject_detection": "All",
        ],
        "topazSharpenGen": [
            "face_enhancement": true,
            "face_enhancement_creativity": 0.0,
            "face_enhancement_strength": 0.8,
            "focus_boost": 0.5,
            "mode": "Super Focus",
            "output_format": "png",
            "seed": 0,
            "strength": 0.5,
            "subject_detection": "All",
        ],
        "veo2": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "resolution": "720p",
        ],
        "veoFirstLastFrame": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "1080p",
        ],
        "wan25I2V": [
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "sample",
            "resolution": "720p",
            "seed": 0,
        ],
        "wan26Video": [
            "aspect_ratio": "16:9",
            "duration": 10,
            "enhance_prompt": true,
            "generate_audio": true,
            "negative_prompt": "sample",
            "resolution": "1080p",
            "seed": 0,
            "shot_type": "single",
        ],
        "wan26VideoI2V": [
            "duration": 10,
            "enhance_prompt": true,
            "generate_audio": true,
            "negative_prompt": "sample",
            "resolution": "1080p",
            "seed": 0,
            "shot_type": "single",
        ],
        "wanImage": [
            "enhance_prompt": true,
            "image_size": "landscape_4_3",
            "negative_prompt": "sample",
            "num_images": 1,
            "seed": 0,
            "watermark": false,
        ],
        "wanImageEdit": [
            "enhance_prompt": true,
            "image_size": "landscape_4_3",
            "negative_prompt": "sample",
            "seed": 0,
            "watermark": false,
        ],
    ]
}
