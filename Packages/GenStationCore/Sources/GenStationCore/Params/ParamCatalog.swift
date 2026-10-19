// ParamCatalog — every model's descriptor table, behind one symbol (Stage 2, Task 7).
//
// The namespace rule (design § 4.1) exists for exactly this file: 67 per-model tables must
// contribute **one** top-level symbol to the package's API, not 67. (This read "121" until
// 2026-07-27; 121 is the number of registry groups the tables are *keyed by*, which is the correct
// number at line 9 below — several groups share a table.) The tables themselves live in
// `Tables/`, as `static let`s on `extension ParamCatalog` — internal to the package, invisible
// outside it, and reachable only through `descriptors(forModelId:)`. (They cannot be `private`:
// `private` in Swift is file-scoped, and this file is not where they are written.)
//
// Tables are keyed per former `reg()` group, not per alias — 209 registered ids resolved to 121
// groups, so
// keying per alias would make 88 of them duplicates. Aliases that share a group each get their own
// key pointing at the same table.
//
// `migratedIds` is what keeps the migration verifiable while it is half-done: `PayloadEquivalenceTests`
// iterates *only* these ids, so the harness is green from day one and tightens as each table lands.
// Adding a key here is what puts a model under test — a table that exists but is not reachable from
// `tables` is not covered by anything.

import Foundation

public enum ParamCatalog {

    /// The descriptor table for a model, or `nil` if the id has no table. There is no longer a legacy
    /// fallback: `LegacyPayload` was deleted in Stage 2 and `EnhancedModel.paramViewBuilder` with it,
    /// so `nil` here means the renderer draws nothing and `ParamEncoder` emits nothing.
    ///
    /// Lowercases its argument. Every catalog id is lowercased too (`CatalogModel.id` is defined as
    /// the lowercased canonical key), so an upper-cased key here would be permanently unreachable —
    /// `GoldenPayloadTests.testEveryGoldenIdIsLowercasedAndResolvesCaseInsensitively` forbids it.
    public static func descriptors(forModelId id: String) -> [ParamDescriptor]? {
        tables[id.lowercased()]
    }

    /// A catalog row's descriptor table, or `[]` when it has none.
    ///
    /// Every AI/ML id in the catalog has a table — including every alias, because the `tables`
    /// dictionary below is deliberately keyed per alias rather than per `reg()` group. So `[]`
    /// means an **unregistered** row, one from `Catalog.synthesized(for:)`. Encoding and decoding
    /// against an empty table are both no-ops, so this is exactly equivalent to the old registry
    /// fallback rather than merely similar.
    public static func descriptors(for model: CatalogModel) -> [ParamDescriptor] {
        descriptors(forModelId: model.id) ?? []
    }

    /// The encoder/renderer context for a catalog row.
    ///
    /// `isI2I` is the **static** catalog flag, which is what `Condition.isTextToVideo` evaluates
    /// against (frozen legacy semantics — see `Condition.isTextToVideo`). `hasInputImages` is the
    /// true mode, carried for the renderer and for the later ledger wave that will switch the
    /// predicate over to it.
    public static func context(for model: CatalogModel, hasInputImages: Bool) -> ParamContext {
        ParamContext(modelId: model.id, isI2I: model.isI2I, hasInputImages: hasInputImages)
    }

    /// Every id that has a table. The equivalence harness iterates this set.
    public static let migratedIds: Set<String> = Set(tables.keys)

    // MARK: - Tables

    private static let tables: [String: [ParamDescriptor]] = [
        "alibaba/wan-3-0-video": wan30Video,
        "bytedance/seedance-2-5": seedance25Video,
        "minimax/h3-max": minimaxH3MaxVideo,
        // MARK: Alibaba — Wan 2.1 / 2.2 / 2.5 / 2.6 / 2.7 and the Wan-shaped Happy Horse fan-out
        "alibaba/happyhorse-1.0-i2v": wan26VideoI2V,
        "alibaba/happyhorse-1.0-r2v": wan26VideoI2V,
        "alibaba/happyhorse-1.0-t2v": wan26Video,
        "alibaba/wan-2-6-i2v":        wan26VideoI2V,
        "alibaba/wan-2-6-r2v":        wan26VideoI2V,
        "alibaba/wan-2-6-t2v":        wan26Video,
        "alibaba/wan-2-7-i2v":        wan26VideoI2V,
        "alibaba/wan-2-7-r2v":        wan26VideoI2V,
        "alibaba/wan-2-7-t2v":        wan26Video,
        "alibaba/wan2.1-t2v-plus":    alibabaWan21T2VPlus,
        "alibaba/wan2.1-t2v-turbo":   alibabaWan21T2VTurbo,
        // Was `wan25I2V` until 2026-07-28 — a 2.2 model on a 2.5 table. The two publish disjoint
        // `resolution` vocabularies (`["480P","1080P"]` upper case against `["480p","720p","1080p"]`
        // lower case), so the shared struct default `"720p"` was rejected here on every request.
        "alibaba/wan2.2-i2v-plus":    alibabaWan22I2VPlus,
        // Was `alibabaWan21T2VPlus` until 2026-07-28. Same key set as 2.1, but `resolution` is
        // `["480P","1080P"]` where 2.1 is `["720P"]` — no value in common, so one table cannot serve
        // both.
        "alibaba/wan2.2-t2v-plus":    alibabaWan22T2VPlus,
        "alibaba/wan2.5-i2v-preview": wan25I2V,
        "alibaba/wan2.5-t2v-preview": alibabaWan25T2VPreview,
        "alibaba/wan2.6-i2v-flash":   wan26VideoI2V,
        "alibaba/wan2.7-i2v":         wan26VideoI2V,
        "alibaba/wan2.7-r2v":         wan26VideoI2V,
        "alibaba/wan2.7-t2v":         wan26Video,
        "happyhorse-1.0-i2v":         wan26VideoI2V,
        "happyhorse-1.0-r2v":         wan26VideoI2V,
        "happyhorse-1.0-t2v":         wan26Video,
        "wan2.2-i2v-plus":            alibabaWan22I2VPlus,
        "wan2.2-t2v-plus":            alibabaWan22T2VPlus,
        "wan2.6-i2v-flash":           wan26VideoI2V,
        "wan2.7-i2v":                 wan26VideoI2V,
        "wan2.7-r2v":                 wan26VideoI2V,
        "wan2.7-t2v":                 wan26Video,

        // MARK: Google — Veo 2, Veo 3.0/3.1 t2v, i2v, first-last-frame and reference-to-video
        "google/veo-3.0-fast":                           googleVeo3T2V,
        "google/veo-3.0-i2v":                            googleVeo31I2VFastVeo30,
        "google/veo-3.0-i2v-fast":                       googleVeo31I2VFastVeo30,
        "google/veo-3.1-first-last-image-to-video":      veoFirstLastFrame,
        "google/veo-3.1-first-last-image-to-video-fast": veoFirstLastFrame,
        "google/veo-3.1-i2v":                            googleVeo31I2VFastVeo31,
        "google/veo-3.1-i2v-fast":                       googleVeo31I2VFastVeo31,
        // Was `veoFirstLastFrame` until 2026-07-28. Split so that the two first/last-frame ids can
        // offer the `4K` their schemas publish, which this one does not.
        "google/veo-3.1-lite-generate-001":              veoLiteGenerate,
        // Was `googleVeo31I2VFastVeo31` until 2026-07-28. The only Veo 3.1 id that spells its
        // resolutions in lower case, and it accepts a single duration.
        "google/veo-3.1-reference-to-video":             googleVeo31ReferenceToVideo,
        // Both Veo 3.1 t2v ids were `googleVeo3T2V` until 2026-07-28; split so they can offer `4K`.
        "google/veo-3.1-t2v":                            googleVeo3T2V31,
        "google/veo-3.1-t2v-fast":                       googleVeo3T2V31,
        "google/veo2":                                   veo2,
        "google/veo2-image-to-video":                    veo2,
        "google/veo3":                                   googleVeo3T2V,
        "veo-3.1-lite-generate-001":                     veoLiteGenerate,
        "veo2":                                          veo2,
        "veo2/image-to-video":                           veo2,

        // MARK: Kling — v1 through v3, the v2.5-turbo pair and the video-o1 entries
        "kling-video/v1.6/pro/image-to-video":       klingVideo,
        "kling-video/v1.6/pro/text-to-video":        klingVideo,
        "kling-video/v1.6/standard/image-to-video":  klingVideo,
        "kling-video/v1.6/standard/text-to-video":   klingVideo,
        "kling-video/v1/pro/image-to-video":         klingVideo,
        "kling-video/v1/pro/text-to-video":          klingVideo,
        "kling-video/v1/standard/image-to-video":    klingVideo,
        "kling-video/v1/standard/text-to-video":     klingVideo,
        "kling-video/v2.1/master/image-to-video":    klingVideo,
        "kling-video/v2.1/master/text-to-video":     klingVideo,
        "kling-video/v2.1/pro/image-to-video":       klingVideo,
        "kling-video/v2.1/standard/image-to-video":  klingVideo,
        "kling-video/v2.5-turbo/pro/image-to-video": klingv25TurboVideo,
        "kling-video/v2.5-turbo/pro/text-to-video":  klingVideo,
        "kling-video/v2.6/pro/image-to-video":       kling26,
        "kling-video/v2.6/pro/text-to-video":        kling26,
        "kling-video/v2/master/image-to-video":      klingVideo,
        "kling-video/v2/master/text-to-video":       klingVideo,
        "kling-video/v3/pro/image-to-video":         klingV3.filter { $0.wireKey != "aspect_ratio" },
        "kling-video/v3/pro/text-to-video":          klingV3,
        "kling-video/v3/standard/image-to-video":    klingV3.filter { $0.wireKey != "aspect_ratio" },
        "kling-video/v3/standard/text-to-video":     klingV3,
        "klingai/v2-master-image-to-video":          klingVideo,
        "klingai/v2-master-text-to-video":           klingVideo,
        "klingai/v2.1-master-image-to-video":        klingVideo,
        "klingai/v2.1-master-text-to-video":         klingVideo,
        "klingai/v2.5-turbo/pro/image-to-video":     klingv25TurboVideo,
        "klingai/v2.5-turbo/pro/text-to-video":      klingVideo,
        "klingai/video-o1-image-to-video":           klingVideo,
        "klingai/video-o1-reference-to-video":       klingVideo,
        "klingai/video-v2-6-pro-image-to-video":     kling26,
        "klingai/video-v2-6-pro-text-to-video":      kling26,
        "klingai/video-v3-pro-image-to-video":       klingV3.filter { $0.wireKey != "aspect_ratio" },
        "klingai/video-v3-pro-text-to-video":        klingV3,
        "klingai/video-v3-standard-image-to-video":  klingV3.filter { $0.wireKey != "aspect_ratio" },
        "klingai/video-v3-standard-text-to-video":   klingV3,

        // MARK: ByteDance — Seedance 1.0 / 1.5 / 2.0 and OmniHuman
        "bytedance/omnihuman":             omniHuman,
        "bytedance/omnihuman/v1.5":        omniHuman,
        "bytedance/seedance-1-0-pro":      seedance10Pro,
        "bytedance/seedance-1-0-pro-fast": seedanceVideo,
        "bytedance/seedance-1-5-pro":      seedanceVideo,
        "bytedance/seedance-2-0":          seedance20,
        "bytedance/seedance-2-0-fast":     seedance20,

        // MARK: OpenAI — Sora 2 and Sora 2 Pro
        "openai/sora-2-i2v":     sora2,
        "openai/sora-2-pro-i2v": sora2ProI2V,
        "openai/sora-2-pro-t2v": sora2ProI2V,
        "openai/sora-2-t2v":     sora2,
        "sora-2-i2v":            sora2,
        "sora-2-pro-i2v":        sora2ProI2V,
        "sora-2-pro-t2v":        sora2ProI2V,
        "sora-2-t2v":            sora2,

        // MARK: Minimax — Video-01 and the Hailuo pair
        "minimax/hailuo-02":       minimaxHailuo02,
        "minimax/hailuo-2.3":      hailuo23,
        "minimax/hailuo-2.3-fast": hailuo23,
        "video-01":                minimaxVideo01,

        // MARK: Runway — Gen-3a Turbo, Gen-4 Turbo and Gen-4 Aleph
        "gen3a_turbo":        runwayGen3Turbo,
        "runway/gen3a_turbo": runwayGen3Turbo,
        "runway/gen4_aleph":  runwayGen4Aleph,
        "runway/gen4_turbo":  runwayGen4,

        // MARK: Lightricks — LTXV-2 and LTXV-2 Fast
        "ltxv-2":                     ltxv2,
        "ltxv-2/fast":                ltxv2,
        "ltxv-2/image-to-video":      ltxv2,
        "ltxv-2/image-to-video/fast": ltxv2,
        "ltxv-2/text-to-video":       ltxv2,
        "ltxv-2/text-to-video/fast":  ltxv2,
        "ltxv/ltxv-2":                ltxv2,
        "ltxv/ltxv-2-fast":           ltxv2,

        // MARK: PixVerse — v5 and v5.5, t2v / i2v / transition
        "pixverse/v5-5-image-to-video": pixVerseV55T2V,
        "pixverse/v5-5-text-to-video":  pixVerseV55T2V,
        "pixverse/v5.5/image-to-video": pixVerseV55T2V,
        "pixverse/v5.5/text-to-video":  pixVerseV55T2V,
        "pixverse/v5/image-to-video":   pixVerseV55T2V,
        "pixverse/v5/text-to-video":    pixVerseV55T2V,
        "pixverse/v5/transition":       pixVerseV55T2V,

        // MARK: Luma — Ray 2 and Ray Flash 2
        "luma/ray-2":       lumaRay2,
        "luma/ray-flash-2": lumaRay2,

        // MARK: Kandinsky — Sber Kandinsky 5 t2v
        "kandinsky5/text-to-video":         kandinskyVideo,
        "kandinsky5/text-to-video/distill": kandinskyVideo,

        // MARK: Black Forest Labs — Flux Dev / Schnell / Pro / Realism / SRPO / Kontext / Flux 2
        "blackforestlabs/flux-2-max":      flux2Pro,
        "blackforestlabs/flux-2-max-edit": flux2ProEdit,
        "blackforestlabs/flux-2-pro":      flux2Pro,
        "blackforestlabs/flux-2-pro-edit": flux2ProEdit,
        "blackforestlabs/flux-pro-1.1":    flux2Pro,
        "flux-2":                          flux2Pro,
        "flux-2-max":                      flux2Pro,
        "flux-2-max/edit":                 flux2ProEdit,
        "flux-pro":                        fluxPro,
        "flux-realism":                    fluxRealism,
        "flux/dev":                        fluxDev,
        "flux/dev/image-to-image":         fluxSrpoI2i,
        "flux/kontext-max/image-to-image": fluxKontextMaxI2i,
        "flux/kontext-max/text-to-image":  fluxKontextMaxT2i,
        "flux/kontext-pro/image-to-image": fluxKontextProI2i,
        "flux/kontext-pro/text-to-image":  fluxKontextProT2i,
        "flux/schnell":                    fluxSchnell,
        "flux/srpo":                       fluxSrpo,

        // MARK: OpenAI — GPT Image 1 / 1-mini (the "extended" builder) and 1.5 / 2
        "gpt-image-1":             openAIGPTImage1Extended,
        "gpt-image-1-mini":        openAIGPTImage1Extended,
        "gpt-image-1.5":           openAIGPTImage1,
        "gpt-image-2":             openAIGPTImage1,
        "openai/gpt-image-1":      openAIGPTImage1Extended,
        "openai/gpt-image-1-5":    openAIGPTImage1,
        "openai/gpt-image-1-mini": openAIGPTImage1Extended,
        "openai/gpt-image-1.5":    openAIGPTImage1,
        "openai/gpt-image-2":      openAIGPTImage1,
        "openai/gpt-image-2.5-flare": openAIGPTImage1,
        "gpt-image-2.5-flare": openAIGPTImage1,
        "openai/gpt-image-2.5-sunburst": openAIGPTImage1,
        "gpt-image-2.5-sunburst": openAIGPTImage1,

        // MARK: Google — Imagen 3/4, Gemini 2.5 Flash Image and Gemini 3 Pro (a.k.a. Nano Banana Pro)
        "google/gemini-2.5-flash-image":          gemini25FlashImage,
        "google/gemini-2.5-flash-image-edit":     gemini25FlashImageEdit,
        "google/gemini-3-1-flash-lite-image":     nanoBanana2Lite,
        "google/gemini-3-pro-image-preview":      gemini3ProImagePreview,
        "google/gemini-3-pro-image-preview-edit": gemini3ProImagePreviewEdit,
        "google/gemini-3.1-flash-image-preview":  nanoBanana2,
        "google/imagen-3.0-generate-002":         googleImagen4Ultra,
        "google/imagen-4.0-fast-generate-001":    googleImagen4Ultra,
        "google/imagen-4.0-generate-001":         googleImagen4Ultra,
        "google/imagen-4.0-ultra-generate-001":   googleImagen4Ultra,
        "google/nano-banana-pro":                 gemini3ProImagePreview,
        "google/nano-banana-pro-edit":            gemini3ProImagePreviewEdit,
        "imagen-3.0-generate-002":                googleImagen4Ultra,
        "imagen-4.0-generate-001":                googleImagen4Ultra,
        "imagen-4.0-ultra-generate-001":          googleImagen4Ultra,
        "nano-banana-2":                          nanoBanana2,

        // MARK: Kling — the Image O1 still-image model
        "klingai/image-o1": klingImageO1,

        // MARK: ByteDance — Seedream v4 / 4.5 / 5.0-lite, and Alibaba's Z-Image Turbo, which shares
        // the Seedream v4 view and builder outright.
        "alibaba/z-image-turbo":               seedreamV4,
        "bytedance/dola-seedream-5-0-pro":     seedream50Pro,
        "bytedance/seedream-4-5":              seedream45,
        // Was `seedreamV4Edit` until 2026-07-28, which is a real table for a real family — but the
        // wrong one for this id. The v4 edit models publish `image_size` as the fal-style preset set
        // (`square_hd`, `landscape_16_9`, …); **seedream 5.0 lite and seedream 4.5 publish
        // `["2K", "4K"]`**, and neither documents `num_images` or `enable_safety_checker`. So this id
        // was sending `image_size: "square_hd"` plus two undocumented keys and failing validation on
        // every generation, with no user action required to trigger it. `seedream45` already had the
        // right vocabulary and emits only this model's documented keys, so this is a re-registration,
        // not a new table. Verified against the captured schema for both ids; their catalog rows are
        // identical on image routing (`imageInputParam: "image_urls"`, `maxInputImages: 14`).
        "bytedance/seedream-5-0-lite":         seedream45,
        "bytedance/seedream-5-0-pro":          seedream50Pro,
        "bytedance/seedream-v4-edit":          seedreamV4Edit,
        "bytedance/seedream-v4-text-to-image": seedreamV4,
        "bytedance/seedream/v4/edit":          seedreamV4Edit,
        "bytedance/seedream/v4/text-to-image": seedreamV4,
        "z-image-turbo":                       seedreamV4,
        "z-image/turbo":                       seedreamV4,

        // MARK: Alibaba — Qwen Image, Qwen Image Edit, and the Wan t2i / image family
        "alibaba/qwen-image":         alibabaQwenImage,
        "alibaba/qwen-image-2.0":     wanImageEdit,
        "alibaba/qwen-image-edit":    alibabaQwenImageEdit,
        "alibaba/wan2.2-t2i-flash":   wanImage,
        "alibaba/wan2.2-t2i-plus":    wanImage,
        "alibaba/wan2.5-t2i-preview": wanImage,
        "alibaba/wan2.6-image":       wanImageEdit,
        "alibaba/wan2.7-image":       wanImageEdit,
        "alibaba/wan2.7-image-pro":   wanImageEdit,
        "qwen-image-2.0":             wanImageEdit,
        "wan2.2-t2i-flash":           wanImage,
        "wan2.2-t2i-plus":            wanImage,
        "wan2.5-t2i-preview":         wanImage,
        "wan2.6-image":               wanImageEdit,
        "wan2.7-image":               wanImageEdit,
        "wan2.7-image-pro":           wanImageEdit,

        // MARK: Tencent — Hunyuan Image v3
        "hunyuan-image/v3/text-to-image":         hunyuanImageV3,
        "hunyuan/hunyuan-image-v3-text-to-image": hunyuanImageV3,

        // MARK: Stability AI — SD 3 Medium and SD 3.5 Large
        "stable-diffusion-v3-medium": stableDiffusionV3Medium,
        "stable-diffusion-v35-large": stableDiffusionV35Large,

        // MARK: Recraft — Recraft V3
        "recraft-v3": recraftV3,

        // MARK: Topaz — the two sharpen models
        "topaz-labs/sharpen":     topazSharpen,
        "topaz-labs/sharpen-gen": topazSharpenGen,

        // MARK: xAI — Grok Imagine
        "x-ai/grok-imagine-image":     grokImagine,
        "x-ai/grok-imagine-image-pro": grokImagine,

        // MARK: Reve — Create Image and Remix Edit
        "reve/create-image":     reveImage,
        "reve/remix-edit-image": reveImage,

        // MARK: Models with no parameters at all — `defaultJSONBuilder` returns `[:]` and
        // `buildDefaultParamsView` returns `EmptyView()`, so the honest table is the empty one.
        "bytedance/uso":   noParameters,
        "reve/edit-image": noParameters
    ]
}
