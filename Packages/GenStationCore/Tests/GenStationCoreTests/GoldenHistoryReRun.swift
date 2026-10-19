// Golden history re-run fixtures (Stage 2, Task 11).
//
// For each of the 32 distinct payload shapes actually present in a real
// `history_v2.json`, the `ModelParameters` the model's legacy `ParameterParser` reconstructed —
// recorded at `92e07cf`, before the parsers were deleted.
//
// History stores the submitted payload string and no parameters, so decoding it is the only way
// a past generation can be replayed. `HistoryReRunTests` asserts `ParamDecoder` lands on exactly
// these values, which is the strongest evidence in the package that the migration is
// behaviour-preserving on **real user data** rather than on synthetic probes.
//
// Index-aligned with `HistoryReRunTests.realPayloads`; that test pins both counts.
//
// GENERATED. Do not hand-edit.

import Foundation
import GenStationCore

enum GoldenHistoryReRun {

    /// One entry per shape in `HistoryReRunTests.realPayloads`, in the same order:
    /// the `ModelParameters` the model's legacy `ParameterParser` reconstructed.
    static let expected: [ModelParameters] = [
        /* bytedance/seedream-v4-text-to-image */ ModelParameters(numImages: 1, enableSafetyChecker: true, imageSizeMode: "custom", customWidth: 1920, customHeight: 1080),
        /* openai/sora-2-pro-i2v */ ModelParameters(duration: 4),
        /* bytedance/seedream-4-5 */ ModelParameters(imageSizeMode: "preset", imageSizePreset: "2K"),
        /* google/nano-banana-pro-edit */ ModelParameters(numImages: 1, geminiResolution: "2K", aspectRatio: "9:16"),
        /* google/nano-banana-pro-edit */ ModelParameters(numImages: 2, geminiResolution: "4K"),
        /* google/nano-banana-pro-edit */ ModelParameters(numImages: 1, aspectRatio: "1:1"),
        /* bytedance/seedream-4-5 */ ModelParameters(imageSizeMode: "custom", customWidth: 2048, customHeight: 4096),
        /* google/nano-banana-pro-edit */ ModelParameters(numImages: 1, geminiResolution: "2K", aspectRatio: "9:16"),
        /* google/nano-banana-pro-edit */ ModelParameters(numImages: 1),
        /* klingai/v2.5-turbo/pro/image-to-video */ ModelParameters(negativePrompt: nil, guidanceScale: 0.5),
        /* alibaba/wan2.5-i2v-preview */ ModelParameters(negativePrompt: nil),
        /* google/nano-banana-pro-edit */ ModelParameters(numImages: 2, geminiResolution: "2K", aspectRatio: "1:1"),
        /* google/nano-banana-pro-edit */ ModelParameters(numImages: 1, geminiResolution: "2K", aspectRatio: "1:1"),
        /* flux/srpo */ ModelParameters(numImages: 1, enableSafetyChecker: true, imageSizeMode: "preset", imageSizePreset: "landscape_4_3", guidanceScale: 4.5, numInferenceSteps: 28),
        /* klingai/v2.5-turbo/pro/image-to-video */ ModelParameters(guidanceScale: 0.5),
        /* alibaba/wan2.5-i2v-preview */ ModelParameters(resolution: "480p"),
        /* runway/gen4_turbo */ ModelParameters(),
        /* ltxv/ltxv-2 */ ModelParameters(duration: 8, frameRate: 25, resolution: "1080p"),
        /* google/veo-3.1-i2v-fast */ ModelParameters(duration: 8),
        /* alibaba/wan-2-6-i2v */ ModelParameters(negativePrompt: nil, aspectRatio: nil, shotType: "single"),
        /* bytedance/seedream-4-5 */ ModelParameters(imageSizeMode: "preset", imageSizePreset: "2K"),
        /* google/nano-banana-pro */ ModelParameters(numImages: 1),
        /* hunyuan/hunyuan-image-v3-text-to-image */ ModelParameters(numImages: 1, enableSafetyChecker: true, imageSizeMode: "preset", imageSizePreset: "square_hd", guidanceScale: 7.5, numInferenceSteps: 28),
        /* google/nano-banana-pro-edit */ ModelParameters(numImages: 1, aspectRatio: "9:16"),
        /* bytedance/omnihuman/v1.5 */ ModelParameters(audioURL: "https://example.com/audio/clip1.wav"),
        /* bytedance/omnihuman */ ModelParameters(audioURL: "https://example.com/audio/clip3.wav"),
        /* alibaba/qwen-image */ ModelParameters(numImages: 1, enableSafetyChecker: true, guidanceScale: 7.5),
        /* openai/gpt-image-1-5 */ ModelParameters(),
        /* stable-diffusion-v35-large */ ModelParameters(numImages: 1, enableSafetyChecker: true, imageSizeMode: "preset", imageSizePreset: "square_hd", guidanceScale: 4.5, numInferenceSteps: 40),
        /* alibaba/z-image-turbo */ ModelParameters(numImages: 1, enableSafetyChecker: true, imageSizeMode: "preset", imageSizePreset: "square_hd"),
        /* flux/schnell */ ModelParameters(numImages: 1, enableSafetyChecker: true, imageSizeMode: "preset", imageSizePreset: "landscape_4_3", numInferenceSteps: 4),
        /* ltxv/ltxv-2-fast */ ModelParameters(duration: 6, frameRate: 25, resolution: "1080p"),
    ]
}
