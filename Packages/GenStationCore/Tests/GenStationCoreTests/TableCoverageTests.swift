// Every model the catalog knows has a descriptor table. All 209 spellings of them.
//
// This started as Task 8's video-only check and spent Stage 2 parsing `reg([...])` blocks out of
// `GenStation/Catalog/ModelRegistry.swift` with `String.contains` and odd-index
// `split(separator: "\"")` filtering — because the registry lived in the app target, which has no
// test harness. Stage 3 moved the model set into the package as `Catalog`, so the scan is gone and
// the ids are read where they are declared. `reg([` becoming `reg(\n[` would have driven the old
// parse silently to zero; there is nothing left to mis-parse.
//
// Scoped to `.aimlapi` and to *all* spellings — canonical ids and aliases alike — because
// `ParamCatalog` is deliberately keyed per alias (`ParamCatalog.swift:9-11`). That makes this the
// id-level statement of design § 3.6 invariant 5: every model, `.dead` and `.superseded` included,
// still resolves a descriptor table.
//
// This is the test that stops the migration lying about itself. `PayloadEquivalenceTests` iterates
// `ParamCatalog.migratedIds`, so a model left out of that set is not *tested* — it is skipped,
// silently and green. Coverage has to be asserted from the catalog's side, not the tables'.

import XCTest
@testable import GenStationCore

final class TableCoverageTests: XCTestCase {

    /// Ids that are deliberately **not** migrated, each with the reason. Empty, and meant to stay
    /// that way: an entry here is a model whose parameters the descriptor tables do not describe.
    /// The contract freezes this at `[:]`.
    private static let knownExclusions: [String: String] = [:]

    /// Every AI/ML id the catalog knows — canonical keys and aliases alike.
    static var aimlIds: Set<String> {
        Set(Catalog.all
            .filter { $0.provider == .aimlapi }
            .flatMap { [$0.id] + $0.aliases })
    }

    func testEveryCatalogModelHasADescriptorTable() {
        let ids = Self.aimlIds

        // The only guard the parse-honesty counts still buy. It exists so a catalog that resolves
        // to almost nothing cannot make the assertions below pass vacuously; it is deliberately far
        // below the real figure so that adding or deleting models never fails it for the wrong
        // reason. The exact id set is pinned by the set equality below, not by a number.
        XCTAssertGreaterThan(ids.count, 100, "Catalog.all resolved to \(ids.count) AI/ML ids")

        let missing = ids
            .filter { ParamCatalog.descriptors(forModelId: $0) == nil }
            .filter { Self.knownExclusions[$0] == nil }
        XCTAssertEqual(missing.sorted(), [], "catalog models without a descriptor table")

        // Stated as one equality rather than two counts. It replaces both the old
        // `allIds.count == 209` and `migratedIds.count == 209 - knownExclusions.count`: set equality
        // implies both, and additionally catches a table added for an id the catalog does not have —
        // which a pair of matching counts cannot.
        XCTAssertEqual(ParamCatalog.migratedIds,
                       ids.subtracting(Self.knownExclusions.keys),
                       "the descriptor tables and the catalog have drifted apart")
    }

    /// An exclusion must name a model that actually exists, or the equality above is wrong in the
    /// direction that hides an unmigrated model.
    ///
    /// The contract freezes `knownExclusions` at `[:]`, so looping over it directly can never
    /// execute its own body — a vacuously-green test that was never capable of catching either
    /// violation it names. The validation itself is factored into `invalidExclusions(_:knownIds:)`
    /// below so it can be run — and bite-proofed — against a hand-built dict, the same seam
    /// `CatalogSelectableTests` uses for `Catalog.selectable(task:from:)`. This method keeps
    /// asserting the real (currently vacuous) contract; `testTheExclusionValidatorCatchesBothKindsOfViolation`
    /// proves the logic underneath it actually works.
    func testEveryKnownExclusionIsARealCatalogIdWithNoTable() {
        XCTAssertEqual(Self.invalidExclusions(Self.knownExclusions, knownIds: Self.aimlIds), [])
    }

    /// The checks `testEveryKnownExclusionIsARealCatalogIdWithNoTable` runs, factored out so they
    /// are falsifiable independent of `knownExclusions` ever being populated.
    private static func invalidExclusions(_ exclusions: [String: String],
                                          knownIds: Set<String>) -> [String] {
        var offenders: [String] = []
        for (id, reason) in exclusions {
            if !knownIds.contains(id) {
                offenders.append("excluded id \(id) is not in the catalog")
            }
            if ParamCatalog.descriptors(forModelId: id) != nil {
                offenders.append("\(id) is excluded (\(reason)) but does have a table")
            }
        }
        return offenders.sorted()
    }

    /// Proof that `invalidExclusions` is not itself a tautology: a real catalog id that DOES have
    /// a table, and an id that is not in the catalog at all, must both be caught when handed to it
    /// as if they were exclusions.
    func testTheExclusionValidatorCatchesBothKindsOfViolation() throws {
        let ids = Self.aimlIds
        let realIdWithATable = try XCTUnwrap(
            ids.first { ParamCatalog.descriptors(forModelId: $0) != nil },
            "expected at least one real catalog id with a descriptor table")
        let fakeId = "not-a-real-catalog-id-\(UUID().uuidString)"

        let offenders = Self.invalidExclusions(
            [realIdWithATable: "pretend exclusion", fakeId: "pretend exclusion"],
            knownIds: ids)

        XCTAssertEqual(offenders.count, 2,
                       "expected both the wrongly-excluded real id and the fake id to be caught: "
                       + "\(offenders)")
    }

    /// The multi-vendor fan-outs: one view serving models from companies that never agreed on
    /// anything. A generated table that silently dropped the marker would launder a guess into
    /// apparent fact, and nothing else in the suite looks at comments.
    func testTheSharedFanOutTablesCarryTheirUnverifiedMarker() throws {
        let tables = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/GenStationCore/Params/Tables")
            .standardizedFileURL

        for (file, marker) in [("VideoAlibaba.swift", "copied from the shared Wan 2.6 view"),
                               ("VideoKling.swift", "copied from the shared Kling video view"),
                               ("ImageByteDance.swift", "copied from the shared Seedream v4 view")] {
            let source = try String(contentsOf: tables.appendingPathComponent(file), encoding: .utf8)
            XCTAssertTrue(source.contains("// unverified: " + marker),
                          "\(file) lost its unverified marker")
        }
    }
}
