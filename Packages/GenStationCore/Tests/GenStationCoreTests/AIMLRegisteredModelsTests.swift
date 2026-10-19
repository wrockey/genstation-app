import XCTest
@testable import GenStationCore

/// The generated rows, checked for the properties the generator claims. These are not a
/// restatement of the generator's output — they are the invariants a *bad* parse would break:
/// a swallowed group, a duplicated key, a flattened id-dependent group, an id the descriptor
/// tables have never heard of.
///
/// Post-Task-11: three methods. Two are written against **spellings** (each row's `id` plus its
/// `aliases`), which is what keeps them meaningful across the 201 -> 122 collapse. The first
/// method now asserts both shapes at once — `rows.count == 122` alongside the 201-spelling
/// union — because after the collapse "one row per model" and "one spelling per row-or-alias"
/// are both true and both worth pinning. The provisional pre-collapse method this class used to
/// have (`testTheRowsAreInTheProvisionalPreCollapseShape`) is gone: Task 11 deleted it, as its
/// own doc comment said it would.
final class AIMLRegisteredModelsTests: XCTestCase {

    /// Every id the rows claim to answer to: canonical ids plus aliases, flattened.
    private static var spellings: [String] {
        AIMLRegisteredModels.all.flatMap { [$0.id] + $0.aliases }
    }

    /// Looks a model up by any spelling. Before Task 11 that is an id match; after it, an alias
    /// match. Same call site either way.
    private func row(_ id: String) throws -> CatalogModel {
        try XCTUnwrap(AIMLRegisteredModels.all.first { $0.id == id || $0.aliases.contains(id) },
                      "no row spells \(id)")
    }

    func testEveryRegisteredSpellingHasExactlyOneRow() {
        let rows = AIMLRegisteredModels.all
        XCTAssertEqual(rows.count, 131,
                       "expected one row per model; 121 reg() groups, one of which splits on "
                       + "hasSuffix(\"gpt-image-2\"), plus the 2 rows Task 5 intake added "
                       + "(google/gemini-3.1-flash-image-preview, google/gemini-3-1-flash-lite-image), "
                       + "plus the 2 rows Task 6 intake added "
                       + "(bytedance/seedream-5-0-pro, blackforestlabs/flux-2-max)")

        let ids = rows.map(\.id)
        XCTAssertEqual(Set(ids).count, 131, "duplicate canonical ids in the generated rows")
        XCTAssertEqual(ids.filter { $0 != $0.lowercased() }, [], "every id must be lowercased")

        // Task 11's collapse, then Task 22's deletion, then Task 5's Nano Banana 2 intake (2026-08-11,
        // +3 spellings: 2 canonical ids and 1 alias), then Task 6's Seedream 5.0 Pro + FLUX.2 Max
        // intake (+3 spellings: 2 canonical ids and 1 alias). The spellings are the union, and it
        // must be exactly the current 214.
        let spellings = rows.flatMap { [$0.id] + $0.aliases }
        XCTAssertEqual(spellings.count, 214, "the 214 registered spellings must all be accounted for")
        XCTAssertEqual(Set(spellings).count, 214, "a spelling appears on two rows")
        XCTAssertEqual(Set(ids).intersection(rows.flatMap(\.aliases)), [],
                       "the canonical set and the alias set must be disjoint")
        XCTAssertEqual(rows.filter { !$0.aliases.isEmpty }.count, 53)
        XCTAssertEqual(rows.filter { $0.aliases != $0.aliases.sorted() }, [])

        XCTAssertEqual(rows.filter { !$0.isRegistered }, [])
        XCTAssertEqual(rows.filter { $0.provider != .aimlapi }, [])
        XCTAssertEqual(rows.filter { $0.lifecycle != .current }, [])
        // Stage 3 Task 13 populates typicalWallClock on video rows; CatalogWallClockTests owns
        // the per-family values, this just pins the video/non-video split at the row level.
        XCTAssertEqual(rows.filter { $0.task != .video && $0.typicalWallClock != nil }, [])
        XCTAssertEqual(rows.filter { $0.task == .video && $0.typicalWallClock == nil }.count, 5,
                       "OmniHuman and Kandinsky 5 are the two video families with no estimate")

        // The video/image split the registry declares, so a group parsed with the wrong
        // isVideo shows up here rather than at a call site. Per model now, not per spelling —
        // the split over the 201 spellings is TableCoverageTests' concern.
        XCTAssertEqual(rows.filter(\.isVideo).count, 77)
        XCTAssertEqual(rows.filter { !$0.isVideo }.count, 54)
        XCTAssertEqual(rows.filter { $0.task == .video }.count, 77)
    }

    /// `rows.map(\.id) == rows.map(\.id).sorted()` used to stand in for "the generator emits
    /// sorted rows", but `AIMLRegisteredModels.all` ends in `.sorted { $0.id < $1.id }`
    /// (`AIMLRegisteredModels.swift:26`) — that assertion is comparing the sort's own output to
    /// itself and can never fail no matter what order the 23 per-vendor files are in. This checks
    /// what the claim is actually about: each per-vendor file, which the generator writes
    /// independently and which `.all` only concatenates before its own sort runs.
    func testEachGeneratedFileEmitsItsOwnRowsSortedByID() {
        let files: [(String, [CatalogModel])] = [
            ("imageAlibabaRows", AIMLRegisteredModels.imageAlibabaRows),
            ("imageBlackForestLabsRows", AIMLRegisteredModels.imageBlackForestLabsRows),
            ("imageByteDanceRows", AIMLRegisteredModels.imageByteDanceRows),
            ("imageGoogleRows", AIMLRegisteredModels.imageGoogleRows),
            ("imageKlingRows", AIMLRegisteredModels.imageKlingRows),
            ("imageOpenAIRows", AIMLRegisteredModels.imageOpenAIRows),
            ("imageRecraftRows", AIMLRegisteredModels.imageRecraftRows),
            ("imageReveRows", AIMLRegisteredModels.imageReveRows),
            ("imageStabilityAIRows", AIMLRegisteredModels.imageStabilityAIRows),
            ("imageTencentRows", AIMLRegisteredModels.imageTencentRows),
            ("imageTopazRows", AIMLRegisteredModels.imageTopazRows),
            ("imageXAIRows", AIMLRegisteredModels.imageXAIRows),
            ("videoAlibabaRows", AIMLRegisteredModels.videoAlibabaRows),
            ("videoByteDanceRows", AIMLRegisteredModels.videoByteDanceRows),
            ("videoGoogleRows", AIMLRegisteredModels.videoGoogleRows),
            ("videoKandinskyRows", AIMLRegisteredModels.videoKandinskyRows),
            ("videoKlingRows", AIMLRegisteredModels.videoKlingRows),
            ("videoLightricksRows", AIMLRegisteredModels.videoLightricksRows),
            ("videoLumaRows", AIMLRegisteredModels.videoLumaRows),
            ("videoMinimaxRows", AIMLRegisteredModels.videoMinimaxRows),
            ("videoOpenAIRows", AIMLRegisteredModels.videoOpenAIRows),
            ("videoPixVerseRows", AIMLRegisteredModels.videoPixVerseRows),
            ("videoRunwayRows", AIMLRegisteredModels.videoRunwayRows),
        ]
        XCTAssertEqual(files.count, 23, "expected one entry per per-vendor file")
        for (name, rows) in files {
            let ids = rows.map(\.id)
            XCTAssertEqual(ids, ids.sorted(), "\(name) is not sorted by id")
        }
    }

    /// The one group whose capabilities depend on which alias you asked for
    /// (`ModelRegistry.swift:1872-1885`). Flattening it is the single most damaging thing a
    /// generator could do quietly, so it is asserted from both sides.
    func testTheGPTImageGroupSplitIntoDistinctRows() throws {
        for id in ["gpt-image-2", "openai/gpt-image-2"] {
            let m = try row(id)
            XCTAssertTrue(m.isI2I, "\(id) isI2I")
            XCTAssertEqual(m.maxInputImages, 16, "\(id) maxInputImages")
            XCTAssertTrue(m.supportsMask, "\(id) supportsMask")
        }
        for id in ["gpt-image-1.5", "openai/gpt-image-1.5", "openai/gpt-image-1-5"] {
            let m = try row(id)
            XCTAssertFalse(m.isI2I, "\(id) isI2I")
            XCTAssertEqual(m.maxInputImages, 4, "\(id) maxInputImages")
            XCTAssertFalse(m.supportsMask, "\(id) supportsMask")
        }

        // The other mask-capable model, which is a separate group (`:488-507`) and must not have
        // been folded in with these.
        for id in ["gpt-image-1", "openai/gpt-image-1"] {
            let m = try row(id)
            XCTAssertTrue(m.supportsMask, "\(id) supportsMask")
            XCTAssertEqual(m.maxInputImages, 4, "\(id) maxInputImages")
        }

        // The split itself: the two halves must be two rows, not one row reached twice.
        XCTAssertNotEqual(try row("gpt-image-2").id, try row("gpt-image-1.5").id)
    }

    /// Coverage from the catalog's side. `TableCoverageTests` asserts this by scanning
    /// `ModelRegistry.swift` as text; this asserts it against the rows that will replace it, so
    /// the day the registry is deleted (Task 18) the guarantee does not go with it.
    ///
    /// `ParamCatalog` keys **per alias, on purpose** (`ParamCatalog.swift:9-11`) — 201 keys
    /// pointing at 67 tables (grouped by 121 former `reg()` groups; several groups share a table) —
    /// and it keeps doing so after the collapse. That is why the comparison is against spellings and
    /// not against `all`. (This read "121 tables" until 2026-07-27; 121 is the group count, not the
    /// table count — see `ParamCatalog.swift:3-4`.)
    func testEveryRegisteredSpellingHasADescriptorTable() {
        let missing = Self.spellings.filter { ParamCatalog.descriptors(forModelId: $0) == nil }
        XCTAssertEqual(missing.sorted(), [], "generated spellings without a descriptor table")
        XCTAssertEqual(Set(Self.spellings), ParamCatalog.migratedIds,
                       "the catalog's spellings and ParamCatalog's keys are not the same set")
    }
}
