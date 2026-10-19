// Stage 2, Task 6b — the descriptor decoder.
//
// Descriptors drive three outputs, and the encoder is only two of them. `ParameterParser` has three
// live consumers that Task 11 deletes out from under: MCP defaults seeding (`MCPService.swift:585`),
// MCP agent overrides (`:663`), and **history re-run** (`HistoryView.swift:2163`). History stores only
// the submitted payload string and no parameters, so the decoder is the only path that can replay a
// past generation.
//
// The plan's Task 6b tests iterate `ParamCatalog.migratedIds` and `ProbeSet.all`, neither of which
// exists until Task 7 — and iterating an empty catalog proves nothing. These tests instead pin the
// decoder against two **real** legacy families resolved through `LegacyPayload`, so they bite today.
// Task 7 adds the catalog-wide sweep on top.

import XCTest
@testable import GenStationCore

final class ParamDecoderTests: XCTestCase {

    // MARK: - Tables transcribed from the legacy pair they must reproduce

    /// `wan25I2VJSONBuilder` / `wan25I2VParameterParser` (`Legacy/Alibaba.swift:118-135`).
    ///
    /// Read out of `ParamCatalog` rather than transcribed again: Task 7 promoted this exact table into
    /// the catalog, and a second copy here would be free to drift from the one the app ships.
    private let wan25I2V: [ParamDescriptor] =
        ParamCatalog.descriptors(forModelId: "alibaba/wan2.5-i2v-preview") ?? []

    /// `wan26VideoJSONBuilder` / `wan26VideoParameterParser` (`Legacy/Alibaba.swift:138-160`).
    ///
    /// Note `resolution`: the UI default is "720p" (the struct default) but the parser substitutes
    /// "1080p" when the key is absent. That divergence is exactly why `defaultValue` cannot double as
    /// the decode fallback.
    private let wan26Video: [ParamDescriptor] = [
        ParamDescriptor(wireKey: "aspect_ratio", field: .aspectRatio, label: "Aspect Ratio", help: nil,
                        control: .picker(options: [.string("16:9"), .string("9:16")], style: .menu),
                        defaultValue: .string("16:9"), visibleWhen: nil, alwaysEmit: false,
                        parseFallback: .value(.string("16:9"))),
        ParamDescriptor(wireKey: "resolution", field: .resolution, label: "Resolution", help: nil,
                        control: .picker(options: [.string("720p"), .string("1080p")], style: .segmented),
                        defaultValue: .string("720p"), visibleWhen: nil, alwaysEmit: false,
                        parseFallback: .value(.string("1080p"))),
        ParamDescriptor(wireKey: "duration", field: .duration, label: "Duration", help: nil,
                        control: .picker(options: [.int(5), .int(10)], style: .segmented),
                        defaultValue: .int(5), visibleWhen: nil, alwaysEmit: false,
                        parseFallback: .value(.int(10))),
        ParamDescriptor(wireKey: "negative_prompt", field: .negativePrompt, label: "Negative Prompt",
                        help: nil, control: .text(placeholder: "What to avoid"), defaultValue: nil,
                        visibleWhen: nil, alwaysEmit: false, omitWhenEmpty: true, parseFallback: .setNil),
        ParamDescriptor(wireKey: "shot_type", field: .shotType, label: "Shot Type", help: nil,
                        control: .picker(options: [.string("single"), .string("multi")], style: .segmented),
                        defaultValue: .string("single"), visibleWhen: nil, alwaysEmit: false,
                        parseFallback: .value(.string("single"))),
        ParamDescriptor(wireKey: "generate_audio", field: .generateAudio, label: "Generate Audio",
                        help: nil, control: .toggle, defaultValue: .bool(true), visibleWhen: nil,
                        alwaysEmit: false, parseFallback: .value(.bool(true))),
        ParamDescriptor(wireKey: "enhance_prompt", field: .enhancePrompt, label: "Enhance Prompt",
                        help: nil, control: .toggle, defaultValue: .bool(true), visibleWhen: nil,
                        alwaysEmit: false, parseFallback: .value(.bool(true))),
        ParamDescriptor(wireKey: "seed", field: .seed, label: "Seed", help: nil,
                        control: .seed(range: 0...2147483647), defaultValue: nil, visibleWhen: nil,
                        alwaysEmit: false, parseFallback: .setNil)
    ]

    private var tables: [(id: String, table: [ParamDescriptor])] {
        [("alibaba/wan2.5-i2v-preview", wan25I2V), ("alibaba/wan-2-6-t2v", wan26Video)]
    }

    /// Task 7 formalised this as `ProbeSet.all` — four probes, because probes 1-3 all take the preset
    /// branch of the `image_size` composite and would leave its object branch unexercised.
    private var probes: [(name: String, params: ModelParameters)] { ProbeSet.all }

    // MARK: - Reading a present key

    func testAPresentKeyIsDecodedIntoItsField() {
        var p = ModelParameters()
        ParamDecoder.decode(wan25I2V, from: ["resolution": "1080p", "duration": 10, "seed": 7], into: &p)
        XCTAssertEqual(p.resolution, "1080p")
        XCTAssertEqual(p.duration, 10)
        XCTAssertEqual(p.seed, 7)
    }

    /// `wireKey` and `field` are independent on the way in too: Gemini 3 Pro stores the `resolution`
    /// key into `geminiResolution`.
    func testAPresentKeyIsWrittenToTheFieldTheRowNamesNotTheKeysNamesake() {
        let d = ParamDescriptor(wireKey: "resolution", field: .geminiResolution, label: "Resolution",
                                help: nil, control: .picker(options: [.string("2K")], style: .menu),
                                defaultValue: .string("1K"), visibleWhen: nil, alwaysEmit: false)
        var p = ModelParameters()
        ParamDecoder.decode([d], from: ["resolution": "2K"], into: &p)
        XCTAssertEqual(p.geminiResolution, "2K")
        XCTAssertEqual(p.resolution, "720p", "the same-named field must be untouched")
    }

    /// JSONSerialization hands back `NSNumber`, so an integral literal must still reach a Double field.
    func testJSONNumbersAreCoercedToTheFieldsKind() throws {
        let d = ParamDescriptor(wireKey: "guidance_scale", field: .guidanceScale, label: "Guidance",
                                help: nil, control: .slider(range: 1...20, step: 0.5),
                                defaultValue: nil, visibleWhen: nil, alwaysEmit: false)
        let json = try JSONSerialization.jsonObject(with: Data(#"{"guidance_scale": 3}"#.utf8)) as! [String: Any]
        var p = ModelParameters()
        ParamDecoder.decode([d], from: json, into: &p)
        XCTAssertEqual(p.guidanceScale, 3.0)
    }

    // MARK: - Reading an absent key: the three legacy fallback shapes

    func testAnAbsentKeyTakesTheParsersDefault() {
        var p = ModelParameters()
        ParamDecoder.decode(wan26Video, from: [:], into: &p)
        XCTAssertEqual(p.resolution, "1080p", "the parser default, not the UI default of 720p")
        XCTAssertEqual(p.duration, 10)
    }

    func testAnAbsentKeySetsNilWhereTheLegacyParserHasNoDefault() {
        var p = ModelParameters(); p.negativePrompt = "leftover"; p.seed = 99
        ParamDecoder.decode(wan25I2V, from: [:], into: &p)
        XCTAssertNil(p.negativePrompt)
        XCTAssertNil(p.seed)
    }

    func testAnAbsentKeyLeavesTheFieldUnchangedByDefault() {
        let d = ParamDescriptor(wireKey: "shot_type", field: .shotType, label: "Shot Type", help: nil,
                                control: .toggle, defaultValue: nil, visibleWhen: nil, alwaysEmit: false)
        var p = ModelParameters(); p.shotType = "multi"
        ParamDecoder.decode([d], from: [:], into: &p)
        XCTAssertEqual(p.shotType, "multi")
    }

    /// `json["duration"] as? Int ?? 10` takes the default on a *type* mismatch too, not only when the
    /// key is missing.
    func testAWrongTypedValueTakesTheFallbackJustLikeTheLegacyCast() {
        var p = ModelParameters()
        ParamDecoder.decode(wan26Video, from: ["duration": "8s"], into: &p)
        XCTAssertEqual(p.duration, 10)
    }

    // MARK: - The image_size composite

    func testImageSizeDecodesAPresetStringOrADimensionObject() {
        let spec = ImageSizeSpec(
            presets: ["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"],
            presetFallback: "landscape_4_3", dimensions: [512, 768, 1024, 1280, 1440],
            widthFallback: 1024, heightFallback: 1024)
        let d = ParamDescriptor(wireKey: "image_size", field: nil, label: "Image Size", help: nil,
                                control: .imageSize(spec), defaultValue: nil, visibleWhen: nil, alwaysEmit: true)
        var preset = ModelParameters()
        ParamDecoder.decode([d], from: ["image_size": "square_hd"], into: &preset)
        XCTAssertEqual(preset.imageSizeMode, "preset")
        XCTAssertEqual(preset.imageSizePreset, "square_hd")

        var custom = ModelParameters()
        ParamDecoder.decode([d], from: ["image_size": ["width": 1280, "height": 720]], into: &custom)
        XCTAssertEqual(custom.imageSizeMode, "custom")
        XCTAssertEqual(custom.customWidth, 1280)
        XCTAssertEqual(custom.customHeight, 720)

        var absent = ModelParameters()
        ParamDecoder.decode([d], from: [:], into: &absent)
        XCTAssertEqual(absent.imageSizeMode, "preset")
        XCTAssertEqual(absent.imageSizePreset, "landscape_4_3")

        // The absent-key fallback is the *model's* preset, not a constant: seven models spell it
        // `square_hd` and one spells it `2K`.
        let seedream45 = ImageSizeSpec(presets: ["2K", "4K"], presetFallback: "2K",
                                       dimensions: [1440, 2048, 4096],
                                       widthFallback: 2048, heightFallback: 2048, minimumDimension: 1440)
        var other = ModelParameters()
        ParamDecoder.decode([ParamDescriptor(wireKey: "image_size", field: nil, label: "", help: nil,
                                             control: .imageSize(seedream45), defaultValue: nil,
                                             visibleWhen: nil, alwaysEmit: true)], from: [:], into: &other)
        XCTAssertEqual(other.imageSizePreset, "2K")
    }

    // MARK: - Equivalence with the legacy parsers, catalog-wide
    //
    // Task 6b's sweeps ran over `tables` — two hand-picked families — which is enough to prove the
    // decoder works and nothing like enough to prove that 121 generated tables decode the way the
    // parsers they replace did. Task 10b widened them to all 209 ids and immediately found **22
    // divergent ids** (`wan26VideoI2V`'s 14 and `wanImageEdit`'s 8, both wire-key-less rows the
    // decoder was skipping outright — drift ledger § B.9).
    //
    // Task 11 deleted the parsers, so what these compare against is `GoldenDecodes` — a recording of
    // those same parsers, taken by `GoldenFixtureRecorder` at `92e07cf` before the deletion. The
    // sweeps still run over every registered id; only the right-hand side changed from a live call
    // to a checked-in literal.

    /// Ids deliberately re-registered onto a different table *after* `GoldenDecodes` was recorded.
    ///
    /// `GoldenTableNames` is a generated historical record of what each id resolved to at `92e07cf`
    /// and must not be edited to paper over a change — the MCP gate pin reads it to know what the
    /// app advertised *before*, and repointing it there would erase the very change that pin exists
    /// to detect. So the redirection lives here instead, named and dated.
    ///
    /// `bytedance/seedream-5-0-lite` moved `seedreamV4Edit` → `seedream45` on 2026-07-28: it
    /// publishes `image_size: ["2K","4K"]`, not the v4-edit preset set, and every generation was
    /// failing validation. Comparing it against `seedreamV4Edit`'s recording would assert that a
    /// known-broken mapping is still in place.
    ///
    /// This redirects to another table's **independently recorded** legacy decode — it never
    /// weakens an assertion, and the sweep still covers every id exactly once.
    /// The 2026-07-28 schema-conformance work split five tables. Each split table's rows are the parent
    /// table's rows with **only** `control` and `allowedValues` replaced — neither of which
    /// `ParamDecoder` reads — so every one of them decodes byte-identically to the table it came from,
    /// and redirecting to the parent's recording is an equality, not a relaxation. Two also move a
    /// display-only `defaultValue`, which the decoder does not read either.
    private static let approvedReregistrations: [String: String] = [
        "bytedance/seedream-5-0-lite": "seedream45",

        "alibaba/wan2.2-t2v-plus":            "alibabaWan21T2VPlus",
        "wan2.2-t2v-plus":                    "alibabaWan21T2VPlus",
        "alibaba/wan2.2-i2v-plus":            "wan25I2V",
        "wan2.2-i2v-plus":                    "wan25I2V",
        "google/veo-3.1-reference-to-video":  "googleVeo31I2VFastVeo31",
        "google/veo-3.1-t2v":                 "googleVeo3T2V",
        "google/veo-3.1-t2v-fast":            "googleVeo3T2V",
        "google/veo-3.1-lite-generate-001":   "veoFirstLastFrame",
        "veo-3.1-lite-generate-001":          "veoFirstLastFrame",
    ]

    private func recordedTableName(for id: String) -> String? {
        Self.approvedReregistrations[id] ?? GoldenTableNames.byModelId[id]
    }

    /// Every field on which a table's decode deliberately differs from `GoldenDecodes`, as
    /// `"<field>: <was> -> <now>"`, keyed by recorded table name.
    ///
    /// `GoldenDecodes` records *the legacy parser applied to the legacy payload*. The 2026-07-28
    /// schema-conformance work changed the payload — that is the whole point of it — so decoding the
    /// new payload necessarily lands somewhere else, and asserting the old landing point would be
    /// asserting that the broken payload is still being produced. Two distinct causes, both visible in
    /// the strings below:
    ///
    ///   • a key whose value was **case-corrected** decodes to the new spelling (`720p` → `720P`);
    ///   • a key that is now **omitted** decodes to the row's `parseFallback` instead of to the value
    ///     the payload used to carry (`duration: 5` → `8`, the model's documented default).
    ///
    /// A third cause shows up on the `allNil` probe only, where the payload is empty and the decode is
    /// nothing but fallbacks: five Veo tables had `parseFallback: .value("1080p")` against schemas that
    /// publish `1080P`, so the fallback itself was corrected.
    ///
    /// Pinned as an exact equality per table — every probe's differences must be a subset of the
    /// table's entry, and their union must equal it — so a sixth field moving, or one of these quietly
    /// reverting, still fails. This is deliberately field-level rather than a per-table skip: the
    /// fields that did *not* move are still being checked against the recording.
    private static let approvedDecodeChanges: [String: Set<String>] = [
        // — case corrections only —
        "alibabaWan21T2VPlus":      ["resolution: 720p -> 720P"],
        "alibabaWan21T2VTurbo":     ["resolution: 720p -> 720P"],
        "googleVeo31I2VFastVeo30":  ["resolution: 720p -> 720P", "resolution: 1080p -> 1080P"],
        "googleVeo31I2VFastVeo31":  ["resolution: 720p -> 720P", "resolution: 1080p -> 1080P"],

        // — case correction plus an omitted key falling back —
        "googleVeo3T2V":            ["resolution: 720p -> 720P", "duration: 5 -> 8"],
        "veoFirstLastFrame":        ["resolution: 720p -> 720P", "duration: 5 -> 8",
                                     "resolution: 1080p -> 1080P"],

        // — omissions only —
        "grokImagine":              ["resolution: 720p -> 2k"],
        "klingImageO1":             ["resolution: 720p -> 1K"],
        "kandinskyVideo":           ["aspectRatio: 16:9 -> 3:2"],
        "ltxv2":                    ["resolution: 720p -> 1080p", "duration: 5 -> 6", "frameRate: 30 -> 25"],
        "minimaxHailuo02":          ["resolution: 720p -> 768P", "duration: 5 -> 6"],
        "hailuo23":                 ["resolution: 720p -> 768P", "duration: 5 -> 6"],
        "sora2":                    ["duration: 5 -> 8"],
        "sora2ProI2V":              ["duration: 5 -> 8"],
        "pixVerseV55T2V":           ["stylePreset: realistic -> nil"],
        "recraftV3":                ["stylePreset: realistic -> realistic_image"],
        "topazSharpen":             ["topazMode: sharpen -> Standard"],
        "topazSharpenGen":          ["topazMode: sharpen -> Super Focus"],
    ]

    /// `"<field>: <was> -> <now>"` for every field on which two `ModelParameters` differ, driven by
    /// `ParamField.allCases` so a field added to the struct is covered the day it gets a case.
    private func differences(from old: ModelParameters, to new: ModelParameters) -> Set<String> {
        var out: Set<String> = []
        for field in ParamField.allCases where old[field] != new[field] {
            func text(_ value: ParamValue?) -> String {
                switch value {
                case .none:              return "nil"
                case .string(let v):     return v
                case .int(let v):        return String(v)
                case .double(let v):     return String(v)
                case .bool(let v):       return String(v)
                }
            }
            out.insert("\(field): \(text(old[field])) -> \(text(new[field]))")
        }
        return out
    }

    /// `ParamDecoder.defaults` seeds the MCP schema and, through `ParamDefaults.merge` at
    /// `ConfigurationSection.handleSelectedModelChange()`, every model switch in the UI. It must
    /// equal what the legacy parser produced from `[:]`, for every recorded id.
    func testDefaultsMatchTheRecordedLegacyParserForEveryRegisteredModel() {
        var checked = 0
        for id in GoldenTableNames.byModelId.keys.sorted() {
            guard let table = ParamCatalog.descriptors(forModelId: id) else {
                XCTFail("\(id) has no descriptor table"); continue
            }
            guard let name = recordedTableName(for: id), let recorded = GoldenDecodes.defaultsByTable[name] else {
                XCTFail("\(id) has no recorded legacy defaults"); continue
            }
            // The same pin as the decode sweep, restricted to the empty payload: `defaults` is
            // literally `decode(table, from: [:])`, so the only differences it can show are corrected
            // `parseFallback` values — the five Veo tables whose `1080p` fallback did not match the
            // `1080P` their schemas publish.
            let moved = differences(from: recorded, to: ParamDecoder.defaults(table))
            XCTAssertTrue(moved.isSubset(of: Self.approvedDecodeChanges[name] ?? []),
                          "defaults diverge for \(id) beyond what was approved: "
                          + "\(moved.subtracting(Self.approvedDecodeChanges[name] ?? []).sorted())")
            checked += 1
        }
        XCTAssertGreaterThan(GoldenTableNames.byModelId.count, 100, "the recording is nearly empty")
        XCTAssertEqual(checked, GoldenTableNames.byModelId.count,
                       "every recorded id must be covered, or the sweep is partial")
    }

    /// The same, over every probe: decoding a payload the model itself produced must land on the
    /// same 41 fields the legacy parser landed on. This is the invariant history re-run rests on.
    func testDecodeMatchesTheRecordedLegacyParserForEveryRegisteredModel() {
        var checked = 0
        var observed: [String: Set<String>] = [:]
        for id in GoldenTableNames.byModelId.keys.sorted() {
            guard let table = ParamCatalog.descriptors(forModelId: id),
                  let name = recordedTableName(for: id),
                  let recorded = GoldenDecodes.decodedByTable[name],
                  let payloads = GoldenPayloads.byModelId[id] else {
                XCTFail("\(id) is missing a table or a recording"); continue
            }
            for (probeName, _) in probes {
                guard let json = payloads[probeName], let expected = recorded[probeName] else {
                    XCTFail("\(id) has no recording for probe \(probeName)"); continue
                }
                var viaDescriptors = ModelParameters()
                ParamDecoder.decode(table, from: json, into: &viaDescriptors)
                let moved = differences(from: expected, to: viaDescriptors)
                XCTAssertTrue(moved.isSubset(of: Self.approvedDecodeChanges[name] ?? []),
                              "decode diverges for \(id) / \(probeName) beyond what was approved: "
                              + "\(moved.subtracting(Self.approvedDecodeChanges[name] ?? []).sorted())")
                if !moved.isEmpty { observed[name, default: []].formUnion(moved) }
                checked += 1
            }
        }
        // The union over probes must equal the pin exactly, so an approved difference that stops
        // happening fails just as loudly as a new one appearing.
        XCTAssertEqual(observed, Self.approvedDecodeChanges,
                       "the approved-decode-change pin and what the sweep observes have diverged")
        XCTAssertEqual(checked, GoldenTableNames.byModelId.count * probes.count,
                       "every recorded id × probe must be covered")
    }

    /// Decode then encode must reproduce the payload it started from.
    ///
    /// Over the fully populated probe only, deliberately: when a payload omits a key the legacy parser
    /// substituted its own default, so re-encoding necessarily puts the key back. That asymmetry is a
    /// property of the legacy parser, not a decoder defect — pinning the fully populated case is what
    /// proves no *data* is lost in the round trip. Widened from two families to all 209 ids here,
    /// since the recorded payloads make it free.
    ///
    /// Since 2026-07-28 the fully populated payload is no longer "every key", because the schema guard
    /// omits keys whose value the model rejects. Decoding such a payload takes the row's
    /// `parseFallback` — a value the model *does* accept — and re-encoding then puts the key back. So
    /// the invariant is stated the way it was always meant: **every key the payload carried comes back
    /// with the same value**, and any key that appears only in the round trip is named below. That is
    /// still "no data is lost"; it is the omitted-key asymmetry above, now reachable from this probe.
    private static let approvedReencodeAdditions: [String: [String: String]] = [
        "googleVeo3T2V":           ["duration": "8"],
        "veoFirstLastFrame":       ["duration": "8"],
        "kandinskyVideo":          ["aspect_ratio": "3:2"],
        "ltxv2":                   ["duration": "6", "fps": "25", "resolution": "1080p"],
        "minimaxHailuo02":         ["duration": "6", "resolution": "768P"],
        "hailuo23":                ["duration": "6", "resolution": "768P"],
        "sora2":                   ["duration": "8"],
        "sora2ProI2V":             ["duration": "8"],
        "grokImagine":             ["resolution": "2k"],
        "recraftV3":               ["style": "realistic_image"],
    ]

    func testDecodeThenEncodeReproducesTheOriginalPayloadForEveryRegisteredModel() {
        var observed: [String: [String: String]] = [:]
        for id in GoldenPayloads.byModelId.keys.sorted() {
            guard let table = ParamCatalog.descriptors(forModelId: id),
                  let original = GoldenPayloads.byModelId[id]?["fullyPopulated"] else {
                XCTFail("\(id) is missing a table or a recording"); continue
            }
            var round = ModelParameters()
            ParamDecoder.decode(table, from: original, into: &round)
            let ctx = ParamContext(modelId: id, isI2I: false, hasInputImages: false)
            let reencoded = ParamEncoder.encode(table, params: round, context: ctx)

            // Nothing the payload carried may change or disappear. This is the half that means
            // "no data is lost", and it is unchanged.
            for (key, value) in original {
                if ["google/veo-3.1-t2v", "google/veo-3.1-t2v-fast"].contains(id),
                   ["negative_prompt", "enhance_prompt", "seed"].contains(key) {
                    XCTAssertNil(reencoded[key], "Retired fallback-only controls remain readable but must not be resubmitted")
                    continue
                }
                XCTAssertEqual(NSDictionary(dictionary: [key: reencoded[key] ?? "<missing>"]),
                               NSDictionary(dictionary: [key: value]),
                               "round trip lost or changed \(key) for \(id)")
            }
            let added = Set(reencoded.keys).subtracting(original.keys)
            guard !added.isEmpty, let name = recordedTableName(for: id) else { continue }
            observed[name] = Dictionary(uniqueKeysWithValues:
                added.map { ($0, String(describing: reencoded[$0]!)) })
        }
        XCTAssertEqual(observed, Self.approvedReencodeAdditions,
                       "a key reappears on re-encode that was not approved to, or an approved one "
                       + "stopped reappearing")
    }
}
