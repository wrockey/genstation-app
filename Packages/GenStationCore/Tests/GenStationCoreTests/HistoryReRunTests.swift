// Stage 2, Task 10b — history re-run against REAL history entries.
//
// `HistoryView.loadSubmissionData` is the only path that can replay a past generation: a history
// entry stores the literal submitted payload string and **no** `ModelParameters`, so re-run has to
// reconstruct them by decoding that payload. Task 10b moves that decode from the model's legacy
// `ParameterParser` to `ParamDecoder`, which makes it the highest-consequence of the 13 call sites —
// a divergence here silently re-runs a past generation with different parameters.
//
// The cases below are the **32 distinct (model id, key set) payload shapes** present in the live
// history file (`history_v2.json` in the app's Application Support directory),
// transcribed verbatim from it with two redactions that touch no
// descriptor key: prompt text is replaced with "[prompt]", and base64 image data URIs are elided.
// They span 21 model ids, image and video, and both branches of the `image_size` composite — the
// object branch appears in real data exactly once.
//
// Inline Swift literals rather than a resource file, following `HistoryItemCodingTests`: the package
// manifest declares no `resources:` clause.

import XCTest
@testable import GenStationCore

final class HistoryReRunTests: XCTestCase {

    /// Every distinct payload shape in the live history file, with the id the entry stored.
    static let realPayloads: [(id: String, payload: String)] = [
        (id: "bytedance/seedream-v4-text-to-image", payload: #"""
          {
            "image_size": {
              "height": 1080,
              "width": 1920
            },
            "model": "bytedance/seedream-v4-text-to-image",
            "prompt": "[prompt]"
          }
          """#),
        (id: "openai/sora-2-pro-i2v", payload: #"""
          {
            "aspect_ratio": "16:9",
            "duration": 4,
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "openai/sora-2-pro-i2v",
            "prompt": "[prompt]",
            "resolution": "720p"
          }
          """#),
        (id: "bytedance/seedream-4-5", payload: #"""
          {
            "image_size": "2K",
            "model": "bytedance/seedream-4-5",
            "prompt": "[prompt]",
            "watermark": false
          }
          """#),
        (id: "google/nano-banana-pro-edit", payload: #"""
          {
            "aspect_ratio": "9:16",
            "image_urls": [
              "data:image/jpeg;base64,<elided>"
            ],
            "model": "google/nano-banana-pro-edit",
            "prompt": "[prompt]",
            "resolution": "2K"
          }
          """#),
        (id: "google/nano-banana-pro-edit", payload: #"""
          {
            "aspect_ratio": "16:9",
            "image_urls": [
              "data:image/jpeg;base64,<elided>"
            ],
            "model": "google/nano-banana-pro-edit",
            "num_images": 2,
            "prompt": "[prompt]",
            "resolution": "4K"
          }
          """#),
        (id: "google/nano-banana-pro-edit", payload: #"""
          {
            "image_urls": [
              "data:image/jpeg;base64,<elided>"
            ],
            "model": "google/nano-banana-pro-edit",
            "prompt": "[prompt]"
          }
          """#),
        (id: "bytedance/seedream-4-5", payload: #"""
          {
            "image_size": {
              "height": 4096,
              "width": 2048
            },
            "image_urls": [
              "data:image/jpeg;base64,<elided>"
            ],
            "model": "bytedance/seedream-4-5",
            "prompt": "[prompt]",
            "watermark": false
          }
          """#),
        (id: "google/nano-banana-pro-edit", payload: #"""
          {
            "aspect_ratio": "9:16",
            "image_urls": [
              "data:image/jpeg;base64,<elided>"
            ],
            "model": "google/nano-banana-pro-edit",
            "prompt": "[prompt]",
            "resolution": "2K",
            "response_format": "b64_json"
          }
          """#),
        (id: "google/nano-banana-pro-edit", payload: #"""
          {
            "aspect_ratio": "16:9",
            "image_urls": [
              "data:image/jpeg;base64,<elided>"
            ],
            "model": "google/nano-banana-pro-edit",
            "prompt": "[prompt]"
          }
          """#),
        (id: "klingai/v2.5-turbo/pro/image-to-video", payload: #"""
          {
            "duration": 5,
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "klingai/v2.5-turbo/pro/image-to-video",
            "prompt": "[prompt]"
          }
          """#),
        (id: "alibaba/wan2.5-i2v-preview", payload: #"""
          {
            "duration": 5,
            "enable_prompt_expansion": true,
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "alibaba/wan2.5-i2v-preview",
            "prompt": "[prompt]",
            "resolution": "720p"
          }
          """#),
        (id: "google/nano-banana-pro-edit", payload: #"""
          {
            "image_urls": [
              "data:image/jpeg;base64,<elided>",
              "data:image/jpeg;base64,<elided>"
            ],
            "model": "google/nano-banana-pro-edit",
            "num_images": 2,
            "prompt": "[prompt]",
            "resolution": "2K"
          }
          """#),
        (id: "google/nano-banana-pro-edit", payload: #"""
          {
            "image_urls": [
              "data:image/jpeg;base64,<elided>"
            ],
            "model": "google/nano-banana-pro-edit",
            "prompt": "[prompt]",
            "resolution": "2K"
          }
          """#),
        (id: "flux/srpo", payload: #"""
          {
            "acceleration": "regular",
            "image_size": "landscape_4_3",
            "model": "flux/srpo",
            "prompt": "[prompt]"
          }
          """#),
        (id: "klingai/v2.5-turbo/pro/image-to-video", payload: #"""
          {
            "duration": 5,
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "klingai/v2.5-turbo/pro/image-to-video",
            "negative_prompt": "",
            "prompt": "[prompt]"
          }
          """#),
        (id: "alibaba/wan2.5-i2v-preview", payload: #"""
          {
            "duration": 5,
            "enable_prompt_expansion": true,
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "alibaba/wan2.5-i2v-preview",
            "negative_prompt": "",
            "prompt": "[prompt]",
            "resolution": "480p"
          }
          """#),
        (id: "runway/gen4_turbo", payload: #"""
          {
            "aspect_ratio": "16:9",
            "duration": 5,
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "runway/gen4_turbo",
            "prompt": "[prompt]"
          }
          """#),
        (id: "ltxv/ltxv-2", payload: #"""
          {
            "aspect_ratio": "16:9",
            "duration": 8,
            "fps": 25,
            "generate_audio": true,
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "ltxv/ltxv-2",
            "prompt": "[prompt]",
            "resolution": "1080p"
          }
          """#),
        (id: "google/veo-3.1-i2v-fast", payload: #"""
          {
            "aspect_ratio": "16:9",
            "duration": 8,
            "generate_audio": true,
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "google/veo-3.1-i2v-fast",
            "prompt": "[prompt]",
            "resolution": "720p"
          }
          """#),
        (id: "alibaba/wan-2-6-i2v", payload: #"""
          {
            "aspect_ratio": "16:9",
            "duration": 5,
            "enhance_prompt": true,
            "generate_audio": true,
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "alibaba/wan-2-6-i2v",
            "prompt": "[prompt]",
            "resolution": "720p",
            "shot_type": "single"
          }
          """#),
        (id: "bytedance/seedream-4-5", payload: #"""
          {
            "image_size": "2K",
            "model": "bytedance/seedream-4-5",
            "prompt": "[prompt]",
            "response_format": "b64_json",
            "watermark": false
          }
          """#),
        (id: "google/nano-banana-pro", payload: #"""
          {
            "aspect_ratio": "16:9",
            "model": "google/nano-banana-pro",
            "prompt": "[prompt]",
            "response_format": "b64_json"
          }
          """#),
        (id: "hunyuan/hunyuan-image-v3-text-to-image", payload: #"""
          {
            "enable_prompt_expansion": true,
            "enable_safety_checker": true,
            "guidance_scale": 7.5,
            "image_size": "square_hd",
            "model": "hunyuan/hunyuan-image-v3-text-to-image",
            "num_images": 1,
            "num_inference_steps": 28,
            "prompt": "[prompt]",
            "response_format": "b64_json"
          }
          """#),
        (id: "google/nano-banana-pro-edit", payload: #"""
          {
            "aspect_ratio": "9:16",
            "image_urls": [
              "data:image/jpeg;base64,<elided>"
            ],
            "model": "google/nano-banana-pro-edit",
            "prompt": "[prompt]",
            "response_format": "b64_json"
          }
          """#),
        (id: "bytedance/omnihuman/v1.5", payload: #"""
          {
            "audio_url": "https://example.com/audio/clip1.wav",
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "bytedance/omnihuman/v1.5",
            "prompt": "[prompt]"
          }
          """#),
        (id: "bytedance/omnihuman", payload: #"""
          {
            "audio_url": "https://example.com/audio/clip3.wav",
            "image_url": "data:image/jpeg;base64,<elided>",
            "model": "bytedance/omnihuman",
            "prompt": "[prompt]"
          }
          """#),
        (id: "alibaba/qwen-image", payload: #"""
          {
            "enable_safety_checker": true,
            "guidance_scale": 7.5,
            "model": "alibaba/qwen-image",
            "num_images": 1,
            "prompt": "[prompt]",
            "response_format": "b64_json"
          }
          """#),
        (id: "openai/gpt-image-1-5", payload: #"""
          {
            "model": "openai/gpt-image-1-5",
            "prompt": "[prompt]",
            "response_format": "b64_json"
          }
          """#),
        (id: "stable-diffusion-v35-large", payload: #"""
          {
            "enable_safety_checker": true,
            "guidance_scale": 4.5,
            "image_size": "square_hd",
            "model": "stable-diffusion-v35-large",
            "negative_prompt": "",
            "num_images": 1,
            "num_inference_steps": 40,
            "prompt": "[prompt]",
            "response_format": "b64_json"
          }
          """#),
        (id: "alibaba/z-image-turbo", payload: #"""
          {
            "model": "alibaba/z-image-turbo",
            "prompt": "[prompt]",
            "response_format": "b64_json"
          }
          """#),
        (id: "flux/schnell", payload: #"""
          {
            "enable_safety_checker": true,
            "image_size": "landscape_4_3",
            "model": "flux/schnell",
            "num_images": 1,
            "num_inference_steps": 4,
            "prompt": "[prompt]",
            "response_format": "b64_json"
          }
          """#),
        (id: "ltxv/ltxv-2-fast", payload: #"""
          {
            "aspect_ratio": "16:9",
            "duration": 6,
            "fps": 25,
            "generate_audio": true,
            "model": "ltxv/ltxv-2-fast",
            "prompt": "[prompt]",
            "resolution": "1080p"
          }
          """#),
    ]

    private func parsed(_ text: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try XCTUnwrap(object as? [String: Any])
    }

    /// The migration is behaviour-preserving on real data: decoding an actual stored payload with
    /// the model's descriptors yields the same `ModelParameters` — all 41 fields, `ModelParameters`
    /// is `Equatable` — as the legacy parser it replaces.
    ///
    /// Task 11 deleted the parsers, so the right-hand side is `GoldenHistoryReRun.expected`: what
    /// each model's legacy parser produced from these exact payloads, recorded at `92e07cf` before
    /// the deletion. This is the strongest evidence in the package that the migration is
    /// behaviour-preserving on **real user data** rather than on synthetic probes.
    func testEveryRealHistoryPayloadReRunsToTheSameParameters() throws {
        XCTAssertEqual(GoldenHistoryReRun.expected.count, Self.realPayloads.count,
                       "the recording and the corpus have drifted out of alignment")

        for (index, (id, text)) in Self.realPayloads.enumerated() {
            let json = try parsed(text)
            guard let descriptors = ParamCatalog.descriptors(forModelId: id) else {
                XCTFail("history entry names \(id), which has no descriptor table"); continue
            }

            var viaDescriptors = ModelParameters()
            ParamDecoder.decode(descriptors, from: json, into: &viaDescriptors)

            XCTAssertEqual(viaDescriptors, GoldenHistoryReRun.expected[index],
                           "re-run diverges for the stored \(id) payload (shape \(index))")
        }
    }

    /// Keys the descriptor system never claims to round-trip at all — `model` and `prompt` are the
    /// two the app injects outside `ModelParameters` before this loop even starts; these three join
    /// them for the same reason, verified against the actual production sources rather than assumed:
    ///   * `response_format` has no case anywhere in `ModelParameters`/`ParamDescriptor`. It is set
    ///     by app-layer request-building code (`ContentView+Generation.swift`, `MCPService.swift`),
    ///     never by the descriptor tables this test exercises.
    ///   * `image_url` / `image_urls` likewise have no `ModelParameters` case. The attached input
    ///     image is injected via `CatalogModel.imageInputParam` / `secondImageParam` — a wire-key
    ///     *name*, not a descriptor-driven value — entirely outside `ParamDecoder`/`ParamEncoder`.
    ///     (`audio_url`, by contrast, IS a real `.audioURL` field and round-trips normally; it is
    ///     not in this set.)
    /// Exact equality below (not a one-way filter) is deliberate: this stage has had eight checks
    /// that silently tolerated more than they meant to, and a `continue` that quietly widens to a
    /// key nobody added here is the same failure mode. If a 4th unmodeled key starts appearing, or
    /// one of these three stops appearing, the equality assertion — not this comment — is what
    /// notices.
    private static let unmodeledKeys: Set<String> = ["response_format", "image_url", "image_urls"]

    /// A dropped `(id, key)` that is not unmodeled (the key IS a real descriptor field) but is a
    /// documented, deliberate legacy behavior rather than a bug. Keyed by id *and* key, not by key
    /// alone — a bare key exception would also hide the same key silently dropping on some other
    /// model, which is the failure this whole file exists to catch.
    private struct DocumentedException: Hashable { let id: String; let key: String }

    private static let documentedLegacyExceptions: Set<DocumentedException> = [
        // `VideoAlibaba.swift`'s `wan26VideoI2V` table (~line 448): the i2v parser runs the shared
        // t2v aspect-ratio descriptor and then the legacy builder explicitly cleared it for i2v
        // generations. `visibleWhen: .isTextToVideo` + `parseFallback: .setNil` preserve that on
        // purpose — the table's own comment names this exact test as how it was found.
        DocumentedException(id: "alibaba/wan-2-6-i2v", key: "aspect_ratio"),
    ]

    /// Known, open drift between what a real stored payload carried and what today's descriptor
    /// table re-emits for that SAME modeled field — not unmodeled (not in `unmodeledKeys`), not a
    /// documented legacy clear (not in `documentedLegacyExceptions`), just an unresolved bug.
    ///
    /// Pinned by exact equality rather than left permanently red: a suite that is red on every run
    /// teaches "these two failures are normal," which is how a gate dies — the next real regression
    /// arrives as a third familiar-looking failure nobody reads. An exact-equality pin tells the
    /// same truth and additionally fails the moment either drift is fixed without this set being
    /// updated, or a third one appears.
    ///
    /// **Do not fix by editing `VideoAlibaba.swift`, `ImageBlackForestLabs.swift`, or any
    /// encoder/decoder** — Stage 2 froze the wire, and which spelling (or whether either table
    /// should change at all) is an open question for the drift ledger, not something to silently
    /// patch here. Recorded as group-A rows awaiting approval in the drift ledger.
    private struct KnownDrift: Hashable { let id: String; let key: String }

    private static let knownUnresolvedDrift: Set<KnownDrift> = [
        // `wan25I2V` (`VideoAlibaba.swift:262`) emits wireKey "enhance_prompt" for `.enhancePrompt`.
        // Every real `alibaba/wan2.5-i2v-preview` history entry recorded the key as
        // "enable_prompt_expansion" instead. `wan26VideoI2V`'s own table correctly uses
        // "enhance_prompt" for *its* corpus, which is why this reads as `wan25I2V` having inherited
        // wan2.6's wire key rather than keeping wan2.5's own — a functional gap, not just a re-run
        // one: every CURRENT generation with this model would emit the same wrong key, so the
        // setting has likely never worked for wan2.5-i2v-preview, not only old history re-runs.
        KnownDrift(id: "alibaba/wan2.5-i2v-preview", key: "enable_prompt_expansion"),
        // `fluxSrpo` (`ImageBlackForestLabs.swift`, `flux/srpo` section) has no `acceleration`
        // descriptor at all. Also a functional gap, not just a re-run one: there is no UI control
        // for it today, so a user cannot set `acceleration` on `flux/srpo` under any circumstance —
        // it is not only old history that loses the setting on re-run.
        KnownDrift(id: "flux/srpo", key: "acceleration"),
    ]

    /// Keys a re-run deliberately comes back with a **different value** for, because the stored value
    /// was one the model's own schema rejects.
    ///
    /// The three sets above are about keys that get *dropped*; this one is about a key that survives
    /// and is corrected. `google/veo-3.1-i2v-fast` publishes `resolution: ["720P", "1080P", "4K"]` and
    /// the app sent the shared struct default `"720p"` on every request, so every entry in this corpus
    /// records a generation that failed validation. Re-running it now emits `"720P"` — the same
    /// resolution, spelled the way the model spells it (`ParamEncoder.schemaChecked`, rule 2).
    ///
    /// Round-tripping the old value byte-for-byte would mean faithfully reproducing a request the API
    /// refuses, which is the opposite of what re-run is for. Pinned as an exact old → new pair and
    /// asserted in both directions, so neither a third value nor a silent revert passes.
    private struct CorrectedOnReRun: Hashable { let id: String; let key: String; let was: String; let now: String }
    private static let schemaCorrectedOnReRun: Set<CorrectedOnReRun> = [
        CorrectedOnReRun(id: "google/veo-3.1-i2v-fast", key: "resolution", was: "720p", now: "720P"),
    ]

    /// Re-run also has to survive the trip *back* out: the reconstructed parameters are what the
    /// next generation encodes. Anything the stored payload carried that the table knows about must
    /// come back with the same value — except the three pinned exception sets above, each asserted
    /// by exact equality so this test cannot silently absorb a fourth.
    func testReRunRoundTripsEveryDescriptorKeyTheStoredPayloadCarried() throws {
        var encounteredUnmodeled: Set<String> = []
        var encounteredDocumented: Set<DocumentedException> = []
        var encounteredDrift: Set<KnownDrift> = []
        var encounteredCorrections: Set<CorrectedOnReRun> = []

        for (id, text) in Self.realPayloads {
            let json = try parsed(text)
            guard let descriptors = ParamCatalog.descriptors(forModelId: id) else { continue }

            var params = ModelParameters()
            ParamDecoder.decode(descriptors, from: json, into: &params)
            let context = ParamContext(modelId: id, isI2I: false, hasInputImages: false)
            let reencoded = ParamEncoder.encode(descriptors, params: params, context: context)

            for key in json.keys where key != "model" && key != "prompt" {
                let original = json[key]!
                guard let reencodedValue = reencoded[key] else {
                    if Self.unmodeledKeys.contains(key) {
                        encounteredUnmodeled.insert(key)
                    } else if Self.documentedLegacyExceptions.contains(
                        DocumentedException(id: id, key: key)) {
                        encounteredDocumented.insert(DocumentedException(id: id, key: key))
                    } else if Self.knownUnresolvedDrift.contains(KnownDrift(id: id, key: key)) {
                        encounteredDrift.insert(KnownDrift(id: id, key: key))
                    } else {
                        XCTFail("\(id) dropped \(key) on re-encode (shape had value \(original)) — "
                               + "not in any pinned exception set")
                    }
                    continue
                }
                if let correction = Self.schemaCorrectedOnReRun.first(where: { $0.id == id && $0.key == key }) {
                    XCTAssertEqual(original as? String, correction.was,
                                   "\(id): the stored \(key) is no longer the value the correction was approved for")
                    XCTAssertEqual(reencodedValue as? String, correction.now,
                                   "\(id): \(key) was approved to be corrected to \(correction.now)")
                    encounteredCorrections.insert(correction)
                    continue
                }
                XCTAssertEqual(NSDictionary(dictionary: [key: reencodedValue]),
                               NSDictionary(dictionary: [key: original]),
                               "\(id) re-runs \(key) with a different value")
            }
        }

        XCTAssertEqual(encounteredUnmodeled, Self.unmodeledKeys,
                       "the unmodeled-key set and what the corpus actually drops have diverged")
        XCTAssertEqual(encounteredDocumented, Self.documentedLegacyExceptions,
                       "the documented-legacy-exception set and what the corpus actually drops "
                       + "have diverged")
        XCTAssertEqual(encounteredCorrections, Self.schemaCorrectedOnReRun,
                       "the schema-correction pin and what the corpus actually corrects have diverged")
        XCTAssertEqual(encounteredDrift, Self.knownUnresolvedDrift,
                       "the known-drift pin and what the corpus actually drops have diverged — a "
                       + "drift was fixed without updating this set, or a new one appeared")
    }

    /// The corpus is only evidence if it stays the corpus. A shape silently dropped would shrink
    /// coverage without failing anything.
    func testTheCorpusKeepsAllThirtyTwoObservedShapes() {
        XCTAssertEqual(Self.realPayloads.count, 32)
        XCTAssertEqual(Set(Self.realPayloads.map(\.id)).count, 21)
        XCTAssertTrue(Self.realPayloads.contains { $0.payload.contains("\"height\"") },
                      "the one real image_size object-branch entry must stay in the corpus")
    }
}
