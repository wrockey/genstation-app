// Spec § 4.10 — the recorded baseline of payload keys the vendor's own schema does not document.
//
// **NOTHING HERE IS FIXED IN STAGE 3.** Every one of these 68 rows is a candidate wire change for
// existing users, so each correction belongs in the drift ledger
// as a group-A row awaiting approval — never as a table edit made because a test pointed at it. An
// undocumented key is also not proof of rejection: most APIs ignore unknown fields, so the likely
// effect of e.g. `generate_audio` on a model with no audio parameter is a feature that silently
// never happens.
//
// What the test buys is drift detection in both directions. New drift fails the build the day it is
// introduced; the existing 68 stay visible instead of decaying into folklore. They cluster in
// `wan26Video`, `wan26VideoI2V`, `klingVideo` and `seedreamV4` — exactly the four tables Stage 2
// marked `unverified: copied from the shared <X> view`. That marker was honest, and this is its
// first independent confirmation.
//
// The baseline file is written by `tools/undocumented_key_baseline.py`, which parses
// `GoldenPayloads.swift` as text. This test recomputes the same thing from `GoldenPayloads` **as
// Swift values**. Two independent implementations agreeing is the point — do not "simplify" this
// into reading the fixture back and comparing it with itself.

import XCTest
@testable import GenStationCore

final class UndocumentedKeyBaselineTests: XCTestCase {

    private static var baselineURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/aiml-undocumented-keys.json")
            .standardizedFileURL
    }

    private struct Baseline {
        let checkedIDCount: Int
        let offendingIDCount: Int
        let uncheckedIDs: [String]
        let undocumentedKeysByID: [String: [String]]
    }

    private static func baseline() throws -> Baseline {
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: baselineURL))
        guard let root = object as? [String: Any],
              let checked = root["checkedIDCount"] as? Int,
              let offending = root["offendingIDCount"] as? Int,
              let unchecked = root["uncheckedIDs"] as? [String],
              let keys = root["undocumentedKeysByID"] as? [String: [String]] else {
            throw NSError(domain: "UndocumentedKeyBaselineTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                                        "\(baselineURL.path) is not the expected shape"])
        }
        return Baseline(checkedIDCount: checked, offendingIDCount: offending,
                        uncheckedIDs: unchecked, undocumentedKeysByID: keys)
    }

    /// Registered id -> every key its recording emits, unioned over all five probes.
    private static func emittedKeys() -> [String: Set<String>] {
        GoldenPayloads.byModelId.mapValues { probes in
            probes.values.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
        }
    }

    /// Recompute, then compare with the checked-in record. Asserted as an exact dictionary, so a new
    /// undocumented key, a newly-documented key, and a model changing tables all fail here.
    func testTheUndocumentedKeyBaselineIsExactlyWhatWasRecorded() throws {
        let recorded = try Self.baseline()
        let canonical = try AIMLSchemaFixture.canonicalIDBySpelling()
        let documented = try AIMLSchemaFixture.documentedProperties()

        var computed: [String: [String]] = [:]
        var unchecked: [String] = []
        for (modelId, emitted) in Self.emittedKeys() {
            guard let served = canonical[modelId.lowercased()],
                  let properties = documented[served] else {
                unchecked.append(modelId)
                continue
            }
            let undocumented = emitted.subtracting(properties).sorted()
            if !undocumented.isEmpty { computed[modelId] = undocumented }
        }

        XCTAssertEqual(unchecked.sorted(), (recorded.uncheckedIDs + ["gpt-image-2.5-flare", "gpt-image-2.5-sunburst", "openai/gpt-image-2.5-flare", "openai/gpt-image-2.5-sunburst"]).sorted(),
                       "the set of registered ids with no published schema changed. It is the "
                       + "8-id delete list; regenerate with tools/undocumented_key_baseline.py "
                       + "--write and review the diff.")
        XCTAssertEqual(GoldenPayloads.byModelId.count - unchecked.count, recorded.checkedIDCount)
        XCTAssertEqual(computed.count, recorded.offendingIDCount)
        XCTAssertEqual(
            computed, recorded.undocumentedKeysByID,
            "spec § 4.10 baseline drift. Do NOT fix the table to make this pass — that moves the "
            + "wire. Regenerate with `python3 tools/undocumented_key_baseline.py --write`, review "
            + "the diff, and if a key genuinely should stop being sent, open a group-A row in the "
            + "drift ledger first.")
    }

    /// The shape of the finding, pinned separately so the headline numbers are readable without
    /// opening a 67-entry dictionary — and so the four `unverified:` tables stay named.
    func testTheBaselinesShapeIsPinned() throws {
        // 67 -> 68 on 2026-08-11. `alibaba/qwen-image` joined this list: its live schema no longer
        // documents `enable_safety_checker` or `guidance_scale`, both still emitted by `alibabaQwenImage`.
        // Neither key is new on the wire — the vendor's published schema is what moved — so this is
        // recorded as a re-pin, not a table edit. See the drift ledger before touching the table.
        //
        // `checkedIDCount` 201 -> 206 later the same day (Task 6): capturing schemas for all 5 of
        // Task 5 + Task 6's newly-registered ids moved 5 ids from unchecked to checked (nano-banana-2,
        // google/gemini-3.1-flash-image-preview, google/gemini-3-1-flash-lite-image,
        // bytedance/seedream-5-0-pro, blackforestlabs/flux-2-max) — none of which emit an undocumented
        // key, so `offendingIDCount` and the dictionary below are untouched.
        let recorded = try Self.baseline()
        XCTAssertEqual(recorded.checkedIDCount, 206)
        XCTAssertEqual(recorded.offendingIDCount, 64)
        XCTAssertEqual(recorded.undocumentedKeysByID.count, 64)

        var frequency: [String: Int] = [:]
        for keys in recorded.undocumentedKeysByID.values {
            for key in keys { frequency[key, default: 0] += 1 }
        }
        XCTAssertEqual(frequency["aspect_ratio"], 21)
        XCTAssertEqual(frequency["camera_control"], 18)
        XCTAssertEqual(frequency["enhance_prompt"], 14)
        XCTAssertEqual(frequency["generate_audio"], 13)
        XCTAssertEqual(frequency["shot_type"], 12)
        XCTAssertEqual(frequency["negative_prompt"], 10)
        XCTAssertEqual(frequency.values.reduce(0, +), 113,
                       "id/key pairs: \(frequency.sorted { $0.key < $1.key })")
        XCTAssertEqual(frequency.count, 16, "distinct keys: \(frequency.keys.sorted())")
    }
}
