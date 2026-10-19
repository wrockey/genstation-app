// Stage 2, Task 10b — the MCP contract.
//
// `MCPService.paramSchema(for:)` is two things at once:
//
//   1. the schema `list_models` advertises to agents, and
//   2. the **validation gate** — `generate_image` / `generate_video` reject any `params` key that is
//      absent from it (`MCPService.swift:655-661`).
//
// Task 10b migrates its synthesis from the legacy `ParameterParser`/`JSONBuilder` pair to the
// descriptor path. Publishing richer schema would be allowed; **narrowing the gate would not** —
// rejecting a key an agent is permitted to send today is a user-visible behaviour change that needs
// its own release note, not a refactor. These tests pin that the key set is byte-identical, for
// every registered id, so the gate cannot tighten by accident here or in a later table edit.
//
// The algorithm under test is reproduced from `MCPService.paramSchema` rather than called: the schema
// is synthesized in the app target, which has no XCTest target, and both of its inputs live here.
//
// Task 11 deleted the legacy builder/parser pair, so the pre-Task-10b schema is no longer computable.
// It was recorded first — `GoldenSchemas`, written by `GoldenFixtureRecorder` at `92e07cf` by running
// the legacy algorithm verbatim — and these tests now compare against that recording. **`GoldenSchemas`
// is therefore the definition of "as permissive as the gate used to be".** Changing it is changing the
// MCP contract, and needs a release note rather than a regenerate.

import XCTest
@testable import GenStationCore

final class MCPSchemaGateTests: XCTestCase {

    /// The recorded pre-Task-10b schema for a model: the legacy parser run on `[:]` to get defaults,
    /// the legacy builder run on those, unioned with the builder run on a fully populated probe so
    /// that optional keys with a nil default were advertised too.
    private func legacySchema(forModelId id: String) -> [String: Any]? {
        guard let table = GoldenTableNames.byModelId[id] else { return nil }
        return GoldenSchemas.byTable[table]
    }

    /// `MCPService.paramSchema` as Task 10b leaves it.
    ///
    /// The union over both `isI2I` values is the load-bearing part: the legacy builder took no
    /// `ParamContext` at all, so a row gated on the model's mode reached the schema — and therefore
    /// the gate — under *either* mode. Encoding under one context only would be a silent tightening
    /// the moment any table gates a wire-bearing row on the mode.
    private func descriptorSchema(forModelId id: String) -> [String: Any]? {
        guard let descriptors = ParamCatalog.descriptors(forModelId: id) else { return nil }

        func encode(_ params: ModelParameters) -> [String: Any] {
            var merged: [String: Any] = [:]
            for isI2I in [false, true] {
                let context = ParamContext(modelId: id, isI2I: isI2I, hasInputImages: isI2I)
                for (key, value) in ParamEncoder.encode(descriptors, params: params, context: context)
                where merged[key] == nil {
                    merged[key] = value
                }
            }
            return merged
        }

        var payload = encode(ParamDecoder.defaults(descriptors))
        for (key, value) in encode(ModelParameters.fullyPopulatedProbe()) where payload[key] == nil {
            payload[key] = value
        }
        for (key, value) in ParamEncoder.enumExamples(descriptors) where payload[key] == nil {
            payload[key] = value
        }
        payload.removeValue(forKey: "model")
        payload.removeValue(forKey: "prompt")
        return payload
    }

    /// The gate is `rawParams.keys.filter { schema[$0] == nil }`, so it is the **key set** — not the
    /// example values — that decides what an agent may send. Equal key sets ⇒ equal permissiveness.
    /// Ids whose gate deliberately changed, with the exact difference in both directions.
    ///
    /// The standing rule is **the gate may widen but never narrow** — narrowing rejects a key some
    /// agent may already be sending. `bytedance/seedream-5-0-lite` is an approved exception, decided
    /// 2026-07-28: it was registered against `seedreamV4Edit`, a table for a different family, so it
    /// advertised `num_images` and `enable_safety_checker` — **two keys its published schema does not
    /// document** — and emitted `image_size: "square_hd"` against an enum of `["2K", "4K"]`. Every
    /// generation failed validation. Narrowing takes nothing from an agent that was working, because
    /// no agent using those keys on this model was working; it was a 100% failure rate. `watermark`
    /// is genuinely new and is documented.
    ///
    /// Asserted as an **exact equality in both directions**, never a skip: a third key vanishing, or
    /// this one silently re-widening, still fails. Adding a row here needs the same justification —
    /// a schema-backed reason recorded in a commit — never convenience.
    private static let approvedGateChanges:
        [String: (removed: Set<String>, added: Set<String>, revalued: [String: String])] = [
        // `revalued` is old-value → new-value for a key that survives. `image_size` is the reason
        // this entry exists at all: `square_hd` is not in this model's enum and `2K` is.
        "bytedance/seedream-5-0-lite": (removed: ["num_images", "enable_safety_checker"],
                                        added: ["watermark"],
                                        revalued: ["square_hd": "2K"]),

        // 2026-07-28, the schema-conformance wave. **Every entry below removes and adds nothing** —
        // the gate's key set is byte-identical for all 201 ids, so no agent call that was accepted
        // before is rejected now. What moved is the *advertised example value*, and in each case it
        // moved from a value the model's own schema rejects to one it publishes. An agent copying the
        // old example got "Validation failed"; that is what these rows fix.
        //
        // Keeping the key set intact through this change is what `ParamEncoder.enumExamples` is for:
        // the schema is synthesised by encoding two probes, both probes carry the shared
        // `ModelParameters` defaults, and once the encoder stops emitting values a model rejects, a key
        // whose only source was an invalid probe value would have vanished from the gate entirely.
        // `pixverse/*` is that case exactly — no probe produces a valid `style`.
        "alibaba/wan2.2-i2v-plus":   (removed: [], added: [], revalued: ["720p": "1080P"]),
        "wan2.2-i2v-plus":           (removed: [], added: [], revalued: ["720p": "1080P"]),
        // 2.2 t2v was advertising `720P` — the right *case*, but this model publishes only
        // `["480P", "1080P"]`; it was on Wan **2.1**'s table, which is the one that publishes 720P.
        "alibaba/wan2.2-t2v-plus":   (removed: [], added: [], revalued: ["720P": "1080P"]),
        "wan2.2-t2v-plus":           (removed: [], added: [], revalued: ["720P": "1080P"]),

        // The five Veo tables whose `parseFallback` spelled the resolution `1080p` against schemas
        // that publish `1080P`. `ParamDecoder.defaults` feeds both this schema and every model switch
        // in the UI, so the wrong case here reached agents and users alike.
        "google/veo-3.0-i2v":                            (removed: [], added: [], revalued: ["1080p": "1080P"]),
        "google/veo-3.0-i2v-fast":                       (removed: [], added: [], revalued: ["1080p": "1080P"]),
        "google/veo-3.1-i2v":                            (removed: [], added: [], revalued: ["1080p": "1080P"]),
        "google/veo-3.1-i2v-fast":                       (removed: [], added: [], revalued: ["1080p": "1080P"]),
        "google/veo-3.1-first-last-image-to-video":      (removed: [], added: [], revalued: ["1080p": "1080P"]),
        "google/veo-3.1-first-last-image-to-video-fast": (removed: [], added: [], revalued: ["1080p": "1080P"]),
        "google/veo-3.1-lite-generate-001":              (removed: [], added: [], revalued: ["1080p": "1080P"]),
        "veo-3.1-lite-generate-001":                     (removed: [], added: [], revalued: ["1080p": "1080P"]),

        // An image model that was advertising a video resolution, because `resolution` is shared across
        // every model in `ModelParameters` and only the fully-populated probe ever supplied this key.
        "klingai/image-o1":          (removed: [], added: [], revalued: ["720p": "1K"]),

        // `realistic` is not a PixVerse style — it is Recraft-shaped, arriving through the shared
        // `stylePreset`. The replacement is the first style PixVerse publishes; it is an *example* in
        // the advertised schema, not a default the app sends.
        "pixverse/v5-5-image-to-video": (removed: [], added: [], revalued: ["realistic": "3d_animation"]),
        "pixverse/v5-5-text-to-video":  (removed: [], added: [], revalued: ["realistic": "3d_animation"]),
        "pixverse/v5.5/image-to-video": (removed: [], added: [], revalued: ["realistic": "3d_animation"]),
        "pixverse/v5.5/text-to-video":  (removed: [], added: [], revalued: ["realistic": "3d_animation"]),
        "google/veo-3.1-t2v": (removed: ["negative_prompt", "enhance_prompt", "seed"], added: [], revalued: [:]),
        "google/veo-3.1-t2v-fast": (removed: ["negative_prompt", "enhance_prompt", "seed"], added: [], revalued: [:]),
        // September reliability repair: current image-to-video schema has no aspect_ratio.
        "kling-video/v3/standard/image-to-video": (removed: ["aspect_ratio"], added: [], revalued: [:]),
        "kling-video/v3/pro/image-to-video": (removed: ["aspect_ratio"], added: [], revalued: [:]),
        "klingai/video-v3-pro-image-to-video": (removed: ["aspect_ratio"], added: [], revalued: [:]),
        "klingai/video-v3-standard-image-to-video": (removed: ["aspect_ratio"], added: [], revalued: [:]),
        "pixverse/v5/image-to-video":   (removed: [], added: [], revalued: ["realistic": "3d_animation"]),
        "pixverse/v5/text-to-video":    (removed: [], added: [], revalued: ["realistic": "3d_animation"]),
        "pixverse/v5/transition":       (removed: [], added: [], revalued: ["realistic": "3d_animation"]),
    ]

    func testTheAgentValidationGateAcceptsExactlyTheKeysItAcceptedBefore() {
        var checked = 0
        for id in GoldenTableNames.byModelId.keys.sorted() {
            guard let old = legacySchema(forModelId: id) else { XCTFail("no recorded schema for \(id)"); continue }
            guard let new = descriptorSchema(forModelId: id) else { XCTFail("no table for \(id)"); continue }

            if let approved = Self.approvedGateChanges[id] {
                XCTAssertEqual(Set(old.keys).subtracting(new.keys), approved.removed,
                               "\(id): the approved gate NARROWING is not exactly what was approved")
                XCTAssertEqual(Set(new.keys).subtracting(old.keys), approved.added,
                               "\(id): the approved gate WIDENING is not exactly what was approved")
            } else {
                XCTAssertEqual(Set(new.keys), Set(old.keys), "the MCP gate changed for \(id)")
            }
            checked += 1
        }
        // Derived from the **recording**, not from `Catalog`: this pins the gate against the legacy
        // algorithm for the ids that were recorded, and deleting a model from the catalog must not
        // quietly shrink that pin.
        XCTAssertGreaterThan(GoldenTableNames.byModelId.count, 100, "the recording is nearly empty")
        XCTAssertEqual(checked, GoldenTableNames.byModelId.count,
                       "every recorded id must be covered, or the pin is partial")
    }

    /// `list_models` advertises the same dictionary. Values are not part of the gate, but an agent
    /// reads them as the model's defaults and examples, so they are a contract too.
    func testListModelsAdvertisesTheSameSchemaValues() {
        var exercised: Set<String> = []
        for id in GoldenTableNames.byModelId.keys.sorted() {
            guard let old = legacySchema(forModelId: id), let new = descriptorSchema(forModelId: id) else { continue }
            if let approved = Self.approvedGateChanges[id] {
                // Every key the two have in COMMON must advertise the same value, EXCEPT the exact
                // old→new pairs named in `revalued`. So an approved key change cannot smuggle an
                // unrelated value change in with it, and the approved value change itself is pinned
                // to one specific replacement rather than "anything but the old one".
                exercised.insert(id)
                for (key, oldValue) in old where new[key] != nil {
                    let oldText = String(describing: oldValue)
                    let newText = String(describing: new[key]!)
                    if let expected = approved.revalued[oldText] {
                        XCTAssertEqual(newText, expected,
                                       "\(id): \(key) was approved to become \(expected), not \(newText)")
                    } else {
                        XCTAssertEqual(newText, oldText,
                                       "\(id): surviving key \(key) changed its advertised value")
                    }
                }
                continue
            }
            XCTAssertEqual(NSDictionary(dictionary: new), NSDictionary(dictionary: old),
                           "advertised schema values changed for \(id)")
        }
        // The exception list must not outlive the ids it was written for.
        XCTAssertEqual(exercised, Set(Self.approvedGateChanges.keys),
                       "an approvedGateChanges entry no longer matches any recorded id")
    }
}
