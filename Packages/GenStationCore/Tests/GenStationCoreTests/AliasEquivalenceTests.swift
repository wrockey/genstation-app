// The proof that two spellings of one model are interchangeable (design § 4.4).
//
// `GoldenPayloadTests:14-16` forbids regenerating the fixtures *from the encoder*, and that ban is
// correct: it is what stops the assertion becoming circular. Nothing here regenerates anything, and
// — unlike an earlier draft of this plan — nothing downstream of here subtracts a row from a golden
// fixture at collapse time. `ParamCatalog` keeps a key for every one of the 201 spellings
// (`ParamCatalog.swift:9-11`), so after Task 11's collapse all 201 still resolve to a payload, a
// table, a decode and a schema. The fixtures stay whole.
//
// What this file licenses is two things. (1) Task 11 makes 79 spellings resolve to another
// spelling's catalog row; that is only sound if the two were already indistinguishable on the wire.
// (2) Task 22 physically deletes a handful of ids the live `/models` probe no longer serves, and a
// deletion is only safe against this proof.
//
// It is also permanent rather than throwaway: it is the only detector in the repo for a drift that
// gives one spelling of a model a different payload from another. See the perturbation in the task
// that created this file — a self-consistent three-line drift passes every other test in the suite.
//
// Assertion strength is deliberately the same pair `GoldenPayloadTests:55-60` uses — `NSDictionary`
// equality (which implies key-set equality) *plus* a type-tag comparison. NSDictionary compares
// numbers by value, so `5` and `5.0` are equal to it even though the wire cares: video `duration` is
// always an Int and `guidance_scale` always a Double, and the golden literals carry their Swift types
// for exactly that reason. Anything weaker would let a key — or a key's numeric type — drift into one
// spelling and out of another, which is the exact defect class the golden harness exists to catch.
//
// What this does NOT prove: that group-mates share *capabilities*. The five gpt-image ids share one
// descriptor table and therefore pass every assertion here, while `ModelRegistry.swift:1876-1883`
// gives them two different `isI2I` / `maxInputImages` / `supportsMask` triples. `AliasGroups`
// already splits that group for exactly this reason, and Task 11's collapse script re-checks
// capability equality line-by-line before it drops a row. Nothing in this file would have caught it.

import XCTest
@testable import GenStationCore

final class AliasEquivalenceTests: XCTestCase {

    func testEveryIdInAGroupHasTheSameRecordedPayloads() {
        var comparisons = 0
        for group in AliasGroups.groups where group.count > 1 {
            let head = group[0]
            guard let expected = GoldenPayloads.byModelId[head] else {
                XCTFail("\(head) has no golden payload recording"); continue
            }
            for alias in group.dropFirst() {
                guard let actual = GoldenPayloads.byModelId[alias] else {
                    XCTFail("\(alias) has no golden payload recording"); continue
                }
                XCTAssertEqual(NSDictionary(dictionary: actual), NSDictionary(dictionary: expected),
                               "\(alias) records a different payload from its group-mate \(head)")
                // See file header: NSDictionary alone would let `5` and `5.0` compare equal. Per-probe,
                // matching GoldenPayloadTests:60's own granularity — `typeTags` on the outer
                // `ProbePayloads` would only ever see `Dictionary<String, Any>` and prove nothing.
                for (probeName, expectedProbe) in expected {
                    let actualProbe = actual[probeName] ?? [:]
                    XCTAssertEqual(GoldenPayloadTests.typeTags(actualProbe), GoldenPayloadTests.typeTags(expectedProbe),
                                   "\(alias) / \(probeName) records JSON value types that differ from its group-mate \(head)")
                }
                comparisons += 1
            }
        }
        XCTAssertEqual(comparisons, 83, "expected 83 alias spellings, compared \(comparisons)")
    }

    func testEveryIdInAGroupNamesTheSameDescriptorTable() {
        for group in AliasGroups.groups where group.count > 1 {
            let head = group[0]
            guard let expected = GoldenTableNames.byModelId[head] else {
                XCTFail("\(head) has no recorded table name"); continue
            }
            for alias in group.dropFirst() {
                XCTAssertEqual(GoldenTableNames.byModelId[alias], expected,
                               "\(alias) resolves to a different table from its group-mate \(head)")
            }
        }
    }

    /// `GoldenSchemas` and `GoldenDecodes` are keyed per *table*, so same-table implies same schema
    /// and same decode. Asserted anyway, from the id side: it is what makes "no fixture family is
    /// left un-checked" a fact rather than an argument, and it is free.
    func testEveryIdInAGroupHasTheSameRecordedMCPSchema() {
        for group in AliasGroups.groups where group.count > 1 {
            let head = group[0]
            guard let headTable = GoldenTableNames.byModelId[head],
                  let expected = GoldenSchemas.byTable[headTable] else {
                XCTFail("\(head) has no recorded MCP schema"); continue
            }
            for alias in group.dropFirst() {
                guard let aliasTable = GoldenTableNames.byModelId[alias],
                      let actual = GoldenSchemas.byTable[aliasTable] else {
                    XCTFail("\(alias) has no recorded MCP schema"); continue
                }
                XCTAssertEqual(NSDictionary(dictionary: actual), NSDictionary(dictionary: expected),
                               "\(alias) advertises a different MCP schema from \(head)")
            }
        }
    }

    /// The fixture is only evidence if it stays total over the recorded id set. A group silently
    /// dropped would shrink the proof without failing anything. The `migratedIds` line is the one
    /// that pins `ParamCatalog`'s per-alias keying: collapse those keys and this goes red on 79 ids.
    func testTheGroupsPartitionExactlyTheRecordedIdSet() {
        let flat = AliasGroups.groups.flatMap { $0 }
        XCTAssertEqual(flat.count, 214)
        XCTAssertEqual(Set(flat).count, 214, "an id appears in two groups")
        XCTAssertEqual(Set(flat), Set(GoldenPayloads.byModelId.keys).union(["alibaba/wan-3-0-video", "bytedance/seedance-2-5", "minimax/h3-max"]))
        XCTAssertEqual(Set(flat), Set(GoldenTableNames.byModelId.keys).union(["alibaba/wan-3-0-video", "bytedance/seedance-2-5", "minimax/h3-max"]))
        XCTAssertEqual(Set(flat), ParamCatalog.migratedIds)
        for id in flat { XCTAssertEqual(id, id.lowercased(), "\(id) is not lowercased") }
    }

    /// The catalog and the recorded grouping are two independent statements of the same fact.
    /// This is what keeps `AliasGroups` from becoming a stale second list. Grok's 2 rows arrive in
    /// Task 14, which is why the total and the AI/ML count are both stated.
    func testTheCatalogAgreesWithTheRecordedGrouping() {
        let aiml = Catalog.all.filter { $0.provider == .aimlapi }
        XCTAssertEqual(aiml.count, 131, "expected 131 canonical AI/ML rows")
        XCTAssertEqual(aiml.flatMap { [$0.id] + $0.aliases }.count, 214,
                       "the canonical ids and their aliases must total the 214 registered spellings")
        XCTAssertEqual(aiml.filter { !$0.aliases.isEmpty }.count, 53)
        XCTAssertEqual(aiml.filter(\.isVideo).count, 77)
        XCTAssertEqual(aiml.filter { !$0.isVideo }.count, 54)

        let fromCatalog = Set(aiml.map { Set([$0.id] + $0.aliases) })
        let fromFixture = Set(AliasGroups.groups.map { Set($0) })
        XCTAssertEqual(fromCatalog, fromFixture, "the catalog partitions the ids differently")

        // The canonical rule, restated as a property rather than as the 122 answers it produced.
        for model in aiml where !model.aliases.isEmpty {
            let group = [model.id] + model.aliases
            if group.contains(where: { $0.contains("/") }) {
                XCTAssertTrue(model.id.contains("/"),
                              "\(model.id) is canonical but a group-mate is vendor-qualified")
            }
            XCTAssertEqual(model.aliases, model.aliases.sorted(), "\(model.id): aliases unsorted")
        }

        // The six ids spec § 1 records as reachable only as registry keys. Each must still resolve,
        // and each must resolve to the vendor-qualified spelling the API serves as an entry id.
        let onlyRegistryKeys = [
            "gpt-image-1": "openai/gpt-image-1",
            "gpt-image-1.5": "openai/gpt-image-1.5",
            "gpt-image-2": "openai/gpt-image-2",
            "imagen-4.0-generate-001": "google/imagen-4.0-generate-001",
            "sora-2-t2v": "openai/sora-2-t2v",
            "veo2": "google/veo2",
        ]
        for (alias, expected) in onlyRegistryKeys {
            XCTAssertEqual(Catalog.canonicalID(for: alias), expected, "\(alias) resolves wrong")
        }
        XCTAssertEqual(Catalog.model(for: "gpt-image-2")?.maxInputImages, 16,
                       "the gpt-image split did not survive the collapse")
        XCTAssertEqual(Catalog.model(for: "gpt-image-1.5")?.maxInputImages, 4,
                       "gpt-image-1.5 picked up gpt-image-2's capabilities")
    }

    /// The tie-break rule `Catalog.swift`'s header comment documents, restated as an executable
    /// check — and, unlike everything above, checked against `AliasGroups`' own preserved order
    /// rather than against anything `Catalog` computes about itself.
    ///
    /// `CatalogEquivalenceTests` cannot pin this: the pre-collapse registry recording it checks
    /// against has no notion of "canonical" at all (every row's `id` is just its own `queriedID`
    /// echoed back — verified by scanning all 218 recorded rows), so any assertion phrased against
    /// it necessarily re-derives both sides from today's `Catalog`, which agrees with itself by
    /// construction no matter which group member is elected. `AliasGroups.groups` is the only
    /// checked-in artifact that still carries the pre-election fact this needs: element order is
    /// the `reg([...])` literal order, and Task 11 breaks ties on it (see the file's own header).
    /// That makes "first vendor-qualified member in that order, or the group's only member" an
    /// independent restatement of the rule, not a re-run of it.
    ///
    /// Bite-proofed against the mutation that motivated this test: swapping canonical and alias
    /// for `kling-video/v2.1/master/image-to-video` / `klingai/v2.1-master-image-to-video` in
    /// `VideoKlingRows.swift` (both spellings are vendor-qualified, so the weaker "some group-mate
    /// is vendor-qualified" check above does not move) makes this fail with "expected
    /// kling-video/v2.1/master/image-to-video, got klingai/v2.1-master-image-to-video" and passes
    /// green on every other test in the package.
    func testTheCanonicalSpellingIsTheFirstVendorQualifiedGroupMemberInRegOrder() {
        for group in AliasGroups.groups {
            let expected = group.first(where: { $0.contains("/") }) ?? group[0]
            XCTAssertEqual(Catalog.canonicalID(for: group[0]), expected,
                           "group \(group): canonical should be \(expected)")
        }
    }

    /// Lifecycle hides a model from pickers; it must never break history re-run. Aliases are the
    /// spellings history is full of, so all 214 have to resolve whatever the lifecycle says — and
    /// case-insensitively, because `history_v2.json` stores the caller's spelling verbatim.
    func testEveryRecordedSpellingStillResolves() {
        var checked = 0
        for group in AliasGroups.groups {
            for id in group {
                XCTAssertNotNil(Catalog.canonicalID(for: id), "\(id) no longer resolves")
                XCTAssertNotNil(Catalog.model(for: id), "\(id) has no row")
                XCTAssertEqual(Catalog.canonicalID(for: id.uppercased()),
                               Catalog.canonicalID(for: id), "\(id) is case-sensitive")
                XCTAssertNotNil(ParamCatalog.descriptors(forModelId: id),
                                "\(id) lost its descriptor table")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 214)
    }
}
