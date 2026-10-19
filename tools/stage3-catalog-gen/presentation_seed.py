#!/usr/bin/env python3
"""Stage 3 Task 12 — the `family` column for the 122 canonical catalog rows.

`displayName` is NOT here. It comes from the captured /models fixture's `info.name`, with the
exceptions listed in Catalog/Models/PresentationOverrides.swift, which apply_presentation.py parses
directly. Duplicating either of those here would create the second list this stage exists to delete.

`family` is ours. It seeds from `info.developer` — the 122 rows below are grouped by vendor, in the
order the vendor-sorted listing prints them — and splits within a vendor by product line. Two rows
share a family iff they are the same product line from the same vendor, differing only by tier,
speed or direction. A version bump starts a new family.

Three families carry a "(via AI/ML API)" suffix because the same product is also reachable through
its native provider (Gemini in Task 15, Grok in Task 14), and `family` is global: without the
suffix `Catalog.selectable(task:)` would merge the AI/ML-routed row and the native row into one
picker group.

**Two deliberate exceptions to "a version bump starts a new family" (recorded 2026-07-27, Task 26):**
"GPT Image" spans `gpt-image-1`, `-1-mini`, `-1.5` and `-2`, and "FLUX Pro" spans `flux-pro-1.1` and
`flux-pro`. Both stay one family across versions on purpose — these read as a single
product line to a picker, not as generations to split apart — and neither is a bug to fix. Task 23's
model-browse surface renders one undifferentiated "GPT Image" / "FLUX Pro" group for exactly this
reason. `family` values are otherwise unchanged; this note only explains the table, per Task 26.
"""

FAMILY = {
    # --- Alibaba Cloud
    "alibaba/qwen-image":                            "Qwen Image",
    "alibaba/qwen-image-2.0":                        "Qwen Image",
    "alibaba/qwen-image-edit":                       "Qwen Image",
    "alibaba/wan2.1-t2v-plus":                       "Wan 2.1",
    "alibaba/wan2.1-t2v-turbo":                      "Wan 2.1",
    "alibaba/wan2.2-i2v-plus":                       "Wan 2.2",
    "alibaba/wan2.2-t2i-plus":                       "Wan 2.2",
    "alibaba/wan2.2-t2v-plus":                       "Wan 2.2",
    "alibaba/wan2.5-i2v-preview":                    "Wan 2.5",
    "alibaba/wan2.5-t2v-preview":                    "Wan 2.5",
    "alibaba/wan-2-6-i2v":                           "Wan 2.6",
    "alibaba/wan-2-6-r2v":                           "Wan 2.6",
    "alibaba/wan-2-6-t2v":                           "Wan 2.6",
    "alibaba/wan2.6-image":                          "Wan 2.6",
    "alibaba/wan2.7-i2v":                            "Wan 2.7",
    "alibaba/wan2.7-r2v":                            "Wan 2.7",
    "alibaba/wan2.7-t2v":                            "Wan 2.7",
    "alibaba/z-image-turbo":                         "Z-Image",
    # --- Black Forest Labs
    "blackforestlabs/flux-2-max-edit":               "FLUX 2",
    "blackforestlabs/flux-2-pro":                    "FLUX 2",
    "blackforestlabs/flux-2-pro-edit":               "FLUX 2",
    "flux/dev":                                      "FLUX Dev",
    "flux/dev/image-to-image":                       "FLUX Dev",
    "flux/kontext-max/image-to-image":               "FLUX Kontext",
    "flux/kontext-max/text-to-image":                "FLUX Kontext",
    "flux/kontext-pro/image-to-image":               "FLUX Kontext",
    "flux/kontext-pro/text-to-image":                "FLUX Kontext",
    "blackforestlabs/flux-pro-1.1":                  "FLUX Pro",
    "flux-pro":                                      "FLUX Pro",
    "flux-realism":                                  "FLUX Realism",
    "flux/srpo":                                     "FLUX SRPO",
    "flux/schnell":                                  "FLUX Schnell",
    # --- ByteDance
    "bytedance/omnihuman":                           "OmniHuman",
    "bytedance/seedance-1-0-pro":                    "Seedance 1.0",
    "bytedance/seedance-1-0-pro-fast":               "Seedance 1.0",
    "bytedance/seedance-1-5-pro":                    "Seedance 1.5",
    "bytedance/seedance-2-0":                        "Seedance 2.0",
    "bytedance/seedream/v4/edit":                    "Seedream 4",
    "bytedance/seedream/v4/text-to-image":           "Seedream 4",
    "bytedance/seedream-4-5":                        "Seedream 4.5",
    "bytedance/seedream-5-0-lite":                   "Seedream 5.0",
    "bytedance/uso":                                 "USO",
    # --- Google
    "google/gemini-2.5-flash-image":                 "Gemini 2.5 Flash Image (via AI/ML API)",
    "google/gemini-2.5-flash-image-edit":            "Gemini 2.5 Flash Image (via AI/ML API)",
    "google/gemini-3-pro-image-preview":             "Gemini 3 Pro Image (via AI/ML API)",
    "google/gemini-3-pro-image-preview-edit":        "Gemini 3 Pro Image (via AI/ML API)",
    "google/imagen-3.0-generate-002":                "Imagen 3",
    "google/imagen-4.0-fast-generate-001":           "Imagen 4",
    "google/imagen-4.0-generate-001":                "Imagen 4",
    "google/imagen-4.0-ultra-generate-001":          "Imagen 4",
    "google/veo2":                                   "Veo 2",
    "veo2/image-to-video":                           "Veo 2",
    "google/veo-3.0-fast":                           "Veo 3",
    "google/veo-3.0-i2v":                            "Veo 3",
    "google/veo-3.0-i2v-fast":                       "Veo 3",
    "google/veo3":                                   "Veo 3",
    "google/veo-3.1-first-last-image-to-video":      "Veo 3.1",
    "google/veo-3.1-first-last-image-to-video-fast": "Veo 3.1",
    "google/veo-3.1-i2v":                            "Veo 3.1",
    "google/veo-3.1-i2v-fast":                       "Veo 3.1",
    "google/veo-3.1-lite-generate-001":              "Veo 3.1",
    "google/veo-3.1-reference-to-video":             "Veo 3.1",
    "google/veo-3.1-t2v":                            "Veo 3.1",
    "google/veo-3.1-t2v-fast":                       "Veo 3.1",
    # --- Kling AI
    "kling-video/v1/pro/image-to-video":             "Kling 1.0",
    "kling-video/v1/pro/text-to-video":              "Kling 1.0",
    "kling-video/v1/standard/image-to-video":        "Kling 1.0",
    "kling-video/v1/standard/text-to-video":         "Kling 1.0",
    "kling-video/v1.6/pro/image-to-video":           "Kling 1.6",
    "kling-video/v1.6/pro/text-to-video":            "Kling 1.6",
    "kling-video/v1.6/standard/image-to-video":      "Kling 1.6",
    "kling-video/v1.6/standard/text-to-video":       "Kling 1.6",
    "kling-video/v2/master/image-to-video":          "Kling 2.0",
    "kling-video/v2/master/text-to-video":           "Kling 2.0",
    "kling-video/v2.1/master/image-to-video":        "Kling 2.1",
    "kling-video/v2.1/master/text-to-video":         "Kling 2.1",
    "kling-video/v2.1/pro/image-to-video":           "Kling 2.1",
    "kling-video/v2.1/standard/image-to-video":      "Kling 2.1",
    "kling-video/v2.5-turbo/pro/image-to-video":     "Kling 2.5",
    "kling-video/v2.5-turbo/pro/text-to-video":      "Kling 2.5",
    "kling-video/v2.6/pro/image-to-video":           "Kling 2.6",
    "kling-video/v2.6/pro/text-to-video":            "Kling 2.6",
    "kling-video/v3/standard/image-to-video":        "Kling 3.0",
    "kling-video/v3/standard/text-to-video":         "Kling 3.0",
    "klingai/image-o1":                              "Kling O1",
    "klingai/video-o1-image-to-video":               "Kling O1",
    "klingai/video-o1-reference-to-video":           "Kling O1",
    # --- LTXV
    "ltxv-2/fast":                                   "LTX Video 2",
    "ltxv/ltxv-2":                                   "LTX Video 2",
    # --- Luma AI
    "luma/ray-2":                                    "Luma Ray",
    "luma/ray-flash-2":                              "Luma Ray",
    # --- Minimax AI
    "minimax/hailuo-02":                             "MiniMax Hailuo",
    "minimax/hailuo-2.3":                            "MiniMax Hailuo",
    "minimax/hailuo-2.3-fast":                       "MiniMax Hailuo",
    "minimax/video-01":                              "MiniMax Video",
    # --- Open AI
    "openai/gpt-image-1":                            "GPT Image",
    "openai/gpt-image-1-mini":                       "GPT Image",
    "openai/gpt-image-1.5":                          "GPT Image",
    "openai/gpt-image-2":                            "GPT Image",
    "openai/sora-2-i2v":                             "Sora 2",
    "openai/sora-2-pro-i2v":                         "Sora 2",
    "openai/sora-2-pro-t2v":                         "Sora 2",
    "openai/sora-2-t2v":                             "Sora 2",
    # --- Pixverse
    "pixverse/v5/image-to-video":                    "PixVerse V5",
    "pixverse/v5/text-to-video":                     "PixVerse V5",
    "pixverse/v5/transition":                        "PixVerse V5",
    "pixverse/v5.5/image-to-video":                  "PixVerse V5.5",
    "pixverse/v5.5/text-to-video":                   "PixVerse V5.5",
    # --- Recraft AI
    "recraft-v3":                                    "Recraft",
    # --- Reve AI
    "reve/create-image":                             "Reve",
    "reve/edit-image":                               "Reve",
    "reve/remix-edit-image":                         "Reve",
    # --- Runway ML
    "runway/gen3a_turbo":                            "Runway Gen-3",
    "runway/gen4_aleph":                             "Runway Gen-4",
    "runway/gen4_turbo":                             "Runway Gen-4",
    # --- Sber AI
    "kandinsky5/text-to-video":                      "Kandinsky 5",
    # --- Stability AI
    "stable-diffusion-v3-medium":                    "Stable Diffusion 3",
    "stable-diffusion-v35-large":                    "Stable Diffusion 3.5",
    # --- Tencent
    "hunyuan/hunyuan-image-v3-text-to-image":        "Hunyuan Image",
    # --- Topaz Labs
    "topaz-labs/sharpen":                            "Topaz Sharpen",
    "topaz-labs/sharpen-gen":                        "Topaz Sharpen",
    # --- X AI
    "x-ai/grok-imagine-image":                       "Grok Imagine (via AI/ML API)",
}
