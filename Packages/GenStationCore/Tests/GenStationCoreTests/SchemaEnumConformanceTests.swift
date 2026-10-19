// Every value we send on an enum-constrained key must be a member of that key's published enum.
//
// **This is the check whose absence let 42 models rot behind a green suite.** Stage 3 pinned the
// captured schemas (`AIMLSchemaFixture`) and compared *key sets* against them
// (`UndocumentedKeyBaselineTests`) — but nothing compared *values*. So `resolution: "720p"` sailed
// past every gate for models whose enum is `["720P"]`, and the first report was a user watching
// generation fail with "Validation failed. Please check your request fields and values."
//
// Two assertions, over every registered id that has a captured schema:
//
// 1. **Emitted values** — driven by `GoldenPayloads`, the recording of what the app actually sends.
//    Not by re-encoding, which would only prove the encoder agrees with itself.
// 2. **Picker options** — what the UI offers the user. An option outside the enum is a trap the user
//    can walk into; an enum member missing from the picker is a capability silently withheld.
//
// The picker assertion's exception list is an **exact equality**, never a filter. A filter would
// absorb the next regression in silence, which is exactly how this class of bug survived.

import XCTest
@testable import GenStationCore

final class SchemaEnumConformanceTests: XCTestCase {

    /// One (id, key, value) that a published enum rejects.
    private struct Violation: CustomStringConvertible {
        let modelId: String
        let key: String
        let value: AIMLSchemaFixture.EnumValue
        let allowed: Set<AIMLSchemaFixture.EnumValue>

        var description: String {
            let permitted = allowed.map(\.description).sorted().joined(separator: ", ")
            return "\(modelId): \(key) = \(value) is not in [\(permitted)]"
        }
    }

    /// Registered id -> its published request-body enums, for the ids we can check at all.
    ///
    /// Ids resolve through `canonicalIDBySpelling` because the catalog registers aliases the schema
    /// capture is not keyed by; an id with no captured document is skipped, and the count of what was
    /// actually checked is asserted so silent shrinkage of coverage fails too.
    private func enumsByRegisteredID() throws -> [String: [String: Set<AIMLSchemaFixture.EnumValue>]] {
        let canonical = try AIMLSchemaFixture.canonicalIDBySpelling()
        let enums = try AIMLSchemaFixture.requestBodyEnums()
        var out: [String: [String: Set<AIMLSchemaFixture.EnumValue>]] = [:]
        for id in GoldenPayloads.byModelId.keys {
            guard let served = canonical[id.lowercased()], let published = enums[served] else { continue }
            out[id] = published
        }
        return out
    }

    // MARK: - Emitted values

    /// The one emitted value left that a published enum rejects, named rather than fixed.
    ///
    /// Four Kling ids publish `camera_control` as a **string enum of four preset names**; the other
    /// eighteen on the same table do not document the key at all. The app models it as a composite
    /// (`Control.custom(.klingCameraControl)`) that emits either a preset name or a
    /// `{movement_type, movement_value}` object, and the object is what those four reject.
    ///
    /// It is not fixed here because **the vendor's own documents contradict each other about it**:
    /// `kling-video/v2/master/text-to-video` and `klingai/v2-master-text-to-video` are two separately
    /// served ids for the same Kling model, and only the second one documents `camera_control`. Acting
    /// on that would mean disabling advanced camera control on four arbitrarily-chosen ids — removing a
    /// feature that may well work — on evidence that is self-inconsistent. Omitting a value is only
    /// safe when the schema saying so is trustworthy.
    ///
    /// `"{}"` is `fullyPopulatedProbe`'s canned `cameraControl`, a preset-name placeholder no picker
    /// offers; the object is the real user-reachable case. Recorded in the drift ledger, and pinned
    /// here as an exact equality so it stays visible and cannot grow.
    private static let knownSchemaConflicts: Set<String> = [
        #"kling-video/v1.6/pro/text-to-video|camera_control|"{}""#,
        #"kling-video/v1.6/pro/text-to-video|camera_control|[movement_type: zoom, movement_value: -4]"#,
        #"kling-video/v1/pro/text-to-video|camera_control|"{}""#,
        #"kling-video/v1/pro/text-to-video|camera_control|[movement_type: zoom, movement_value: -4]"#,
        #"kling-video/v1/standard/text-to-video|camera_control|"{}""#,
        #"kling-video/v1/standard/text-to-video|camera_control|[movement_type: zoom, movement_value: -4]"#,
        #"klingai/v2-master-text-to-video|camera_control|"{}""#,
        #"klingai/v2-master-text-to-video|camera_control|[movement_type: zoom, movement_value: -4]"#,
    ]

    /// The headline assertion. Every value in every probe of every recording, against its key's enum.
    func testEveryEmittedValueIsAMemberOfItsKeysPublishedEnum() throws {
        let published = try enumsByRegisteredID()
        var violations: [Violation] = []

        for (modelId, probes) in published.keys.sorted().map({ ($0, GoldenPayloads.byModelId[$0]!) }) {
            let enums = published[modelId]!
            for probe in probes.keys.sorted() {
                for (key, value) in probes[probe]!.sorted(by: { $0.key < $1.key }) {
                    guard let allowed = enums[key] else { continue }   // not enum-constrained
                    let emitted = AIMLSchemaFixture.EnumValue(json: value)
                    guard !allowed.contains(emitted) else { continue }
                    // The five probes differ only in which keys are present, so an offending value
                    // repeats across them. Report the id/key/value once.
                    if !violations.contains(where: {
                        $0.modelId == modelId && $0.key == key && $0.value == emitted
                    }) {
                        violations.append(Violation(modelId: modelId, key: key,
                                                    value: emitted, allowed: allowed))
                    }
                }
            }
        }

        let conflicts = Set(violations.map { "\($0.modelId)|\($0.key)|\($0.value)" })
            .intersection(Self.knownSchemaConflicts)
        XCTAssertEqual(conflicts, Self.knownSchemaConflicts,
                       "the known-conflict pin and what the sweep observes have diverged")
        violations.removeAll { Self.knownSchemaConflicts.contains("\($0.modelId)|\($0.key)|\($0.value)") }

        XCTAssertTrue(violations.isEmpty,
                      "\(violations.count) emitted value(s) the vendor's own schema rejects. The API "
                      + "answers these with \"Validation failed\" and generation never starts. Fix the "
                      + "case where the mismatch is only case; otherwise OMIT the key and let the "
                      + "documented default apply — never substitute a different value, which "
                      + "silently changes what the user gets or is charged. Record the wire change as "
                      + "a group-A row in the drift ledger.\n"
                      + violations.map { "  " + $0.description }.sorted().joined(separator: "\n"))

        // Coverage is part of the assertion: a check that quietly stops checking is worse than none.
        XCTAssertEqual(published.count, 206,
                       "the number of registered ids with a captured request-body schema changed")
    }

    // MARK: - Picker options

    /// Ids whose picker deliberately offers **fewer** options than the schema permits.
    ///
    /// Curation is legitimate — a model may publish an option the app has no way to render, or one the
    /// product has decided not to surface — but it must be *named*, so that the next option to vanish
    /// fails the build instead of joining an anonymous allowance.
    ///
    /// Keyed `"<model id>|<wire key>"`, valued with the exact set of published values the picker omits.
    /// Asserted as an equality in both directions, so an entry that stops applying also fails.
    private static let approvedPickerCurations: [String: Set<String>] = {
        var out: [String: Set<String>] = [:]

        // Kling v3 publishes `["customize", "intelligent", "intelligence"]` — two spellings of the
        // same thing. The picker offers `intelligent`, which is valid; offering `intelligence` beside
        // it would be a second control for the same behaviour.
        // September: multi-shot controls are not offered in the standard video workflow.


        // Happyhorse publishes every whole second from 3 to 15. The picker offers 5 and 10, which is
        // the shape every other video model in the app uses; twelve more menu entries would be noise.
        for id in ["alibaba/happyhorse-1.0-i2v", "alibaba/happyhorse-1.0-r2v", "alibaba/happyhorse-1.0-t2v",
                   "happyhorse-1.0-i2v", "happyhorse-1.0-r2v", "happyhorse-1.0-t2v"] {
            out["\(id)|duration"] = ["3", "4", "6", "7", "8", "9", "11", "12", "13", "14"]
        }

        // Topaz publishes five output formats; the picker offers `jpeg` and `png`. `jpg`/`tif`/`tiff`
        // are spelling variants of formats already offered.
        for id in ["topaz-labs/sharpen", "topaz-labs/sharpen-gen"] {
            out["\(id)|output_format"] = ["\"jpg\"", "\"tif\"", "\"tiff\""]
        }

        // Grok publishes six ultra-wide/ultra-tall ratios beyond the eight the picker offers.
        for id in ["x-ai/grok-imagine-image", "x-ai/grok-imagine-image-pro"] {
            out["\(id)|aspect_ratio"] = ["\"1:2\"", "\"2:1\"", "\"19.5:9\"", "\"9:19.5\"", "\"20:9\"", "\"9:20\""]
        }

        // The most permissive safety tolerance the model publishes, deliberately not offered.
        out["blackforestlabs/flux-2-pro-edit|safety_tolerance"] = ["\"6\""]

        // Veo 3.0 i2v publishes 4/6/8 but its view offered only 8, and the emit clamp substitutes 8
        // for anything else — so the two agree, and widening the picker would be a product decision
        // about a model whose other durations have never been exercised here.
        for id in ["google/veo-3.0-i2v", "google/veo-3.0-i2v-fast"] {
            out["\(id)|duration"] = ["4", "6"]
        }
        return out
    }()

    /// Ids that share a descriptor table with an id whose published enum for the same key is
    /// **different**, so no single option list can be right for all of them.
    ///
    /// These are the residue of the 2026-07-28 split work. Five tables were split where the disagreement
    /// changed what goes *on the wire*; the four entries below disagree only about what the picker may
    /// *offer*, which is a smaller harm — a user who picks the wrong one gets a validation failure
    /// instead of a video — and each needs a table split of its own to fix properly:
    ///
    ///   • `pixVerseV55T2V` — v5.5 publishes `duration: [5, 8, 10]`, v5 publishes `[5, 8]`. Splitting
    ///     this table is a larger job than the split alone: the v5 and v5.5 ids also disagree about
    ///     `aspect_ratio`, `generate_audio_switch`, `lip_sync_tts_speaker` and `thinking_type`, four of
    ///     which are already recorded on the undocumented-key baseline.
    ///   • `seedanceVideo` — `seedance-1-0-pro-fast` publishes `[5, 10]`, `seedance-1-5-pro` `[4…12]`.
    ///   • `seedance20` — `seedance-2-0` publishes a `4k` resolution, `seedance-2-0-fast` does not.
    ///
    /// Pinned as exact per-key sets in both directions, so none of them can quietly grow while they
    /// wait for their split.
    ///
    /// Task 6 (2026-08-11) added a sixth, found the moment `nanoBanana2`'s two spellings both got a
    /// captured schema for the first time (Task 5 registered the table with no schema on file at
    /// all): `nano-banana-2` publishes `aspect_ratio` as an 11-value enum with default `"auto"` —
    /// the table's picker matches it exactly, per the brief that introduced it — but
    /// `google/gemini-3.1-flash-image-preview`, a **separate top-level served id** sharing the same
    /// table, publishes only 5 of those 11 values and no default at all. Not a Task 6 regression:
    /// the table was already correct for one of its two spellings, and the other spelling's own
    /// schema simply did not exist to check against until now.
    private static let sharedTableEnumConflicts: [String: Set<String>] = [
        "pixverse/v5/image-to-video|duration":      ["10"],
        "pixverse/v5/text-to-video|duration":       ["10"],
        "pixverse/v5/transition|duration":          ["10"],
        "bytedance/seedance-1-0-pro-fast|duration": ["4", "8", "12"],
        "bytedance/seedance-2-0-fast|resolution":   ["\"1080p\"", "\"4k\""],
        "google/gemini-3.1-flash-image-preview|aspect_ratio":
            ["\"21:9\"", "\"2:3\"", "\"3:2\"", "\"4:5\"", "\"5:4\"", "\"auto\""],
    ]

    /// The withheld half of the same shared-table disagreements.
    private static let sharedTableWithheld: [String: Set<String>] = [
        "bytedance/seedance-1-5-pro|duration":     ["6", "7", "9", "11"],
        "bytedance/seedance-1-5-pro|aspect_ratio": ["\"adaptive\""],
    ]

    /// The picker is the other half of the contract: the emitted-value test only sees what the probes
    /// happened to store, while this sees every value the user can *reach*.
    func testEveryPickerOptionIsAMemberOfItsKeysPublishedEnum() throws {
        let published = try enumsByRegisteredID()
        var offered: [String: Set<String>] = [:]   // "<id>|<key>" -> options outside the enum
        var withheld: [String: Set<String>] = [:]  // "<id>|<key>" -> enum members the picker hides

        for modelId in published.keys.sorted() {
            guard let table = ParamCatalog.descriptors(forModelId: modelId) else { continue }
            let enums = published[modelId]!
            for descriptor in table where !descriptor.wireKey.isEmpty {
                guard let allowed = enums[descriptor.wireKey] else { continue }
                var options: [AIMLSchemaFixture.EnumValue]
                switch descriptor.control {
                case .picker(let values, _):
                    options = values.map { AIMLSchemaFixture.EnumValue(json: $0.jsonValue) }
                case .imageSize(let spec):
                    options = spec.presets.map { .text($0) }
                default:
                    continue
                }
                // The empty string on an `omitWhenEmpty` row is the picker's "none of these" entry and
                // the encoder provably never sends it, so it is not an option the user can trip over.
                if descriptor.omitWhenEmpty { options.removeAll { $0 == .text("") } }

                let slot = "\(modelId)|\(descriptor.wireKey)"
                let outside = options.filter { !allowed.contains($0) }
                if !outside.isEmpty { offered[slot] = Set(outside.map(\.description)) }
                let missing = allowed.subtracting(options)
                if !missing.isEmpty { withheld[slot] = Set(missing.map(\.description)) }
            }
        }

        // Shared-table disagreements are pinned exactly, in both directions, and then set aside — the
        // remaining assertion is still "no picker offers a rejected value", with nothing filtered.
        let conflicting = offered.filter { Self.sharedTableEnumConflicts[$0.key] != nil }
        XCTAssertEqual(conflicting, Self.sharedTableEnumConflicts,
                       "the shared-table conflict pin and what the sweep observes have diverged")
        for slot in Self.sharedTableEnumConflicts.keys { offered.removeValue(forKey: slot) }

        XCTAssertTrue(offered.isEmpty,
                      "\(offered.count) picker(s) offer a value the model's schema rejects — the user "
                      + "picks it and generation fails validation:\n"
                      + offered.sorted { $0.key < $1.key }
                          .map { "  \($0.key): \($0.value.sorted().joined(separator: ", "))" }
                          .joined(separator: "\n"))

        XCTAssertEqual(withheld, Self.approvedPickerCurations.merging(Self.sharedTableWithheld) { a, _ in a },
                       "a picker hides a value its model publishes. If that is deliberate curation, "
                       + "add it to `approvedPickerCurations` with a reason; if it is not, add the "
                       + "option. This is an exact equality on purpose — a filter here would swallow "
                       + "the next regression.")
    }
}
