import XCTest
@testable import GenStationCore

/// `Catalog.merge(live:provider:)` — the shape Gemini needs, because its model list is a live
/// `v1beta/models` fetch and cannot be static rows.
///
/// NOTHING CALLS THIS IN STAGE 3. Gemini's fetch path (GenStationApp.swift:449-538) holds two of
/// the four silent healers — the conditional re-pick at :248-256 and the unconditional one at
/// :526-532 — and wiring the merge on top of Task 20's consolidated healer is Stage 5 (design
/// § 3.7, § 8). The function lands now, with fixtures, so that task only has to change who calls it.
final class CatalogMergeTests: XCTestCase {

    /// Shaped like the rows `fetchAvailableGeminiModels` has after its three filter passes.
    private static let liveRows: [LiveModelRow] = [
        // an id we have an override for
        LiveModelRow(id: "gemini-3-pro-image-preview", displayName: "Gemini 3 Pro Image Preview"),
        // an id we do NOT have an override for
        LiveModelRow(id: "imagen-4.0-generate-001", displayName: "Imagen 4"),
        // a duplicate displayName: two ids Google gives the same name
        LiveModelRow(id: "gemini-2.5-flash-image", displayName: "Gemini 2.5 Flash Image"),
        LiveModelRow(id: "gemini-2.5-flash-image-preview", displayName: "Gemini 2.5 Flash Image"),
        // a row with no displayName at all — the field is Optional for a reason
        LiveModelRow(id: "gemini-3.1-flash-image", displayName: nil),
    ]

    func testOverriddenIDUsesOurNameNotGoogles() throws {
        let merged = Catalog.merge(live: Self.liveRows, provider: .gemini)
        let row = try XCTUnwrap(merged.first { $0.id == "gemini-3-pro-image-preview" })
        XCTAssertEqual(row.displayName, "Gemini 3 Pro Image Preview (Nano Banana Pro) 🍌")
        XCTAssertEqual(row.family, "Gemini 3 Pro Image")
        XCTAssertEqual(row.provider, .gemini)
    }

    func testUnoverriddenIDKeepsGooglesName() throws {
        let merged = Catalog.merge(live: Self.liveRows, provider: .gemini)
        let row = try XCTUnwrap(merged.first { $0.id == "imagen-4.0-generate-001" })
        XCTAssertEqual(row.displayName, "Imagen 4")
        XCTAssertEqual(row.family, "Imagen 4")   // falls back to the display name
    }

    func testMissingDisplayNameFallsBackToTheID() throws {
        let merged = Catalog.merge(live: Self.liveRows, provider: .gemini)
        let row = try XCTUnwrap(merged.first { $0.id == "gemini-3.1-flash-image" })
        XCTAssertEqual(row.displayName, "gemini-3.1-flash-image")
    }

    /// Dedupe keys on the LIVE display name, exactly as GenStationApp.swift:502-503 does, and the
    /// priority list at :506-511 decides the survivor — NOT the override, which is applied after.
    func testDuplicateDisplayNameCollapsesToThePriorityID() {
        let merged = Catalog.merge(live: Self.liveRows, provider: .gemini)
        let flashIDs = merged.map(\.id).filter { $0.hasPrefix("gemini-2.5-flash-image") }
        XCTAssertEqual(flashIDs, ["gemini-2.5-flash-image"],
                       "the -preview spelling must lose to the priority list")
    }

    /// Two ids sharing a name with NEITHER in the priority list: shortest id wins (:517-518).
    func testDuplicateWithNoPriorityIDPrefersTheShortestID() {
        let rows = [
            LiveModelRow(id: "gemini-9-image-preview-0521", displayName: "Gemini 9 Image"),
            LiveModelRow(id: "gemini-9-image", displayName: "Gemini 9 Image"),
        ]
        let merged = Catalog.merge(live: rows, provider: .gemini)
        XCTAssertEqual(merged.map(\.id), ["gemini-9-image"])
    }

    /// The sort is on the FINAL name, with the id as a tiebreak. GenStationApp.swift:520 sorts on
    /// the live name — a string the menu does not show for the overridden rows — and a one-field
    /// `<` leaves equal names in nondeterministic order. Both are corrected here on purpose.
    func testSortIsTotalAndOnTheNameThatIsShown() {
        let merged = Catalog.merge(live: Self.liveRows, provider: .gemini)
        XCTAssertEqual(merged.map(\.displayName), merged.map(\.displayName).sorted())
        for _ in 0..<20 {
            XCTAssertEqual(Catalog.merge(live: Self.liveRows.shuffled(), provider: .gemini)
                            .map(\.id),
                           merged.map(\.id),
                           "merge output must not depend on input order")
        }
    }

    /// Merged rows are real rows, not synthesized ones: `isRegistered` is false only for
    /// `Catalog.synthesized(for:)` (contract).
    func testMergedRowsAreRegisteredImageRows() {
        for row in Catalog.merge(live: Self.liveRows, provider: .gemini) {
            XCTAssertTrue(row.isRegistered, row.id)
            XCTAssertEqual(row.task, .image, row.id)
            XCTAssertEqual(row.lifecycle, .current, row.id)
            XCTAssertNil(row.typicalWallClock, row.id)   // Task 13's invariant, image rows
        }
    }

    /// Fix A (Stage 3 whole-branch triage, item A). `capabilities(for:)` has a real template for
    /// Gemini only — the other three providers used to get a template that type-checked but could
    /// not work (`generationEndpoint: ""`, `maxInputImages: 0`), which is exactly what this test
    /// used to exercise without checking: it asserted `provider`/`displayName` and never touched the
    /// capability fields that were wrong. `merge` now refuses outright: no capabilities template
    /// means no rows, for every provider Stage 3 hasn't wired, not a garbage row with real ids and
    /// display names sitting on top of fabricated capabilities.
    func testANonGeminiProviderProducesNoRowsUntilItHasACapabilitiesTemplate() {
        let rows = [
            LiveModelRow(id: "gemini-3-pro-image-preview", displayName: "Something Else"),
            LiveModelRow(id: "grok-imagine-image", displayName: nil),
        ]
        for provider in Provider.allCases where provider != .gemini {
            XCTAssertTrue(Catalog.merge(live: rows, provider: provider).isEmpty,
                          "\(provider) has no capabilities template yet and must merge to nothing")
        }
    }

    func testEmptyInputProducesEmptyOutput() {
        XCTAssertEqual(Catalog.merge(live: [], provider: .gemini).count, 0)
    }

    /// The merge does not add rows to the store. Stage 3's catalog has no Gemini rows, and
    /// `gemini-3-pro-image-preview` is not a spelling of the AI/ML-routed
    /// `google/gemini-3-pro-image-preview` row.
    func testMergeDoesNotMutateTheCatalog() {
        let before = Catalog.all.count
        _ = Catalog.merge(live: Self.liveRows, provider: .gemini)
        XCTAssertEqual(Catalog.all.count, before)
        XCTAssertNil(Catalog.model(for: "gemini-3-pro-image-preview"),
                     "merge output is returned, never stored — a later stage owns that decision")
    }
}
