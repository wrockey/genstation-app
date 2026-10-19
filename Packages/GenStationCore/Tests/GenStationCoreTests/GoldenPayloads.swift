// Golden payload fixtures — spec § 5, Phase B (Stage 2, Task 11).
//
// **These are a recording of the LEGACY builders**, taken at `92e07cf`, the last commit before
// `LegacyPayload` was deleted. They are not a recording of `ParamEncoder` agreeing with itself:
// the recorder ran `LegacyPayload.builder(forModelId:)` over `ProbeSet.all` and wrote what it
// returned. `GoldenPayloadTests` then asserts `ParamEncoder` reproduces every one of them.
//
// That is the whole chain of evidence for the migration now that `PayloadEquivalenceTests` is
// gone. Phase A ran live over all 209 ids × 5 probes × 2 contexts and was green; this file is
// what survives it. **Do not regenerate this file from the encoder** — that would make the
// assertion circular and silently destroy the only record of what the app used to send.
//
// Keyed per *table*, with a 209-entry id map, because 209 ids resolve to 67 tables. The recorder
// asserted that every id sharing a table produces the same payload before writing.
//
// Value types are emitted exactly (`5` vs `5.0`): video `duration` is always an Int on the wire
// and `guidance_scale` always a Double, and the assertion compares dynamic types.
//
// GENERATED. Do not hand-edit — hand-editing a golden defeats its purpose.
//
// Stage 3 Task 22 removed the eight rows for ids the captured /models response no longer serves.
// Pure subtraction, never a regeneration: the diff carried zero insertions, so every remaining
// literal is still the one recorded at `92e07cf`. No id in the live history corpus was on that
// list, so no row here was exempted and no catalog row was marked `.dead`.

import Foundation

enum GoldenPayloads {

    /// Probe name -> the payload the legacy builder produced.
    typealias ProbePayloads = [String: [String: Any]]

    /// Every registered model id -> its table's recording. 209 entries; aliases share.
    static let byModelId: [String: ProbePayloads] = [
        "alibaba/happyhorse-1.0-i2v":                    wan26VideoI2V,
        "alibaba/happyhorse-1.0-r2v":                    wan26VideoI2V,
        "alibaba/happyhorse-1.0-t2v":                    wan26Video,
        "alibaba/qwen-image":                            alibabaQwenImage,
        "alibaba/qwen-image-2.0":                        wanImageEdit,
        "alibaba/qwen-image-edit":                       alibabaQwenImageEdit,
        "alibaba/wan-2-6-i2v":                           wan26VideoI2V,
        "alibaba/wan-2-6-r2v":                           wan26VideoI2V,
        "alibaba/wan-2-6-t2v":                           wan26Video,
        "alibaba/wan-2-7-i2v":                           wan26VideoI2V,
        "alibaba/wan-2-7-r2v":                           wan26VideoI2V,
        "alibaba/wan-2-7-t2v":                           wan26Video,
        "alibaba/wan2.1-t2v-plus":                       alibabaWan21T2VPlus,
        "alibaba/wan2.1-t2v-turbo":                      alibabaWan21T2VTurbo,
        "alibaba/wan2.2-i2v-plus":                       alibabaWan22I2VPlus,
        "alibaba/wan2.2-t2i-flash":                      wanImage,
        "alibaba/wan2.2-t2i-plus":                       wanImage,
        "alibaba/wan2.2-t2v-plus":                       alibabaWan22T2VPlus,
        "alibaba/wan2.5-i2v-preview":                    wan25I2V,
        "alibaba/wan2.5-t2i-preview":                    wanImage,
        "alibaba/wan2.5-t2v-preview":                    alibabaWan25T2VPreview,
        "alibaba/wan2.6-i2v-flash":                      wan26VideoI2V,
        "alibaba/wan2.6-image":                          wanImageEdit,
        "alibaba/wan2.7-i2v":                            wan26VideoI2V,
        "alibaba/wan2.7-image":                          wanImageEdit,
        "alibaba/wan2.7-image-pro":                      wanImageEdit,
        "alibaba/wan2.7-r2v":                            wan26VideoI2V,
        "alibaba/wan2.7-t2v":                            wan26Video,
        "alibaba/z-image-turbo":                         seedreamV4,
        "blackforestlabs/flux-2-max":                    flux2Pro,
        "blackforestlabs/flux-2-max-edit":               flux2ProEdit,
        "blackforestlabs/flux-2-pro":                    flux2Pro,
        "blackforestlabs/flux-2-pro-edit":               flux2ProEdit,
        "blackforestlabs/flux-pro-1.1":                  flux2Pro,
        "bytedance/omnihuman":                           omniHuman,
        "bytedance/omnihuman/v1.5":                      omniHuman,
        "bytedance/seedance-1-0-pro":                    seedance10Pro,
        "bytedance/seedance-1-0-pro-fast":               seedanceVideo,
        "bytedance/seedance-1-5-pro":                    seedanceVideo,
        "bytedance/seedance-2-0":                        seedance20,
        "bytedance/seedance-2-0-fast":                   seedance20,
        "bytedance/seedream-4-5":                        seedream45,
        // Re-registered from `seedreamV4Edit` to `seedream45` on 2026-07-28 — a deliberate,
        // user-approved wire change, not a re-recording. This id publishes `image_size: ["2K","4K"]`
        // and documents neither `num_images` nor `enable_safety_checker`; it was emitting
        // `square_hd` plus both undocumented keys and failing validation on every generation.
        // The expectation below is `seedream45`'s existing independently-recorded golden, reused
        // because it is now genuinely the same table — not regenerated from the encoder.
        "bytedance/dola-seedream-5-0-pro":               seedream50Pro,
        "bytedance/seedream-5-0-lite":                   seedream45,
        "bytedance/seedream-5-0-pro":                    seedream50Pro,
        "bytedance/seedream-v4-edit":                    seedreamV4Edit,
        "bytedance/seedream-v4-text-to-image":           seedreamV4,
        "bytedance/seedream/v4/edit":                    seedreamV4Edit,
        "bytedance/seedream/v4/text-to-image":           seedreamV4,
        "bytedance/uso":                                 noParameters,
        "flux-2":                                        flux2Pro,
        "flux-2-max":                                    flux2Pro,
        "flux-2-max/edit":                               flux2ProEdit,
        "flux-pro":                                      fluxPro,
        "flux-realism":                                  fluxRealism,
        "flux/dev":                                      fluxDev,
        "flux/dev/image-to-image":                       fluxSrpoI2i,
        "flux/kontext-max/image-to-image":               fluxKontextMaxI2i,
        "flux/kontext-max/text-to-image":                fluxKontextMaxT2i,
        "flux/kontext-pro/image-to-image":               fluxKontextProI2i,
        "flux/kontext-pro/text-to-image":                fluxKontextProT2i,
        "flux/schnell":                                  fluxSchnell,
        "flux/srpo":                                     fluxSrpo,
        "gen3a_turbo":                                   runwayGen3Turbo,
        "google/gemini-2.5-flash-image":                 gemini25FlashImage,
        "google/gemini-2.5-flash-image-edit":            gemini25FlashImageEdit,
        "google/gemini-3-1-flash-lite-image":            nanoBanana2Lite,
        "google/gemini-3-pro-image-preview":             gemini3ProImagePreview,
        "google/gemini-3-pro-image-preview-edit":        gemini3ProImagePreviewEdit,
        "google/gemini-3.1-flash-image-preview":         nanoBanana2,
        "google/imagen-3.0-generate-002":                googleImagen4Ultra,
        "google/imagen-4.0-fast-generate-001":           googleImagen4Ultra,
        "google/imagen-4.0-generate-001":                googleImagen4Ultra,
        "google/imagen-4.0-ultra-generate-001":          googleImagen4Ultra,
        "google/nano-banana-pro":                        gemini3ProImagePreview,
        "google/nano-banana-pro-edit":                   gemini3ProImagePreviewEdit,
        "google/veo-3.0-fast":                           googleVeo3T2V,
        "google/veo-3.0-i2v":                            googleVeo31I2VFastVeo30,
        "google/veo-3.0-i2v-fast":                       googleVeo31I2VFastVeo30,
        "google/veo-3.1-first-last-image-to-video":      veoFirstLastFrame,
        "google/veo-3.1-first-last-image-to-video-fast": veoFirstLastFrame,
        "google/veo-3.1-i2v":                            googleVeo31I2VFastVeo31,
        "google/veo-3.1-i2v-fast":                       googleVeo31I2VFastVeo31,
        "google/veo-3.1-lite-generate-001":              veoFirstLastFrame,
        "google/veo-3.1-reference-to-video":             googleVeo31ReferenceToVideo,
        "google/veo-3.1-t2v":                            googleVeo3T2V,
        "google/veo-3.1-t2v-fast":                       googleVeo3T2V,
        "google/veo2":                                   veo2,
        "google/veo2-image-to-video":                    veo2,
        "google/veo3":                                   googleVeo3T2V,
        "gpt-image-1":                                   openAIGPTImage1Extended,
        "gpt-image-1-mini":                              openAIGPTImage1Extended,
        "gpt-image-1.5":                                 openAIGPTImage1,
        "gpt-image-2":                                   openAIGPTImage1,
        "happyhorse-1.0-i2v":                            wan26VideoI2V,
        "happyhorse-1.0-r2v":                            wan26VideoI2V,
        "happyhorse-1.0-t2v":                            wan26Video,
        "hunyuan-image/v3/text-to-image":                hunyuanImageV3,
        "hunyuan/hunyuan-image-v3-text-to-image":        hunyuanImageV3,
        "imagen-3.0-generate-002":                       googleImagen4Ultra,
        "imagen-4.0-generate-001":                       googleImagen4Ultra,
        "imagen-4.0-ultra-generate-001":                 googleImagen4Ultra,
        "kandinsky5/text-to-video":                      kandinskyVideo,
        "kandinsky5/text-to-video/distill":              kandinskyVideo,
        "kling-video/v1.6/pro/image-to-video":           klingVideo,
        "kling-video/v1.6/pro/text-to-video":            klingVideo,
        "kling-video/v1.6/standard/image-to-video":      klingVideo,
        "kling-video/v1.6/standard/text-to-video":       klingVideo,
        "kling-video/v1/pro/image-to-video":             klingVideo,
        "kling-video/v1/pro/text-to-video":              klingVideo,
        "kling-video/v1/standard/image-to-video":        klingVideo,
        "kling-video/v1/standard/text-to-video":         klingVideo,
        "kling-video/v2.1/master/image-to-video":        klingVideo,
        "kling-video/v2.1/master/text-to-video":         klingVideo,
        "kling-video/v2.1/pro/image-to-video":           klingVideo,
        "kling-video/v2.1/standard/image-to-video":      klingVideo,
        "kling-video/v2.5-turbo/pro/image-to-video":     klingv25TurboVideo,
        "kling-video/v2.5-turbo/pro/text-to-video":      klingVideo,
        "kling-video/v2.6/pro/image-to-video":           kling26,
        "kling-video/v2.6/pro/text-to-video":            kling26,
        "kling-video/v2/master/image-to-video":          klingVideo,
        "kling-video/v2/master/text-to-video":           klingVideo,
        "kling-video/v3/pro/image-to-video":             klingV3.mapValues { $0.filter { $0.key != "aspect_ratio" } },
        "kling-video/v3/pro/text-to-video":              klingV3,
        "kling-video/v3/standard/image-to-video":        klingV3.mapValues { $0.filter { $0.key != "aspect_ratio" } },
        "kling-video/v3/standard/text-to-video":         klingV3,
        "klingai/image-o1":                              klingImageO1,
        "klingai/v2-master-image-to-video":              klingVideo,
        "klingai/v2-master-text-to-video":               klingVideo,
        "klingai/v2.1-master-image-to-video":            klingVideo,
        "klingai/v2.1-master-text-to-video":             klingVideo,
        "klingai/v2.5-turbo/pro/image-to-video":         klingv25TurboVideo,
        "klingai/v2.5-turbo/pro/text-to-video":          klingVideo,
        "klingai/video-o1-image-to-video":               klingVideo,
        "klingai/video-o1-reference-to-video":           klingVideo,
        "klingai/video-v2-6-pro-image-to-video":         kling26,
        "klingai/video-v2-6-pro-text-to-video":          kling26,
        "klingai/video-v3-pro-image-to-video":           klingV3.mapValues { $0.filter { $0.key != "aspect_ratio" } },
        "klingai/video-v3-pro-text-to-video":            klingV3,
        "klingai/video-v3-standard-image-to-video":      klingV3.mapValues { $0.filter { $0.key != "aspect_ratio" } },
        "klingai/video-v3-standard-text-to-video":       klingV3,
        "ltxv-2":                                        ltxv2,
        "ltxv-2/fast":                                   ltxv2,
        "ltxv-2/image-to-video":                         ltxv2,
        "ltxv-2/image-to-video/fast":                    ltxv2,
        "ltxv-2/text-to-video":                          ltxv2,
        "ltxv-2/text-to-video/fast":                     ltxv2,
        "ltxv/ltxv-2":                                   ltxv2,
        "ltxv/ltxv-2-fast":                              ltxv2,
        "luma/ray-2":                                    lumaRay2,
        "luma/ray-flash-2":                              lumaRay2,
        "minimax/hailuo-02":                             minimaxHailuo02,
        "minimax/hailuo-2.3":                            hailuo23,
        "minimax/hailuo-2.3-fast":                       hailuo23,
        "nano-banana-2":                                 nanoBanana2,
        "openai/gpt-image-1":                            openAIGPTImage1Extended,
        "openai/gpt-image-1-5":                          openAIGPTImage1,
        "openai/gpt-image-1-mini":                       openAIGPTImage1Extended,
        "openai/gpt-image-1.5":                          openAIGPTImage1,
        "openai/gpt-image-2":                            openAIGPTImage1,
        "openai/gpt-image-2.5-flare":                            openAIGPTImage1,
        "gpt-image-2.5-flare":                            openAIGPTImage1,
        "openai/gpt-image-2.5-sunburst":                            openAIGPTImage1,
        "gpt-image-2.5-sunburst":                            openAIGPTImage1,
        "openai/sora-2-i2v":                             sora2,
        "openai/sora-2-pro-i2v":                         sora2ProI2V,
        "openai/sora-2-pro-t2v":                         sora2ProI2V,
        "openai/sora-2-t2v":                             sora2,
        "pixverse/v5-5-image-to-video":                  pixVerseV55T2V,
        "pixverse/v5-5-text-to-video":                   pixVerseV55T2V,
        "pixverse/v5.5/image-to-video":                  pixVerseV55T2V,
        "pixverse/v5.5/text-to-video":                   pixVerseV55T2V,
        "pixverse/v5/image-to-video":                    pixVerseV55T2V,
        "pixverse/v5/text-to-video":                     pixVerseV55T2V,
        "pixverse/v5/transition":                        pixVerseV55T2V,
        "qwen-image-2.0":                                wanImageEdit,
        "recraft-v3":                                    recraftV3,
        "reve/create-image":                             reveImage,
        "reve/edit-image":                               noParameters,
        "reve/remix-edit-image":                         reveImage,
        "runway/gen3a_turbo":                            runwayGen3Turbo,
        "runway/gen4_aleph":                             runwayGen4Aleph,
        "runway/gen4_turbo":                             runwayGen4,
        "sora-2-i2v":                                    sora2,
        "sora-2-pro-i2v":                                sora2ProI2V,
        "sora-2-pro-t2v":                                sora2ProI2V,
        "sora-2-t2v":                                    sora2,
        "stable-diffusion-v3-medium":                    stableDiffusionV3Medium,
        "stable-diffusion-v35-large":                    stableDiffusionV35Large,
        "topaz-labs/sharpen":                            topazSharpen,
        "topaz-labs/sharpen-gen":                        topazSharpenGen,
        "veo-3.1-lite-generate-001":                     veoFirstLastFrame,
        "veo2":                                          veo2,
        "veo2/image-to-video":                           veo2,
        "video-01":                                      minimaxVideo01,
        "wan2.2-i2v-plus":                               alibabaWan22I2VPlus,
        "wan2.2-t2i-flash":                              wanImage,
        "wan2.2-t2i-plus":                               wanImage,
        "wan2.2-t2v-plus":                               alibabaWan22T2VPlus,
        "wan2.5-t2i-preview":                            wanImage,
        "wan2.6-i2v-flash":                              wan26VideoI2V,
        "wan2.6-image":                                  wanImageEdit,
        "wan2.7-i2v":                                    wan26VideoI2V,
        "wan2.7-image":                                  wanImageEdit,
        "wan2.7-image-pro":                              wanImageEdit,
        "wan2.7-r2v":                                    wan26VideoI2V,
        "wan2.7-t2v":                                    wan26Video,
        "x-ai/grok-imagine-image":                       grokImagine,
        "x-ai/grok-imagine-image-pro":                   grokImagine,
        "z-image-turbo":                                 seedreamV4,
        "z-image/turbo":                                 seedreamV4,
    ]
}

// MARK: - alibabaWan22T2VPlus

extension GoldenPayloads {

    // Split off `alibabaWan21T2VPlus` on 2026-07-28 and recorded here as a **subtraction from that
    // table's existing literal, not a re-recording**: every surviving line is byte-identical to the one
    // recorded at `92e07cf`, and the single difference is that `resolution` is gone. `wan2.2-t2v-plus`
    // publishes `["480P", "1080P"]`, so the `"720p"` this used to send was rejected on every request;
    // it is omitted rather than replaced, because neither 480P nor 1080P is what the user asked for and
    // both cost differently.
    static let alibabaWan22T2VPlus: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "watermark": false,
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "negative_prompt": "sample",
            "seed": 0,
            "watermark": false,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "watermark": false,
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "watermark": false,
        ],
    ]
}

// MARK: - alibabaWan22I2VPlus

extension GoldenPayloads {

    // Split off `wan25I2V` on 2026-07-28. Subtraction from that table's literal, same as
    // `alibabaWan22T2VPlus`: `resolution` alone is gone, because 2.2 publishes `["480P", "1080P"]`
    // where 2.5 publishes lower-case `["480p", "720p", "1080p"]`. `duration` stays exactly as it was —
    // 2.2 does not document that key at all, and an undocumented key has no enum to violate.
    static let alibabaWan22I2VPlus: ProbePayloads = [
        "structDefaults": [
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "",
        ],
        "fullyPopulated": [
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "sample",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "",
        ],
        "klingAdvancedCamera": [
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "",
        ],
    ]
}

// MARK: - googleVeo31ReferenceToVideo

extension GoldenPayloads {

    // Split off `googleVeo31I2VFastVeo31` on 2026-07-28. This literal is that table's **pre-change**
    // recording, unmodified: `veo-3.1-reference-to-video` is the one Veo 3.1 id whose published
    // `resolution` enum is lower case, so `"720p"` was always valid for it and nothing about its wire
    // changed. Its two former table-mates moved to `"720P"`; it did not, and that divergence is the
    // whole reason for the split.
    static let googleVeo31ReferenceToVideo: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720p",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720p",
        ],
    ]
}

// MARK: - alibabaQwenImage

extension GoldenPayloads {

    static let alibabaQwenImage: ProbePayloads = [
        "structDefaults": [:],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "negative_prompt": "sample",
            "num_images": 1,
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [:],
        "klingAdvancedCamera": [:],
    ]
}

// MARK: - alibabaQwenImageEdit

extension GoldenPayloads {

    static let alibabaQwenImageEdit: ProbePayloads = [
        "structDefaults": [
            "watermark": false,
        ],
        "fullyPopulated": [
            "negative_prompt": "sample",
            "watermark": false,
        ],
        "allNil": [:],
        "customImageSize": [
            "watermark": false,
        ],
        "klingAdvancedCamera": [
            "watermark": false,
        ],
    ]
}

// MARK: - alibabaWan21T2VPlus

extension GoldenPayloads {

    static let alibabaWan21T2VPlus: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "resolution": "720P",
            "watermark": false,
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "negative_prompt": "sample",
            "resolution": "720P",
            "seed": 0,
            "watermark": false,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "resolution": "720P",
            "watermark": false,
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "resolution": "720P",
            "watermark": false,
        ],
    ]
}

// MARK: - alibabaWan21T2VTurbo

extension GoldenPayloads {

    static let alibabaWan21T2VTurbo: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "resolution": "720P",
            "watermark": false,
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "negative_prompt": "sample",
            "resolution": "720P",
            "seed": 0,
            "watermark": false,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "resolution": "720P",
            "watermark": false,
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "resolution": "720P",
            "watermark": false,
        ],
    ]
}

// MARK: - alibabaWan25T2VPreview

extension GoldenPayloads {

    static let alibabaWan25T2VPreview: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "enhance_prompt": true,
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "sample",
            "resolution": "720p",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "enhance_prompt": true,
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "enhance_prompt": true,
            "resolution": "720p",
        ],
    ]
}

// MARK: - flux2Pro

extension GoldenPayloads {

    static let flux2Pro: ProbePayloads = [
        "structDefaults": [
            "image_size": "landscape_4_3",
            "safety_tolerance": "2",
        ],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "image_size": "square_hd",
            "safety_tolerance": "2",
        ],
        "allNil": [
            "image_size": "landscape_4_3",
        ],
        "customImageSize": [
            "image_size": ["height": 736, "width": 1280] as [String: Int],
            "safety_tolerance": "2",
        ],
        "klingAdvancedCamera": [
            "image_size": "landscape_4_3",
            "safety_tolerance": "2",
        ],
    ]
}

// MARK: - flux2ProEdit

extension GoldenPayloads {

    static let flux2ProEdit: ProbePayloads = [
        "structDefaults": [
            "image_size": "landscape_4_3",
            "safety_tolerance": "2",
        ],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "image_size": "square_hd",
            "safety_tolerance": "2",
        ],
        "allNil": [
            "image_size": "landscape_4_3",
        ],
        "customImageSize": [
            "image_size": ["height": 736, "width": 1280] as [String: Int],
            "safety_tolerance": "2",
        ],
        "klingAdvancedCamera": [
            "image_size": "landscape_4_3",
            "safety_tolerance": "2",
        ],
    ]
}

// MARK: - fluxDev

extension GoldenPayloads {

    static let fluxDev: ProbePayloads = [
        "structDefaults": [
            "image_size": "landscape_4_3",
        ],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "image_size": "square_hd",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
        ],
        "allNil": [
            "image_size": "landscape_4_3",
        ],
        "customImageSize": [
            "image_size": ["height": 720, "width": 1280] as [String: Int],
        ],
        "klingAdvancedCamera": [
            "image_size": "landscape_4_3",
        ],
    ]
}

// MARK: - fluxKontextMaxI2i

extension GoldenPayloads {

    static let fluxKontextMaxI2i: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "guidance_scale": 3.5,
            "num_images": 1,
            "safety_tolerance": "2",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
    ]
}

// MARK: - fluxKontextMaxT2i

extension GoldenPayloads {

    static let fluxKontextMaxT2i: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "guidance_scale": 3.5,
            "num_images": 1,
            "safety_tolerance": "2",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
    ]
}

// MARK: - fluxKontextProI2i

extension GoldenPayloads {

    static let fluxKontextProI2i: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "guidance_scale": 3.5,
            "num_images": 1,
            "safety_tolerance": "2",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
    ]
}

// MARK: - fluxKontextProT2i

extension GoldenPayloads {

    static let fluxKontextProT2i: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "guidance_scale": 3.5,
            "num_images": 1,
            "safety_tolerance": "2",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "safety_tolerance": "2",
        ],
    ]
}

// MARK: - fluxPro

extension GoldenPayloads {

    static let fluxPro: ProbePayloads = [
        "structDefaults": [
            "image_size": "landscape_4_3",
            "safety_tolerance": "2",
        ],
        "fullyPopulated": [
            "guidance_scale": 3.5,
            "image_size": "square_hd",
            "num_images": 1,
            "num_inference_steps": 28,
            "safety_tolerance": "2",
            "seed": 0,
        ],
        "allNil": [
            "image_size": "landscape_4_3",
        ],
        "customImageSize": [
            "image_size": ["height": 720, "width": 1280] as [String: Int],
            "safety_tolerance": "2",
        ],
        "klingAdvancedCamera": [
            "image_size": "landscape_4_3",
            "safety_tolerance": "2",
        ],
    ]
}

// MARK: - fluxRealism

extension GoldenPayloads {

    static let fluxRealism: ProbePayloads = [
        "structDefaults": [
            "image_size": "landscape_4_3",
        ],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "image_size": "square_hd",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
        ],
        "allNil": [
            "image_size": "landscape_4_3",
        ],
        "customImageSize": [
            "image_size": ["height": 720, "width": 1280] as [String: Int],
        ],
        "klingAdvancedCamera": [
            "image_size": "landscape_4_3",
        ],
    ]
}

// MARK: - fluxSchnell

extension GoldenPayloads {

    static let fluxSchnell: ProbePayloads = [
        "structDefaults": [
            "image_size": "landscape_4_3",
        ],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "image_size": "square_hd",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
        ],
        "allNil": [
            "image_size": "landscape_4_3",
        ],
        "customImageSize": [
            "image_size": ["height": 720, "width": 1280] as [String: Int],
        ],
        "klingAdvancedCamera": [
            "image_size": "landscape_4_3",
        ],
    ]
}

// MARK: - fluxSrpo

extension GoldenPayloads {

    static let fluxSrpo: ProbePayloads = [
        "structDefaults": [
            "image_size": "landscape_4_3",
        ],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "image_size": "square_hd",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
        ],
        "allNil": [
            "image_size": "landscape_4_3",
        ],
        "customImageSize": [
            "image_size": ["height": 720, "width": 1280] as [String: Int],
        ],
        "klingAdvancedCamera": [
            "image_size": "landscape_4_3",
        ],
    ]
}

// MARK: - fluxSrpoI2i

extension GoldenPayloads {

    static let fluxSrpoI2i: ProbePayloads = [
        "structDefaults": [
            "acceleration": "regular",
            "image_size": "landscape_4_3",
            "strength": 0.8,
        ],
        "fullyPopulated": [
            "acceleration": "regular",
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "image_size": "square_hd",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
            "strength": 0.8,
        ],
        "allNil": [
            "image_size": "landscape_4_3",
        ],
        "customImageSize": [
            "acceleration": "regular",
            "image_size": ["height": 720, "width": 1280] as [String: Int],
            "strength": 0.8,
        ],
        "klingAdvancedCamera": [
            "acceleration": "regular",
            "image_size": "landscape_4_3",
            "strength": 0.8,
        ],
    ]
}

// MARK: - gemini25FlashImage

extension GoldenPayloads {

    static let gemini25FlashImage: ProbePayloads = [
        "structDefaults": [:],
        "fullyPopulated": [:],
        "allNil": [:],
        "customImageSize": [:],
        "klingAdvancedCamera": [:],
    ]
}

// MARK: - gemini25FlashImageEdit

extension GoldenPayloads {

    static let gemini25FlashImageEdit: ProbePayloads = [
        "structDefaults": [:],
        "fullyPopulated": [
            "num_images": 1,
        ],
        "allNil": [:],
        "customImageSize": [:],
        "klingAdvancedCamera": [:],
    ]
}

// MARK: - gemini3ProImagePreview

extension GoldenPayloads {

    static let gemini3ProImagePreview: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
        ],
    ]
}

// MARK: - gemini3ProImagePreviewEdit

extension GoldenPayloads {

    static let gemini3ProImagePreviewEdit: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
        ],
    ]
}

// MARK: - googleImagen4Ultra

extension GoldenPayloads {

    static let googleImagen4Ultra: ProbePayloads = [
        "structDefaults": [
            "add_watermark": false,
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
        ],
        "fullyPopulated": [
            "add_watermark": false,
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "num_images": 1,
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "add_watermark": false,
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
        ],
        "klingAdvancedCamera": [
            "add_watermark": false,
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
        ],
    ]
}

// MARK: - googleVeo31I2VFastVeo30

extension GoldenPayloads {

    static let googleVeo31I2VFastVeo30: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720P",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720P",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720P",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720P",
        ],
    ]
}

// MARK: - googleVeo31I2VFastVeo31

extension GoldenPayloads {

    static let googleVeo31I2VFastVeo31: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720P",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720P",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720P",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "resolution": "720P",
        ],
    ]
}

// MARK: - googleVeo3T2V

extension GoldenPayloads {

    static let googleVeo3T2V: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "generate_audio": true,
            "resolution": "720P",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "generate_audio": true,
            "negative_prompt": "sample",
            "resolution": "720P",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "generate_audio": true,
            "resolution": "720P",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "enhance_prompt": true,
            "generate_audio": true,
            "resolution": "720P",
        ],
    ]
}

// MARK: - grokImagine

extension GoldenPayloads {

    static let grokImagine: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "n": 1,
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
        ],
    ]
}

// MARK: - hailuo23

extension GoldenPayloads {

    static let hailuo23: ProbePayloads = [
        "structDefaults": [
            "enhance_prompt": true,
        ],
        "fullyPopulated": [
            "enhance_prompt": true,
        ],
        "allNil": [:],
        "customImageSize": [
            "enhance_prompt": true,
        ],
        "klingAdvancedCamera": [
            "enhance_prompt": true,
        ],
    ]
}

// MARK: - hunyuanImageV3

extension GoldenPayloads {

    static let hunyuanImageV3: ProbePayloads = [
        "structDefaults": [
            "enable_prompt_expansion": true,
            "image_size": "square_hd",
        ],
        "fullyPopulated": [
            "enable_prompt_expansion": true,
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "image_size": "square_hd",
            "negative_prompt": "sample",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
        ],
        "allNil": [
            "image_size": "square_hd",
        ],
        "customImageSize": [
            "enable_prompt_expansion": true,
            "image_size": ["height": 720, "width": 1280] as [String: Int],
        ],
        "klingAdvancedCamera": [
            "enable_prompt_expansion": true,
            "image_size": "square_hd",
        ],
    ]
}

// MARK: - kandinskyVideo

extension GoldenPayloads {

    static let kandinskyVideo: ProbePayloads = [
        "structDefaults": [
            "duration": 5,
        ],
        "fullyPopulated": [
            "duration": 5,
            "num_inference_steps": 28,
        ],
        "allNil": [:],
        "customImageSize": [
            "duration": 5,
        ],
        "klingAdvancedCamera": [
            "duration": 5,
        ],
    ]
}

// MARK: - kling26

extension GoldenPayloads {

    static let kling26: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
            "generate_audio": true,
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
            "generate_audio": true,
            "negative_prompt": "sample",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
            "generate_audio": true,
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
            "generate_audio": true,
        ],
    ]
}

// MARK: - klingImageO1

extension GoldenPayloads {

    static let klingImageO1: ProbePayloads = [
        "structDefaults": [:],
        "fullyPopulated": [:],
        "allNil": [:],
        "customImageSize": [:],
        "klingAdvancedCamera": [:],
    ]
}

// MARK: - klingV3

extension GoldenPayloads {

    static let klingV3: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
            "generate_audio": true,
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
            "generate_audio": true,
            "negative_prompt": "sample",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
            "generate_audio": true,
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
            "generate_audio": true,
        ],
    ]
}

// MARK: - klingVideo

extension GoldenPayloads {

    static let klingVideo: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "camera_control": "{}",
            "cfg_scale": 0.5,
            "duration": 5,
            "negative_prompt": "sample",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "cfg_scale": 0.5,
            "duration": 5,
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "camera_control": ["movement_type": "zoom", "movement_value": -4] as [String: Any],
            "cfg_scale": 0.5,
            "duration": 5,
        ],
    ]
}

// MARK: - klingv25TurboVideo

extension GoldenPayloads {

    static let klingv25TurboVideo: ProbePayloads = [
        "structDefaults": [
            "duration": 5,
            "negative_prompt": "",
        ],
        "fullyPopulated": [
            "cfg_scale": 3.5,
            "duration": 5,
            "negative_prompt": "sample",
        ],
        "allNil": [:],
        "customImageSize": [
            "duration": 5,
            "negative_prompt": "",
        ],
        "klingAdvancedCamera": [
            "duration": 5,
            "negative_prompt": "",
        ],
    ]
}

// MARK: - ltxv2

extension GoldenPayloads {

    static let ltxv2: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "generate_audio": true,
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "generate_audio": true,
        ],
        "allNil": [
            "aspect_ratio": "16:9",
        ],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "generate_audio": true,
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "generate_audio": true,
        ],
    ]
}

// MARK: - lumaRay2

extension GoldenPayloads {

    static let lumaRay2: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "loop": false,
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "loop": false,
            "resolution": "720p",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "loop": false,
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "loop": false,
            "resolution": "720p",
        ],
    ]
}

// MARK: - minimaxHailuo02

extension GoldenPayloads {

    static let minimaxHailuo02: ProbePayloads = [
        "structDefaults": [
            "enhance_prompt": true,
        ],
        "fullyPopulated": [
            "enhance_prompt": true,
        ],
        "allNil": [:],
        "customImageSize": [
            "enhance_prompt": true,
        ],
        "klingAdvancedCamera": [
            "enhance_prompt": true,
        ],
    ]
}

// MARK: - minimaxVideo01

extension GoldenPayloads {

    static let minimaxVideo01: ProbePayloads = [
        "structDefaults": [
            "enhance_prompt": true,
        ],
        "fullyPopulated": [
            "enhance_prompt": true,
        ],
        "allNil": [:],
        "customImageSize": [
            "enhance_prompt": true,
        ],
        "klingAdvancedCamera": [
            "enhance_prompt": true,
        ],
    ]
}

// MARK: - noParameters

extension GoldenPayloads {

    static let noParameters: ProbePayloads = [
        "structDefaults": [:],
        "fullyPopulated": [:],
        "allNil": [:],
        "customImageSize": [:],
        "klingAdvancedCamera": [:],
    ]
}

// MARK: - omniHuman

extension GoldenPayloads {

    static let omniHuman: ProbePayloads = [
        "structDefaults": [:],
        "fullyPopulated": [
            "audio_url": "https://example.com/audio.mp3",
        ],
        "allNil": [:],
        "customImageSize": [:],
        "klingAdvancedCamera": [:],
    ]
}

// MARK: - openAIGPTImage1

extension GoldenPayloads {

    static let openAIGPTImage1: ProbePayloads = [
        "structDefaults": [
            "background": "auto",
            "quality": "medium",
            "size": "1024x1024",
        ],
        "fullyPopulated": [
            "background": "auto",
            "quality": "medium",
            "size": "1024x1024",
        ],
        "allNil": [
            "background": "auto",
            "quality": "medium",
            "size": "1024x1024",
        ],
        "customImageSize": [
            "background": "auto",
            "quality": "medium",
            "size": "1024x1024",
        ],
        "klingAdvancedCamera": [
            "background": "auto",
            "quality": "medium",
            "size": "1024x1024",
        ],
    ]
}

// MARK: - openAIGPTImage1Extended

extension GoldenPayloads {

    static let openAIGPTImage1Extended: ProbePayloads = [
        "structDefaults": [
            "background": "auto",
            "moderation": "auto",
            "output_format": "png",
            "quality": "medium",
            "size": "1024x1024",
        ],
        "fullyPopulated": [
            "background": "auto",
            "moderation": "auto",
            "output_format": "png",
            "quality": "medium",
            "size": "1024x1024",
        ],
        "allNil": [
            "background": "auto",
            "moderation": "auto",
            "output_format": "png",
            "quality": "medium",
            "size": "1024x1024",
        ],
        "customImageSize": [
            "background": "auto",
            "moderation": "auto",
            "output_format": "png",
            "quality": "medium",
            "size": "1024x1024",
        ],
        "klingAdvancedCamera": [
            "background": "auto",
            "moderation": "auto",
            "output_format": "png",
            "quality": "medium",
            "size": "1024x1024",
        ],
    ]
}

// MARK: - pixVerseV55T2V

extension GoldenPayloads {

    static let pixVerseV55T2V: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "generate_audio_switch": true,
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "generate_audio_switch": true,
            "negative_prompt": "sample",
            "resolution": "720p",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "generate_audio_switch": true,
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "generate_audio_switch": true,
            "resolution": "720p",
        ],
    ]
}

// MARK: - recraftV3

extension GoldenPayloads {

    static let recraftV3: ProbePayloads = [
        "structDefaults": [
            "image_size": "square_hd",
        ],
        "fullyPopulated": [
            "image_size": "square_hd",
        ],
        "allNil": [
            "image_size": "square_hd",
        ],
        "customImageSize": [
            "image_size": ["height": 720, "width": 1280] as [String: Int],
        ],
        "klingAdvancedCamera": [
            "image_size": "square_hd",
        ],
    ]
}

// MARK: - reveImage

extension GoldenPayloads {

    static let reveImage: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
        ],
    ]
}

// MARK: - runwayGen3Turbo

extension GoldenPayloads {

    static let runwayGen3Turbo: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
        ],
    ]
}

// MARK: - runwayGen4

extension GoldenPayloads {

    static let runwayGen4: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
        ],
    ]
}

// MARK: - runwayGen4Aleph

extension GoldenPayloads {

    static let runwayGen4Aleph: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
        ],
    ]
}

// MARK: - seedance10Pro

extension GoldenPayloads {

    static let seedance10Pro: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
            "seed": 0,
        ],
        "allNil": [
            "duration": 5,
        ],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
        ],
    ]
}

// MARK: - seedance20

extension GoldenPayloads {

    static let seedance20: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "generate_audio": true,
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "generate_audio": true,
            "resolution": "720p",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "generate_audio": true,
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "generate_audio": true,
            "resolution": "720p",
        ],
    ]
}

// MARK: - seedanceVideo

extension GoldenPayloads {

    static let seedanceVideo: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
        ],
    ]
}

// MARK: - seedream45

extension GoldenPayloads {

    static let seedream45: ProbePayloads = [
        "structDefaults": [
            "image_size": "2K",
            "watermark": false,
        ],
        "fullyPopulated": [
            "image_size": "square_hd",
            "seed": 0,
            "watermark": false,
        ],
        "allNil": [
            "image_size": "2K",
        ],
        "customImageSize": [
            "image_size": ["height": 1440, "width": 1440] as [String: Int],
            "watermark": false,
        ],
        "klingAdvancedCamera": [
            "image_size": "2K",
            "watermark": false,
        ],
    ]
}

// MARK: - seedreamV4

extension GoldenPayloads {

    static let seedreamV4: ProbePayloads = [
        "structDefaults": [
            "image_size": "square_hd",
        ],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "image_size": "square_hd",
            "num_images": 1,
            "seed": 0,
        ],
        "allNil": [
            "image_size": "square_hd",
        ],
        "customImageSize": [
            "image_size": ["height": 720, "width": 1280] as [String: Int],
        ],
        "klingAdvancedCamera": [
            "image_size": "square_hd",
        ],
    ]
}

// MARK: - seedreamV4Edit

extension GoldenPayloads {

    static let seedreamV4Edit: ProbePayloads = [
        "structDefaults": [
            "image_size": "square_hd",
        ],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "image_size": "square_hd",
            "num_images": 1,
            "seed": 0,
        ],
        "allNil": [
            "image_size": "square_hd",
        ],
        "customImageSize": [
            "image_size": ["height": 720, "width": 1280] as [String: Int],
        ],
        "klingAdvancedCamera": [
            "image_size": "square_hd",
        ],
    ]
}

// MARK: - sora2

extension GoldenPayloads {

    static let sora2: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "resolution": "720p",
        ],
        "allNil": [
            "resolution": "720p",
        ],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "resolution": "720p",
        ],
    ]
}

// MARK: - sora2ProI2V

extension GoldenPayloads {

    static let sora2ProI2V: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "resolution": "720p",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "resolution": "720p",
        ],
    ]
}

// MARK: - stableDiffusionV35Large

extension GoldenPayloads {

    static let stableDiffusionV35Large: ProbePayloads = [
        "structDefaults": [
            "image_size": "square_hd",
            "negative_prompt": "",
        ],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "image_size": "square_hd",
            "negative_prompt": "sample",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
        ],
        "allNil": [
            "image_size": "square_hd",
        ],
        "customImageSize": [
            "image_size": ["height": 720, "width": 1280] as [String: Int],
            "negative_prompt": "",
        ],
        "klingAdvancedCamera": [
            "image_size": "square_hd",
            "negative_prompt": "",
        ],
    ]
}

// MARK: - stableDiffusionV3Medium

extension GoldenPayloads {

    static let stableDiffusionV3Medium: ProbePayloads = [
        "structDefaults": [
            "image_size": "square_hd",
            "negative_prompt": "",
        ],
        "fullyPopulated": [
            "enable_safety_checker": true,
            "guidance_scale": 3.5,
            "image_size": "square_hd",
            "negative_prompt": "sample",
            "num_images": 1,
            "num_inference_steps": 28,
            "seed": 0,
        ],
        "allNil": [
            "image_size": "square_hd",
        ],
        "customImageSize": [
            "image_size": ["height": 720, "width": 1280] as [String: Int],
            "negative_prompt": "",
        ],
        "klingAdvancedCamera": [
            "image_size": "square_hd",
            "negative_prompt": "",
        ],
    ]
}

// MARK: - topazSharpen

extension GoldenPayloads {

    static let topazSharpen: ProbePayloads = [
        "structDefaults": [
            "mode": "Standard",
            "strength": 0.8,
        ],
        "fullyPopulated": [
            "face_enhancement": true,
            "face_enhancement_creativity": 0.5,
            "face_enhancement_strength": 0.5,
            "minor_denoise": 0.5,
            "mode": "Standard",
            "output_format": "png",
            "strength": 0.8,
            "subject_detection": "All",
        ],
        "allNil": [
            "mode": "Standard",
        ],
        "customImageSize": [
            "mode": "Standard",
            "strength": 0.8,
        ],
        "klingAdvancedCamera": [
            "mode": "Standard",
            "strength": 0.8,
        ],
    ]
}

// MARK: - topazSharpenGen

extension GoldenPayloads {

    static let topazSharpenGen: ProbePayloads = [
        "structDefaults": [
            "mode": "Super Focus",
            "strength": 0.8,
        ],
        "fullyPopulated": [
            "face_enhancement": true,
            "face_enhancement_creativity": 0.5,
            "face_enhancement_strength": 0.5,
            "focus_boost": 0.5,
            "mode": "Super Focus",
            "output_format": "png",
            "seed": 0,
            "strength": 0.8,
            "subject_detection": "All",
        ],
        "allNil": [
            "mode": "Super Focus",
        ],
        "customImageSize": [
            "mode": "Super Focus",
            "strength": 0.8,
        ],
        "klingAdvancedCamera": [
            "mode": "Super Focus",
            "strength": 0.8,
        ],
    ]
}

// MARK: - veo2

extension GoldenPayloads {

    static let veo2: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "resolution": "720p",
        ],
    ]
}

// MARK: - veoFirstLastFrame

extension GoldenPayloads {

    static let veoFirstLastFrame: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "generate_audio": true,
            "resolution": "720P",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "generate_audio": true,
            "resolution": "720P",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "generate_audio": true,
            "resolution": "720P",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "generate_audio": true,
            "resolution": "720P",
        ],
    ]
}

// MARK: - wan25I2V

extension GoldenPayloads {

    static let wan25I2V: ProbePayloads = [
        "structDefaults": [
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "",
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "sample",
            "resolution": "720p",
            "seed": 0,
        ],
        "allNil": [:],
        "customImageSize": [
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "",
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "duration": 5,
            "enhance_prompt": true,
            "negative_prompt": "",
            "resolution": "720p",
        ],
    ]
}

// MARK: - wan26Video

extension GoldenPayloads {

    static let wan26Video: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "enhance_prompt": true,
            "generate_audio": true,
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "enhance_prompt": true,
            "generate_audio": true,
            "negative_prompt": "sample",
            "resolution": "720p",
            "seed": 0,
            "shot_type": "single",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "enhance_prompt": true,
            "generate_audio": true,
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "duration": 5,
            "enhance_prompt": true,
            "generate_audio": true,
            "resolution": "720p",
        ],
    ]
}

// MARK: - wan26VideoI2V

extension GoldenPayloads {

    static let wan26VideoI2V: ProbePayloads = [
        "structDefaults": [
            "duration": 5,
            "enhance_prompt": true,
            "generate_audio": true,
            "resolution": "720p",
        ],
        "fullyPopulated": [
            "duration": 5,
            "enhance_prompt": true,
            "generate_audio": true,
            "negative_prompt": "sample",
            "resolution": "720p",
            "seed": 0,
            "shot_type": "single",
        ],
        "allNil": [:],
        "customImageSize": [
            "duration": 5,
            "enhance_prompt": true,
            "generate_audio": true,
            "resolution": "720p",
        ],
        "klingAdvancedCamera": [
            "duration": 5,
            "enhance_prompt": true,
            "generate_audio": true,
            "resolution": "720p",
        ],
    ]
}

// MARK: - wanImage

extension GoldenPayloads {

    static let wanImage: ProbePayloads = [
        "structDefaults": [
            "enhance_prompt": true,
            "image_size": "landscape_4_3",
            "watermark": false,
        ],
        "fullyPopulated": [
            "enhance_prompt": true,
            "image_size": "square_hd",
            "negative_prompt": "sample",
            "num_images": 1,
            "seed": 0,
            "watermark": false,
        ],
        "allNil": [
            "image_size": "landscape_4_3",
        ],
        "customImageSize": [
            "enhance_prompt": true,
            "image_size": ["height": 720, "width": 1280] as [String: Int],
            "watermark": false,
        ],
        "klingAdvancedCamera": [
            "enhance_prompt": true,
            "image_size": "landscape_4_3",
            "watermark": false,
        ],
    ]
}

// MARK: - wanImageEdit

extension GoldenPayloads {

    static let wanImageEdit: ProbePayloads = [
        "structDefaults": [
            "enhance_prompt": true,
            "image_size": "landscape_4_3",
            "watermark": false,
        ],
        "fullyPopulated": [
            "enhance_prompt": true,
            "image_size": "square_hd",
            "negative_prompt": "sample",
            "seed": 0,
            "watermark": false,
        ],
        "allNil": [
            "image_size": "landscape_4_3",
        ],
        "customImageSize": [
            "enhance_prompt": true,
            "image_size": ["height": 720, "width": 1280] as [String: Int],
            "watermark": false,
        ],
        "klingAdvancedCamera": [
            "enhance_prompt": true,
            "image_size": "landscape_4_3",
            "watermark": false,
        ],
    ]
}

// Stage-3.5 introduction recordings (2026-08-11): first-ever wire shape for these ids; recorded
// from ParamEncoder AT INTRODUCTION — there is no legacy builder for them.
//
// Both tables' rows read `.aspectRatio` / `.geminiResolution`, whose `ModelParameters` struct
// defaults ("16:9" / "1K") already sit inside each table's own `allowedValues`. Every probe but
// `allNil` leaves both fields at those defaults (`fullyPopulatedProbe()` sets them to the same
// values), so all four non-`allNil` probes produce an identical payload; `allNil` clears every
// `ParamField`, so both keys go unemitted.

// MARK: - nanoBanana2

extension GoldenPayloads {

    static let nanoBanana2: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "resolution": "1K",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "resolution": "1K",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "resolution": "1K",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "resolution": "1K",
        ],
    ]
}

// MARK: - nanoBanana2Lite

extension GoldenPayloads {

    static let nanoBanana2Lite: ProbePayloads = [
        "structDefaults": [
            "aspect_ratio": "16:9",
            "resolution": "1K",
        ],
        "fullyPopulated": [
            "aspect_ratio": "16:9",
            "resolution": "1K",
        ],
        "allNil": [:],
        "customImageSize": [
            "aspect_ratio": "16:9",
            "resolution": "1K",
        ],
        "klingAdvancedCamera": [
            "aspect_ratio": "16:9",
            "resolution": "1K",
        ],
    ]
}

// Task 6 introduction recording (2026-08-11): first-ever wire shape for `seedream50Pro`, the new
// table Seedream 5.0 Pro needed (see `ImageByteDance.swift`'s MARK comment for why it could not
// reuse `seedream45`). Recorded from `ParamEncoder` the same way as the Stage-3.5 block above —
// there is no legacy builder for this id either. Cross-checked with a temporary print-based test
// run over `ProbeSet.all` before being pasted here and deleted, per the same procedure.
//
// `image_size`'s preset fallback is `"1.5K"` (this table's own `presetFallback`, unlike
// `nanoBanana2`'s fields above which happened to share their probe's forced value). `seed` is
// absent from every probe but `fullyPopulated`, which sets it to the struct default `0`.
// `watermark`'s struct default is `false`, matching the table's `defaultValue`, so it is emitted
// on every probe except `allNil`, which clears every `ParamField` including it. `customImageSize`
// exercises the object branch: `customWidth: 1280, customHeight: 720` clamped up to this table's
// `minimumDimension: 1024` — width is already above it (1280), height is raised to 1024 — and
// neither exceeds `maximumDimension: 2752`, so the key is emitted rather than omitted.

// MARK: - seedream50Pro

extension GoldenPayloads {

    static let seedream50Pro: ProbePayloads = [
        "structDefaults": [
            "image_size": "1.5K",
            "watermark": false,
        ],
        "fullyPopulated": [
            "image_size": "square_hd",
            "seed": 0,
            "watermark": false,
        ],
        "allNil": [
            "image_size": "1.5K",
        ],
        "customImageSize": [
            "image_size": ["height": 1024, "width": 1280] as [String: Int],
            "watermark": false,
        ],
        "klingAdvancedCamera": [
            "image_size": "1.5K",
            "watermark": false,
        ],
    ]
}
