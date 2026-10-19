// The browse surface's logic, against the captured live response.
//
// This is the first test in the repository that can see the model picker's content at all. Until
// this file, the video/image split was a 35-token substring heuristic inside a SwiftUI view's
// private method, and the only evidence it was wrong was a user noticing music models in the video
// list.
//
// What it still cannot see: the rendering. No test here reads a capsule colour, a row's layout or
// whether the sheet presents. That half is on the live-test checklist, as it has been since Stage 2.

import XCTest
@testable import GenStationCore

final class ModelBrowserTests: XCTestCase {

    private static var served: [ServedModel] = []

    override class func setUp() {
        super.setUp()
        served = (try? ServedModel.generationModels(from: AIMLModelsFixture.response())) ?? []
    }

    private var served: [ServedModel] { Self.served }

    // MARK: - Classification

    func testTheCapturedResponseSplitsIntoGenerationModelsByEndpointFamily() {
        XCTAssertEqual(served.count, 337, "grouped generation ids in the captured response")
        XCTAssertEqual(served.filter { $0.task == .video }.count, 210)
        XCTAssertEqual(served.filter { $0.task == .image }.count, 127)
    }

    func testTheElevenMultiFamilyIDsCollapseToOneServedModelEach() {
        // These are the ids the API serves on two endpoint families at once, and they are exactly
        // the 11 duplicated rows `ForEach(others, id: \.self)` used to be handed.
        let duplicated = [
            "google/gemini-2.5-flash-image", "google/gemini-3-pro-image",
            "google/gemini-3-pro-image-preview", "google/gemini-3.1-flash-image",
            "google/gemini-3.1-flash-image-preview", "google/gemini-3.1-flash-lite-image",
            "openai/gpt-image-1", "openai/gpt-image-1-5", "openai/gpt-image-1-mini",
            "openai/gpt-image-1.5", "openai/gpt-image-2",
        ]
        for id in duplicated {
            XCTAssertEqual(served.filter { $0.id == id }.count, 1, "\(id) is still duplicated")
        }
        XCTAssertEqual(Set(served.map(\.id)).count, served.count, "ids must be unique")
    }

    func testEveryServedGenerationModelHasANameAndADeveloper() throws {
        let preferred = try AIMLModelsFixture.infoBySpelling()
        // Three served ids are each simultaneously their own entry's id AND an alias listed inside
        // a *different* entry (`google/nano-banana` is its own generation model, and also an alias
        // of `google/gemini-2.5-flash-image`; likewise the two `-pro`/`-pro-edit` spellings).
        // `ServedModel.generationModels` scopes `bestInfo` to an entry's own id, by design — alias
        // resolution to a canonical catalog row happens later, in `ModelBrowser`. The fixture
        // helper's `infoBySpelling()` is keyed by every spelling (id *and* aliases) for a different
        // purpose (Task 22's delete-list work) and so borrows the other entry's name for these three
        // spellings. Excluded here as a known, narrow id/alias collision, not a decode bug.
        let knownIDAliasCollisions: Set<String> = [
            "google/nano-banana", "google/nano-banana-pro", "google/nano-banana-pro-edit",
        ]
        for model in served {
            XCTAssertFalse(model.displayName.isEmpty, "\(model.id) has no display name")
            XCTAssertFalse(model.developer.isEmpty, "\(model.id) has no developer")
            guard !knownIDAliasCollisions.contains(model.id) else { continue }
            // Cross-check the production preference rule against the fixture helper's independent
            // implementation of the same rule. If the two ever disagree, one of them is picking the
            // chat-completions name over the image-generations one.
            XCTAssertEqual(model.displayName, preferred[model.id]?.name,
                           "\(model.id) chose a different info block than the fixture helper")
        }
    }

    func testExactlyThreeGenerationModelsLackAReleaseDate() {
        XCTAssertEqual(served.filter { $0.releasedAt == nil }.map(\.id).sorted(), [
            "google/gemini-3-1-flash-lite-image",
            "google/gemini-3.1-flash-lite-image",
            "google/gemini-omni-flash-preview",
        ])
    }

    // MARK: - Rows

    /// Rewritten 2026-07-27. The original body checked `row.isRegistered` against a literal
    /// (`ModelBrowser.swift:166` / `:184`) that is guaranteed to already agree with
    /// `Catalog.canonicalID(for: row.id)`'s nil-ness by construction of the two branches
    /// `ModelBrowser.rows` builds its output from — it could not have caught a mutation to either
    /// branch. This adds the one cross-check that can: `row.isRegistered` compared against
    /// `CatalogModel.isRegistered`, the catalog's own **data field** (`CatalogModel.swift`), which
    /// `ModelBrowser.rows` never actually reads — it hardcodes the two literals instead. If a row's
    /// hardcoded flag and the catalog's stored one ever disagree, this is the only test that would
    /// notice.
    func testEveryRowIDIsCanonicalOrUnknownToTheCatalog() {
        for task in CreateTask.allCases {
            for row in ModelBrowser.rows(task: task, served: served, showAll: true) {
                XCTAssertEqual(row.isRegistered, Catalog.model(for: row.id)?.isRegistered ?? false,
                               "\(row.id): row.isRegistered disagrees with the catalog's own field")
                if let canonical = Catalog.canonicalID(for: row.id) {
                    XCTAssertEqual(canonical, row.id,
                                   "\(row.id) is an alias spelling; the picker must offer canonicals")
                } else {
                    XCTAssertFalse(row.isRegistered, "\(row.id) claims to be registered")
                }
            }
        }
    }

    func testAServedAliasResolvesToItsCanonicalCatalogRow() throws {
        // `google/nano-banana-pro` is served only as an alias of `google/gemini-3-pro-image`. If the
        // browser keyed on the served id alone, the registered model behind it would vanish from
        // curated mode — which is the shape of the "39 curated ids missing from advanced" bug.
        let entry = try XCTUnwrap(served.first { $0.aliases.contains("google/nano-banana-pro") }
            ?? served.first { $0.id == "google/nano-banana-pro" })
        XCTAssertEqual(entry.task, .image)
        let offered = Set(ModelBrowser.rows(task: .image, served: served, showAll: false).map(\.id))
        let resolvable = ([entry.id] + entry.aliases).compactMap(Catalog.canonicalID(for:))
        // Loud on purpose: an empty `resolvable` used to let this test pass having asserted
        // nothing — exactly the alias-index regression it exists to catch (`entry.id` or none of
        // its aliases resolve to a catalog row). `XCTUnwrap` fails the test instead of skipping it.
        let canonical = try XCTUnwrap(resolvable.first,
            "none of \(entry.id)'s id/aliases resolve to a catalog row via Catalog.canonicalID(for:)")
        XCTAssertTrue(offered.contains(canonical),
                      "\(canonical) is registered and served, so curated mode must offer it")
    }

    func testCuratedIsRegisteredOnlyAndAdvancedIsASuperset() {
        for task in CreateTask.allCases {
            let curated = ModelBrowser.rows(task: task, served: served, showAll: false)
            let advanced = ModelBrowser.rows(task: task, served: served, showAll: true)
            XCTAssertTrue(curated.allSatisfy(\.isRegistered), "curated offered an unregistered row")
            XCTAssertTrue(Set(curated.map(\.id)).isSubset(of: Set(advanced.map(\.id))),
                          "curated must be a subset of advanced — it was not, before Stage 3")
            XCTAssertEqual(advanced.map(\.id), curated.map(\.id), "A saved advanced preference cannot bypass release support")
            XCTAssertFalse(advanced.isEmpty)
            XCTAssertTrue(advanced.allSatisfy { ReleaseModelPolicy.allows($0.id, task: task) })
        }
    }

    // `testNoDeadModelIsEverOffered` (this file, pre-2026-07-27) iterated all 286 rows
    // `ModelBrowser.rows(task:served:showAll:)` can produce today and asserted none is `.dead` —
    // vacuously, since 124/124 shipped catalog rows are `.current`. Deleting the
    // `model.lifecycle != .dead` filter at `Catalog.swift:162` leaves it green.
    //
    // Deleted rather than fixed. `ModelBrowser.rows` has no seam to hand it a hand-built row set:
    // it calls the public `Catalog.selectable(task:)` directly (`ModelBrowser.swift:132`), not the
    // internal `selectable(task:from:)` seam `CatalogSelectableTests` uses, so there is no way to
    // inject a `.dead` fixture row without either (a) adding a new production overload solely to
    // give this test something to call — a bigger change than the bug it would catch justifies —
    // or (b) shipping a `.dead` row, which is explicitly out of scope. And per
    // `ModelBrowser.swift:130-131`'s own comment, `ModelBrowser` does no lifecycle filtering of its
    // own: it inherits whatever `Catalog.selectable(task:)` already excluded. So the fact this test
    // wants to state — "a dead model never reaches the picker" — is entirely a fact about
    // `Catalog.selectable`, already covered against a real `.dead` fixture row by
    // `CatalogSelectableTests.testDeadIsExcludedAndSupersededIsIncluded`; there is no additional
    // ModelBrowser-side behavior left for this test to exercise.

    func testOrderingIsNewestFirstWithMissingDatesLast() {
        let rows = ModelBrowser.rows(task: .video, served: served, showAll: true)
        XCTAssertGreaterThan(rows.count, 1)
        let dates = rows.map { $0.releasedAt ?? "" }
        XCTAssertEqual(dates, dates.sorted(by: >), "rows are not in newest-first order")
        if let firstMissing = rows.firstIndex(where: { $0.releasedAt == nil }) {
            XCTAssertTrue(rows[firstMissing...].allSatisfy { $0.releasedAt == nil },
                          "a dated row sorted after an undated one")
        }
    }

    // MARK: - Sections

    func testEachRowAppearsInExactlyOneSection() {
        let sections = ModelBrowser.sections(
            task: .image, served: served, showAll: true, search: "",
            favorites: ["gpt-image-1"], recents: ["gpt-image-2"])
        let ids = sections.flatMap(\.rows).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count,
                       "a row is in two sections; flattening would duplicate SwiftUI identities")
        for section in sections {
            let sectionIDs = section.rows.map(\.id)
            XCTAssertEqual(Set(sectionIDs).count, sectionIDs.count,
                           "section \(section.title) contains a duplicate id")
        }
    }

    func testSelectableIDsAreExactlyTheSectionedRowIDs() {
        let ids = ModelBrowser.selectableIDs(task: .video, served: served, showAll: true)
        let sectioned = ModelBrowser.sections(
            task: .video, served: served, showAll: true, search: "",
            favorites: [], recents: []).flatMap(\.rows).map(\.id)
        XCTAssertEqual(Set(ids), Set(sectioned))
        XCTAssertEqual(ids.count, sectioned.count)
    }

    func testSearchIsScopedToIDDisplayNameAndFamily() {
        let all = ModelBrowser.sections(task: .video, served: served, showAll: true,
                                        search: "", favorites: [], recents: [])
        let kling = ModelBrowser.sections(task: .video, served: served, showAll: true,
                                          search: "  KLING  ", favorites: [], recents: [])
        let allRows = all.flatMap(\.rows)
        let klingRows = kling.flatMap(\.rows)
        XCTAssertLessThan(klingRows.count, allRows.count)
        XCTAssertFalse(klingRows.isEmpty)
        for row in klingRows {
            XCTAssertTrue(ModelBrowser.matches(row, "kling"), "\(row.id) does not match the query")
        }
    }

    func testRecommendedComesFromTheVendorsOwnFlag() {
        let sections = ModelBrowser.sections(task: .video, served: served, showAll: true,
                                             search: "", favorites: [], recents: [])
        let recommended = sections.first { $0.kind == .recommended }
        XCTAssertNotNil(recommended, "14 captured video models carry info.isHottest")
        for row in recommended?.rows ?? [] {
            XCTAssertTrue(row.isRecommended)
        }
    }

    // MARK: - Badges

    func testTheProviderBadgeAppearsOnlyWhenTheListSpansProviders() {
        let aimlOnly = ModelBrowser.rows(task: .image, served: served, showAll: false)
        for row in aimlOnly {
            XCTAssertFalse(row.badges.contains { if case .provider = $0 { return true }
                                                 else { return false } },
                           "\(row.id) shows a provider badge in a single-provider list")
        }
        // Grok's two native rows (Task 14) are `.grok` and have no `/models` entry, so this is the
        // only way to build a provider-spanning list today — and it is how Stage 5's browser will.
        let both = ModelBrowser.rows(task: .image, served: served, showAll: false,
                                     providers: [.aimlapi, .grok])
        XCTAssertTrue(both.contains { $0.provider == .grok }, "Grok's rows must survive the gate")
        XCTAssertTrue(both.allSatisfy { row in
            row.badges.contains { if case .provider = $0 { return true } else { return false } }
        }, "every row in a multi-provider list must say which provider it is")
    }

    func testTheUnregisteredAndSupersededBadgesAreData() {
        XCTAssertEqual(
            ModelBrowser.badges(provider: .aimlapi, lifecycle: nil,
                                isRegistered: false, knownIssue: nil, includeProvider: false),
            [.unregistered])
        XCTAssertEqual(
            ModelBrowser.badges(provider: .aimlapi, lifecycle: .superseded,
                                isRegistered: true, knownIssue: nil, includeProvider: false),
            [.superseded])
        XCTAssertEqual(
            ModelBrowser.badges(provider: .grok, lifecycle: .current,
                                isRegistered: true, knownIssue: nil, includeProvider: true),
            [.provider("Grok")])
        XCTAssertEqual(ModelBrowser.Badge.unregistered.label, "No preset")
        XCTAssertFalse(ModelBrowser.Badge.superseded.help.isEmpty)
    }

    func testAKnownIssueRowCarriesTheBadgeWithItsOwnText() {
        let badges = ModelBrowser.badges(provider: .aimlapi, lifecycle: .current,
                                         isRegistered: true,
                                         knownIssue: "Upstream image handling is broken (reported 2026-08-11).",
                                         includeProvider: false)
        XCTAssertEqual(badges, [.knownIssue("Upstream image handling is broken (reported 2026-08-11).")])
    }

    func testTheFourVendorBrokenRowsAreBadgedAndEverythingElseIsNot() {
        let flagged = Catalog.all.filter { $0.knownIssue != nil }.map(\.id).sorted()
        XCTAssertEqual(flagged, ["alibaba/qwen-image-2.0", "alibaba/wan2.6-image",
                                 "topaz-labs/sharpen", "topaz-labs/sharpen-gen"])
    }
}
