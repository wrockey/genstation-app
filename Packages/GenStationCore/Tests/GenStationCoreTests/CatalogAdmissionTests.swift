// The catalog properties `MCPService` depends on after Stage 3 Task 21, plus a source pin on the
// two call sites that carry them.
//
// `MCPService` is `#if os(macOS)` for its whole 1,453 lines and the app target has no XCTest
// target, so the wiring cannot be *executed* here. The last method reads the shipped file as text —
// the same idiom `RegistryEndpointTests` uses for the model-switch handler — which is weaker than
// executing it but strictly stronger than nothing, and it is what stops a later edit quietly
// reintroducing a `.dead` rejection on the generate path.

import XCTest
@testable import GenStationCore

final class CatalogAdmissionTests: XCTestCase {

    private static var mcpServiceSource: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("../../../../GenStation/Agents/MCPService.swift")
                .standardizedFileURL
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// `generate_image` / `generate_video` route the agent's `model` through the alias index. Every
    /// spelling an agent could have learned from an older `list_models` must still resolve, or the
    /// collapse would have broken agents while fixing the GUI.
    func testEveryRegisteredSpellingResolvesForAgentAdmission() {
        var resolved = 0
        for group in AliasGroups.groups {
            for id in group {
                XCTAssertNotNil(Catalog.canonicalID(for: id), "\(id) is not admissible")
                XCTAssertNotNil(Catalog.canonicalID(for: id.uppercased()), "\(id) is case-sensitive")
                resolved += 1
            }
        }
        // Vacuity guard only. The exact partition is pinned by
        // `AliasEquivalenceTests.testTheGroupsPartitionExactlyTheRecordedIdSet`; repeating the
        // number here would just be a literal for Task 22 to chase.
        XCTAssertGreaterThan(resolved, 150, "the recorded grouping is nearly empty")
    }

    // `testDeadModelsAreHiddenFromSelectableButStillResolve` (this file, pre-2026-07-27) looped
    // over `Catalog.all.filter { $0.lifecycle == .dead }`, which is empty — 124/124 shipped rows
    // are `.current` — so the loop body has never once executed and the test has never asserted
    // anything. It is deleted rather than fixed, and here is why neither sanctioned option (a
    // hand-built fixture, per the CatalogAdmissionTests policy this file otherwise follows)
    // applies to it:
    //
    //   * The "hidden from selectable" half IS genuinely covered, against a hand-built fixture
    //     with a `.dead` row: `CatalogSelectableTests.testDeadIsExcludedAndSupersededIsIncluded`,
    //     via the internal `Catalog.selectable(task:from:)` seam.
    //   * The "still resolves via `Catalog.model(for:)`" half has no equivalent seam to hang a
    //     fixture on. `Catalog.model(for:)` reads only the package-level `canonical` /
    //     `aliasIndex` dictionaries, built once from `AIMLRegisteredModels.all + Catalog.grokRows`
    //     (`Catalog.swift:38-59`) — there is no injectable-models overload the way
    //     `selectable(task:from:)` provides. Building one only to give this test a fixture would
    //     be a production change in service of a test, not a fix to one.
    //   * `Catalog.model(for:)` also does not read `lifecycle` at all (see its body): resolving
    //     regardless of lifecycle is not a `.dead`-specific fact, it is true of every id, dead or
    //     not, and that general fact is already exercised for real ids by
    //     `CatalogAdmissionTests.testEveryRegisteredSpellingResolvesForAgentAdmission` above and by
    //     `AliasEquivalenceTests.testEveryRecordedSpellingStillResolves`. There is nothing left for
    //     a `.dead`-specific test to add without a live `.dead` row, and shipping one to make this
    //     test executable is explicitly out of scope (it would change what the app offers users).

    /// `list_models`' type filter is `CreateTask`, whose raw values Stage 1 froze as the wire
    /// contract. Every advertised model must answer it.
    func testEverySelectableModelBelongsToExactlyOneTask() {
        for task in CreateTask.allCases {
            for group in Catalog.selectable(task: task) {
                for model in group.models {
                    XCTAssertEqual(model.task, task, "\(model.id) is advertised under the wrong task")
                }
            }
        }
    }

    /// The asymmetry this whole task is about, asserted against the shipped file rather than a
    /// clone: `list_models` filters `.dead`, `generate_*` does not.
    func testTheShippedMCPServiceFiltersDeadFromDiscoveryOnly() throws {
        let source = try Self.mcpServiceSource

        XCTAssertTrue(
            source.contains("ReleaseModelPolicy.allows($0.id)"),
            "curatedModels() must filter .dead at its single source, so all three of its returns "
            + "inherit the filter")
        XCTAssertFalse(
            source.contains("Catalog.synthesized(for: lowerID)"),
            "generate_* must never synthesize an unsupported model from "
            + "an earlier session")
        XCTAssertTrue(
            source.contains("private static func isServed(_ model: CatalogModel, by live: Set<String>) -> Bool"),
            "the live-served check must go through the alias-aware helper, not a bare "
            + "live.contains(model.id)")
        XCTAssertEqual(
            source.components(separatedBy: "Self.isServed(").count - 1, 2,
            "both the advertisement and the generate gate must use it")
    }
}
