import XCTest
@testable import GenStationCore

/// Phase A of spec § 6 — the gate that makes the data transform reviewable.
///
/// For all 209 registered ids and 9 unregistered probes, every capability field of
/// `Catalog.resolve(_:)` must equal what `ModelRegistry.enhancedModelFor(id:)?.base` returned.
/// The expected side is `RegistryCapabilities`, recorded by *running* the registry; the actual
/// side is derived from *parsing* it. The two derivations are independent, which is what stops
/// this being the generator checking its own homework.
///
/// **Known limit, stated so a green run is not over-read:** this compares capability only.
/// `displayName`, `family`, `lifecycle` and `typicalWallClock` have no counterpart in the registry,
/// so this test cannot see them. That is not the same as unfalsifiable: `displayName` is seeded from
/// `info.name` and `family` from `info.developer`, both present on 907/907 entries of
/// `Fixtures/aiml-models-response.json` (spec § 3.4), so a wrong one of those is a deliberate
/// override rather than a guess. `lifecycle` and `typicalWallClock` have no source of truth anywhere
/// and remain the stage's declared blind spot (spec § 2), carried on the live-test checklist.
final class CatalogEquivalenceTests: XCTestCase {

    /// Stage 3 Task 22 deleted these 8 registered spellings from the catalog: the live `/models`
    /// capture no longer serves them (`tools/compute_delete_list.py`), so `Catalog` correctly
    /// stops resolving them as registered. `RegistryCapabilities` is a frozen recording of
    /// `ModelRegistry.enhancedModelFor(id:)`, taken by running the registry before
    /// `ModelRegistry.swift` was deleted (Task 18) — it cannot be re-taken, and it still says
    /// these 8 are registered. This set is what keeps that permanent disagreement from reading
    /// as catalog drift: below, it is asserted as an exact fact (not just excluded), so a 9th id
    /// silently disappearing still fails loudly. Adding to this set requires the same
    /// justification these 8 have — a probe-confirmed deletion recorded in a commit message —
    /// never a convenience exclusion for an inconvenient failure.
    private static let task22DeletedSpellings: Set<String> = [
        "flux-2/edit",
        "flux-pro/v1.1",
        "google/veo-3",
        "klingai/v1-standard/text-to-video",
        "ltxv-2-fast",
        "minimax/video-01",
        "pixverse/v5.5-image-to-video",
        "pixverse/v5.5-text-to-video",
    ]

    /// These two Topaz sharpen models are schema-URI-only (format: uri, no base64), confirmed by
    /// live probe 2026-08-11. The frozen RegistryCapabilities recording says acceptsBase64: true
    /// (what ModelRegistry returned before deletion), but the schema documents the truth. We trust
    /// the probe over the historical recording for this field only, on a per-model basis.
    private static let topazBase64SchemaCorrections: Set<String> = [
        "topaz-labs/sharpen",
        "topaz-labs/sharpen-gen",
    ]

    /// The mirror image of `task22DeletedSpellings`: spellings `Catalog` resolves that the frozen
    /// `RegistryCapabilities` recording (taken before `ModelRegistry.swift` was deleted) never
    /// registered, because they did not exist yet. Task 5's Nano Banana 2 intake (2026-08-11) added
    /// these 3 directly to `CatalogModel`/`ParamCatalog` — there is no `reg()` literal for them to
    /// have been recorded from. As with the deleted set, this is asserted as an exact fact so a 4th
    /// id appearing here unexplained still fails loudly.
    private static let task5AddedSpellings: Set<String> = [
        "google/gemini-3.1-flash-image-preview",
        "google/gemini-3-1-flash-lite-image",
        "nano-banana-2",
    ]

    /// Same rationale as `task5AddedSpellings`, one intake later: Task 6's Seedream 5.0 Pro +
    /// FLUX.2 Max intake (2026-08-11) added these 3 directly, with no `reg()` literal either.
    /// Kept as its own named set rather than folded into `task5AddedSpellings` so each intake's
    /// contribution stays individually named and a future 4th id still fails loudly.
    private static let task6AddedSpellings: Set<String> = [
        "bytedance/seedream-5-0-pro",
        "bytedance/dola-seedream-5-0-pro",
        "blackforestlabs/flux-2-max",
    ]

    /// Field-by-field, with the field named in every failure message so a red run points at the
    /// broken field of the broken model rather than at "a row differs". Skips Task 22's 8 deleted
    /// spellings: the recording says they are registered, `Catalog` correctly says they are not,
    /// and that disagreement is the asserted fact in `testTheFixtureCoversEveryRegisteredIDAndBothBranches`
    /// below rather than something this per-field loop can express.
    func testEveryRecordedRowMatchesTheCatalog() {
        for row in RegistryCapabilities.rows where !Self.task22DeletedSpellings.contains(row.queriedID) {
            let model = Catalog.resolve(row.queriedID)
            let what = row.queriedID

            // Identity. `row.id` is the frozen recording's own answer — what the deleted registry
            // actually returned for this query, independent of anything `Catalog` computes. The
            // alias index is allowed to map it forward (that is the legitimate 209 -> 122
            // collapse), but the row it lands on must be the same row `Catalog.resolve` picked.
            // Comparing `row.queriedID` here (as an earlier draft did) would run
            // `Catalog.canonicalID` against both sides of the assertion, making it unfalsifiable —
            // a re-election of which spelling is canonical within a group would agree with itself.
            XCTAssertEqual(Catalog.canonicalID(for: row.id) ?? row.id.lowercased(), model.id,
                           "\(what): id")
            XCTAssertEqual(model.isRegistered, row.isRegistered, "\(what): isRegistered")

            // Capability — AIMLModel's 14 fields.
            XCTAssertEqual(model.isVideo, row.isVideo, "\(what): isVideo")
            XCTAssertEqual(model.task, CreateTask(isVideo: row.isVideo), "\(what): task")
            XCTAssertEqual(model.isI2I, row.isI2I, "\(what): isI2I")
            XCTAssertEqual(model.requiresInputImage, row.requiresInputImage,
                           "\(what): requiresInputImage")
            XCTAssertEqual(model.supportsMask, row.supportsMask, "\(what): supportsMask")
            XCTAssertEqual(model.maxInputImages, row.maxInputImages, "\(what): maxInputImages")
            XCTAssertEqual(model.imageInputParam, row.imageInputParam,
                           "\(what): imageInputParam")
            XCTAssertEqual(model.secondImageParam, row.secondImageParam,
                           "\(what): secondImageParam")
            XCTAssertEqual(model.acceptsMultiImages, row.acceptsMultiImages, "\(what): acceptsMultiImages")
            if !Self.topazBase64SchemaCorrections.contains(row.queriedID) {
                XCTAssertEqual(model.acceptsBase64, row.acceptsBase64, "\(what): acceptsBase64")
            }
            XCTAssertEqual(model.acceptsPublicURL, row.acceptsPublicURL,
                           "\(what): acceptsPublicURL")
            XCTAssertEqual(model.acceptsBinary, row.acceptsBinary, "\(what): acceptsBinary")
            XCTAssertEqual(model.generationEndpoint, row.generationEndpoint,
                           "\(what): generationEndpoint")
            XCTAssertEqual(model.pollingEndpoint, row.pollingEndpoint,
                           "\(what): pollingEndpoint")

            // The branch itself: `model(for:)` is honest nil for an id the registry did not know.
            XCTAssertEqual(Catalog.model(for: row.queriedID) != nil, row.isRegistered,
                           "\(what): model(for:) took the wrong branch")
        }
    }

    /// The fixture must cover both branches, or the loop above is half vacuous. The 218 here is
    /// the size of a frozen recording, not a property of the catalog, so no later task moves it.
    func testTheFixtureCoversEveryRegisteredIDAndBothBranches() {
        XCTAssertEqual(RegistryCapabilities.rows.count, 218)
        XCTAssertEqual(RegistryCapabilities.rows.filter(\.isRegistered).count, 209)
        XCTAssertEqual(RegistryCapabilities.rows.filter { !$0.isRegistered }.count, 9)

        // Scoped rather than a bare set-equality, since Task 22 deliberately shrank the catalog's
        // membership relative to this frozen recording. The recording (209 registered) and the
        // catalog's spellings (201) now differ by exactly the 8 deleted ids -- asserted as a fact
        // rather than silently excluded, so a 9th id disappearing (or one of the 8 coming back)
        // still fails here, naming the offender.
        let registered = Set(RegistryCapabilities.rows.filter(\.isRegistered).map(\.queriedID))
        let spellings = Set(AIMLRegisteredModels.all.flatMap { [$0.id] + $0.aliases })
        XCTAssertEqual(registered.subtracting(spellings), Self.task22DeletedSpellings,
                       "the recorded ids no longer in the catalog must be exactly Task 22's "
                       + "delete list -- a different set means something else silently "
                       + "disappeared (or one of the 8 silently came back)")
        XCTAssertEqual(spellings.subtracting(registered), Self.task5AddedSpellings.union(Self.task6AddedSpellings).union(["alibaba/wan-3-0-video", "bytedance/seedance-2-5", "minimax/h3-max", "gpt-image-2.5-flare", "gpt-image-2.5-sunburst", "openai/gpt-image-2.5-flare", "openai/gpt-image-2.5-sunburst"]),
                       "the catalog resolves a spelling the recorded registry never registered, and "
                       + "it is not exactly Task 5's + Task 6's added sets: "
                       + "\(spellings.subtracting(registered).sorted())")

        // The synthesis branch's own sub-branches, which nothing else exercises: video-by-token,
        // i2i-by-token, and the no-slash provider fallback.
        let unregistered = RegistryCapabilities.rows.filter { !$0.isRegistered }
        XCTAssertTrue(unregistered.contains { $0.isVideo && $0.isI2I })
        XCTAssertTrue(unregistered.contains { $0.isVideo && !$0.isI2I })
        XCTAssertTrue(unregistered.contains { !$0.isVideo && $0.requiresInputImage })
        XCTAssertTrue(unregistered.contains { !$0.isVideo && !$0.isI2I })
        XCTAssertTrue(unregistered.contains { !$0.queriedID.contains("/") })
    }

    /// `enhancedModelFor(id:)` returns nil **if and only if** the id is nil or empty
    /// (`ModelRegistry.swift:2082-2084`); every other id gets an unconditional synthesis at
    /// `:2104`. The catalog splits that into two named entry points, so the empty id is asserted
    /// here rather than recorded — it is the one input where the two APIs deliberately differ.
    func testAnEmptyIDHasNoCatalogModelButStillSynthesizes() {
        XCTAssertNil(Catalog.model(for: ""))
        XCTAssertNil(Catalog.canonicalID(for: ""))
        XCTAssertFalse(Catalog.resolve("").isRegistered)
        XCTAssertEqual(Catalog.resolve("").id, "")
    }

    /// The store's shape, phrased so it survives the collapse: every recorded spelling resolves,
    /// in any casing; `all` is sorted and duplicate-free; an id the registry never knew stays
    /// unknown. No row count anywhere.
    func testTheStoreResolvesEveryRecordedSpellingCaseInsensitively() {
        let ids = Catalog.all.map(\.id)
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, ids.count)

        // Same skip as testEveryRecordedRowMatchesTheCatalog and for the same reason: these 8
        // spellings are registered in the frozen recording but Task 22 deleted them from the
        // catalog, so they correctly no longer resolve. That fact is asserted once, as a set, in
        // testTheFixtureCoversEveryRegisteredIDAndBothBranches -- not re-litigated here.
        for row in RegistryCapabilities.rows
        where row.isRegistered && !Self.task22DeletedSpellings.contains(row.queriedID) {
            XCTAssertNotNil(Catalog.canonicalID(for: row.queriedID), row.queriedID)
            XCTAssertNotNil(Catalog.canonicalID(for: row.queriedID.uppercased()), row.queriedID)
        }
        XCTAssertNil(Catalog.canonicalID(for: "alibaba/qwen-image-3"))
        XCTAssertEqual(Catalog.model(for: "GPT-Image-2")?.maxInputImages, 16)
        XCTAssertEqual(Catalog.model(for: "LUMA/Ray-2")?.id, "luma/ray-2")
    }
}
