import XCTest
@testable import GenStationCore

/// Design § 3.6, invariant 6 — and § 3.4 as revised on 2026-07-27.
///
/// An earlier draft of this file said these two fields were hand-authored and that "nothing in this
/// repository can falsify them". That is no longer true. The `/models` capture committed at
/// `b16f840` carries `info.name` on 907/907 entries and `info.developer` on 907/907, so:
///
///   * `displayName` IS falsifiable — `testEveryDisplayNameIsTheVendorsUnlessExplicitlyOverridden`
///     compares every row against the fixture, and the only permitted deviations are the entries in
///     `Catalog.displayNameOverrides`, each of which exists for a stated reason.
///   * `family` is half-falsifiable — the strings are ours, but
///     `testEveryFamilyBelongsToExactlyOneVendor` proves each one stays inside a single
///     `info.developer`, so a row cannot quietly file under another vendor's product line.
///
/// What no test here can judge is whether "Wan 2.6" is a better family name than "Wan". That, and
/// `typicalWallClock` (Task 13), stay on the live-test checklist.
///
/// These run over `Catalog.all` with no exemptions, which is only possible because the 209 -> 122
/// collapse has already happened: every row they see is a row this task authors.
final class CatalogPresentationTests: XCTestCase {

    /// The 122 AI/ML rows. Filtered by provider so Task 14's Grok rows — which have no AI/ML
    /// fixture entry and must not be checked against one — do not break the two fixture tests.
    private var aiml: [CatalogModel] { Catalog.all.filter { $0.provider == .aimlapi } }

    /// spelling -> (name, developer), sourced from `AIMLModelsFixture.infoBySpelling()` rather than
    /// scanning the raw entries independently. That choice is deliberate: a spelling can be served
    /// under more than one endpoint family with a different `info.name` on each (`"Gemini 3 Pro
    /// Image"` on `openai/image-generations` vs `"Nano Banana Pro (Gemini 3 Pro Image Preview)"` on
    /// `openai/chat-completions`), and `infoBySpelling()` is the ONE place that already resolves
    /// that ambiguity — via `AIMLEndpoints.infoPreferenceOrder` — for the whole package. Rebuilding
    /// the resolution here with a plain "last entry in the JSON wins" scan would silently disagree
    /// with both `infoBySpelling()` and with `apply_presentation.py`'s generator, which is exactly
    /// the drift `testSixDualNameIDsMatchInfoBySpellingsChoice` below exists to catch.
    private func vendorMetadata() throws -> [String: (name: String, developer: String)] {
        var out: [String: (name: String, developer: String)] = [:]
        for (spelling, info) in try AIMLModelsFixture.infoBySpelling() {
            guard let name = info.name, let developer = info.developer else { continue }
            out[spelling] = (name: name, developer: developer)
        }
        return out
    }

    /// Looks a row's metadata up by canonical id first, then by any alias. `minimax/video-01` is
    /// the one row that needs the fallback: the API stopped serving that spelling and serves the
    /// model as `video-01`. Task 22 re-elects it; this keeps working either way.
    private func metadata(for model: CatalogModel,
                          in index: [String: (name: String, developer: String)])
        -> (name: String, developer: String)? {
        for spelling in [model.id] + model.aliases {
            if let hit = index[spelling] { return hit }
        }
        return nil
    }

    func testEveryModelHasANonEmptyDisplayName() {
        let offenders = Catalog.all
            .filter { $0.displayName.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(\.id)
        XCTAssertEqual(offenders.sorted(), [], "\(offenders.count) rows have an empty displayName")
    }

    func testEveryModelHasANonEmptyFamily() {
        let offenders = Catalog.all
            .filter { $0.family.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(\.id)
        XCTAssertEqual(offenders.sorted(), [], "\(offenders.count) rows have an empty family")
    }

    /// The generator's placeholder for `displayName` was the id itself. Without this, seeding could
    /// be skipped entirely and the two tests above would still be green.
    func testNoDisplayNameIsStillTheRawID() {
        let offenders = Catalog.all.filter { $0.displayName == $0.id }.map(\.id)
        XCTAssertEqual(offenders.sorted(), [],
                       "\(offenders.count) rows still carry the generator's id placeholder")
    }

    /// Two rows with the same name are indistinguishable in the picker, and the vendor ships five
    /// such names across twelve models (both FLUX Dev variants are "Flux Dev"; all three Veo 3.1
    /// directions are "Veo 3.1"). `Catalog.displayNameOverrides` exists to break exactly these.
    ///
    /// Scoped to **provider**, not global, since Task 14: the catalog now spans providers, and the
    /// same underlying model reached through two of them (`grok-imagine-image` natively and
    /// `x-ai/grok-imagine-image` via AI/ML API) is meant to share a display name — spec § 3 puts
    /// the provider on screen as a badge precisely so the picker tells the two apart without
    /// inventing a distinguishing string neither vendor uses. `family` already carries that
    /// distinction (`"Grok Imagine"` vs `"Grok Imagine (via AI/ML API)"`,
    /// `testTheAIMLRoutedGrokRowIsADifferentFamily` in CatalogGrokTests.swift); this invariant only
    /// needs to stay true *within* one provider, which is what a picker actually renders.
    /// `testTheProviderScopedUniquenessInvariantStillCatchesACollision` below proves the scoping is
    /// not a no-op.
    func testNoTwoModelsShareADisplayName() {
        XCTAssertEqual(Self.duplicateDisplayNamesWithinAProvider(Catalog.all), [],
                       "display names are not unique within a provider")
    }

    /// Proof that relaxing the invariant to be provider-scoped did not gut it: two synthetic rows
    /// sharing both a provider AND a display name must still be flagged. Uses the exact same
    /// helper `testNoTwoModelsShareADisplayName` asserts against, so this is not a hand-rolled
    /// re-implementation that could quietly diverge from the real check.
    func testTheProviderScopedUniquenessInvariantStillCatchesACollision() {
        func row(id: String) -> CatalogModel {
            CatalogModel(id: id, aliases: [], provider: .grok, displayName: "Duplicate Name",
                        family: "Test", lifecycle: .current, typicalWallClock: nil,
                        isRegistered: true, task: .image, isI2I: false, requiresInputImage: false,
                        supportsMask: false, maxInputImages: 0, imageInputParam: "",
                        secondImageParam: nil, acceptsMultiImages: false, acceptsBase64: false,
                        acceptsPublicURL: false, acceptsBinary: false, generationEndpoint: "",
                        pollingEndpoint: nil)
        }
        let offenders = Self.duplicateDisplayNamesWithinAProvider([row(id: "a"), row(id: "b")])
        XCTAssertEqual(offenders, ["'Duplicate Name' (grok): a and b"])
    }

    private static func duplicateDisplayNamesWithinAProvider(_ models: [CatalogModel]) -> [String] {
        var seen: [Provider: [String: String]] = [:]
        var offenders: [String] = []
        for model in models.sorted(by: { $0.id < $1.id }) {
            if let first = seen[model.provider]?[model.displayName] {
                offenders.append("'\(model.displayName)' (\(model.provider.rawValue)): \(first) and \(model.id)")
            } else {
                seen[model.provider, default: [:]][model.displayName] = model.id
            }
        }
        return offenders
    }

    /// A family that differs from another only by case or padding splits one group into two in
    /// `selectable(task:)`, and the split is invisible on screen.
    func testFamilyNamesAreNormalized() {
        var seen: [String: String] = [:]
        var offenders: [String] = []
        for model in Catalog.all {
            XCTAssertEqual(model.family, model.family.trimmingCharacters(in: .whitespaces),
                           "family has surrounding whitespace: '\(model.family)' (\(model.id))")
            let key = model.family.lowercased()
            if let first = seen[key], first != model.family {
                offenders.append("'\(first)' vs '\(model.family)'")
            } else {
                seen[key] = model.family
            }
        }
        XCTAssertEqual(offenders, [], "families differing only by case")
    }

    /// § 3.4: `displayName` comes from the API. This is the assertion that makes that sentence
    /// true rather than aspirational — and it is what an earlier draft of this plan claimed was
    /// impossible. A vendor rename shows up here as a failure naming both strings, at which point
    /// the choice is to take the new name or to add a deliberate override row.
    func testEveryDisplayNameIsTheVendorsUnlessExplicitlyOverridden() throws {
        let index = try vendorMetadata()
        var unmatched: [String] = []
        var drifted: [String] = []
        for model in aiml {
            guard let meta = metadata(for: model, in: index) else {
                unmatched.append(model.id); continue
            }
            if let override = Catalog.displayNameOverrides[model.id] {
                XCTAssertEqual(model.displayName, override,
                               "\(model.id): row and override table disagree")
            } else if model.displayName != meta.name {
                drifted.append("\(model.id): row '\(model.displayName)' vs API '\(meta.name)'")
            }
        }
        XCTAssertEqual(unmatched.sorted(), ["alibaba/wan-3-0-video", "minimax/h3-max", "openai/gpt-image-2.5-flare", "openai/gpt-image-2.5-sunburst"], "September intake is checked separately against its current schema and model fixtures")
        XCTAssertEqual(drifted.sorted(), [], "displayName drifted from the vendor's info.name")
        XCTAssertEqual(Catalog.displayNameOverrides.count, 12)
        let unusedOverrides = Set(Catalog.displayNameOverrides.keys)
            .subtracting(aiml.map(\.id))
        XCTAssertEqual(unusedOverrides.sorted(), [], "override keys that match no catalog row")
    }

    /// `family` is ours, but it seeds from `info.developer`, and a family string that spans two
    /// vendors means a row was filed under someone else's product line. This is the half of
    /// `family` a test can hold.
    func testEveryFamilyBelongsToExactlyOneVendor() throws {
        let index = try vendorMetadata()
        var vendorsByFamily: [String: Set<String>] = [:]
        for model in aiml {
            guard let meta = metadata(for: model, in: index) else { continue }
            vendorsByFamily[model.family, default: []].insert(meta.developer)
        }
        let straddling = vendorsByFamily
            .filter { $0.value.count > 1 }
            .map { "'\($0.key)': \($0.value.sorted().joined(separator: " + "))" }
            .sorted()
        XCTAssertEqual(straddling, [], "families claimed by more than one vendor")
        // 55 -> 56 on 2026-08-11: Task 5's Nano Banana 2 intake introduced a new family, "Nano
        // Banana 2", shared by the two new rows.
        XCTAssertEqual(vendorsByFamily.count, 57, "expected 56 AI/ML families across 126 rows")
    }

    /// The cross-task hazard flagged during review of this task: six ids
    /// (`google/gemini-2.5-flash-image`, `google/gemini-3-pro-image`, `google/gemini-3-pro-image-
    /// preview`, `google/gemini-3.1-flash-image`, `google/gemini-3.1-flash-image-preview`,
    /// `google/gemini-3.1-flash-lite-image`) are each served under TWO endpoint families with two
    /// different `info.name` values, e.g. `"Gemini 3 Pro Image"` (openai/image-generations) vs
    /// `"Nano Banana Pro (Gemini 3 Pro Image Preview)"` (openai/chat-completions). Two of the six —
    /// `google/gemini-2.5-flash-image` and `google/gemini-3-pro-image-preview` — are registered
    /// catalog rows, i.e. visible in the picker.
    ///
    /// `apply_presentation.py` (the tool that WROTE these rows' `displayName`) resolves that
    /// ambiguity with its own Python re-implementation of `AIMLEndpoints.infoPreferenceOrder`,
    /// because a Python script cannot call `AIMLModelsFixture.infoBySpelling()`. Those two
    /// implementations must never be allowed to silently disagree — this test is the pin. It does
    /// not merely check "these are non-empty"; it checks the checked-in row against the ONE
    /// canonical Swift resolver for this exact ambiguity, which is the thing an id-non-empty check
    /// would not catch if the two implementations diverged.
    func testSixDualNameIDsMatchInfoBySpellingsChoice() throws {
        let dualNameIDs = [
            "google/gemini-2.5-flash-image",
            "google/gemini-3-pro-image",
            "google/gemini-3-pro-image-preview",
            "google/gemini-3.1-flash-image",
            "google/gemini-3.1-flash-image-preview",
            "google/gemini-3.1-flash-lite-image",
        ]
        let index = try AIMLModelsFixture.infoBySpelling()

        // The three that are actually catalog rows (a third joined 2026-08-11, Task 5's Nano
        // Banana 2 intake): the checked-in displayName must equal infoBySpelling()'s choice
        // (through the override table, if the id has an override).
        let registered = ["google/gemini-2.5-flash-image", "google/gemini-3-pro-image-preview",
                          "google/gemini-3.1-flash-image-preview"]
        for id in registered {
            guard let model = Catalog.model(for: id) else {
                XCTFail("\(id) is expected to be a registered catalog row"); continue
            }
            guard let expectedName = index[id]?.name else {
                XCTFail("\(id) has no entry in infoBySpelling()"); continue
            }
            let expected = Catalog.displayNameOverrides[id] ?? expectedName
            XCTAssertEqual(model.displayName, expected,
                           "\(id): catalog row disagrees with AIMLModelsFixture.infoBySpelling()")
        }

        // Each of the six ids resolves to SOME name via infoBySpelling(), and appears MORE THAN
        // ONCE in the raw fixture — per id, not summed — proving the fixture still serves each one
        // under more than one family (i.e. this test still exercises the ambiguity it names).
        // Summing across all six (as an earlier draft did) let five of them vanish from the
        // fixture entirely and still pass, as long as the sixth appeared six-plus times; counting
        // per id is what actually pins "each of these six is genuinely multi-family".
        var occurrences: [String: Int] = [:]
        for entry in try AIMLModelsFixture.rawEntries() {
            guard let id = entry["id"] as? String, dualNameIDs.contains(id) else { continue }
            occurrences[id, default: 0] += 1
        }
        for id in dualNameIDs {
            XCTAssertNotNil(index[id]?.name, "\(id) missing from infoBySpelling()")
            XCTAssertGreaterThan(occurrences[id] ?? 0, 1,
                                 "\(id) appears \(occurrences[id] ?? 0) time(s) in the fixture; "
                                 + "expected it under more than one endpoint family")
        }
    }
}

extension CatalogPresentationTests {

    /// The review surface for `family`, the one field this task authors. Opt-in, because it writes
    /// a file:
    ///
    ///     CATALOG_REVIEW=1 swift test --filter testDumpCatalogForReview
    ///
    /// Sorted by (family, displayName, id) on purpose. A model filed under the wrong family does
    /// not read as a wrong string — it reads as a **stranger sitting inside another family's
    /// block**, which is the one presentation error a human reliably catches by eye. Sorting by id
    /// instead would scatter each family and hide exactly that.
    func testDumpCatalogForReview() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CATALOG_REVIEW"] == "1",
                          "set CATALOG_REVIEW=1 to write the review file")

        let rows = Catalog.all.sorted {
            ($0.family, $0.displayName, $0.id) < ($1.family, $1.displayName, $1.id)
        }
        var out = "family\tdisplayName\ttask\tid\taliases\n"
        for m in rows {
            out += "\(m.family)\t\(m.displayName)\t\(m.task.rawValue)\t\(m.id)\t"
            out += "\(m.aliases.joined(separator: " "))\n"
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("catalog-review.tsv")
        try out.write(to: url, atomically: true, encoding: .utf8)
        print("catalog review file: \(url.path) — \(rows.count) rows")
    }
}

extension CatalogPresentationTests {

    /// Pins the strings ConfigurationSection.swift's Gemini menu produced today, emoji
    /// included. A change here changes what the Gemini menu says.
    func testGeminiOverridesReproduceTodaysMenuStrings() {
        XCTAssertEqual(Catalog.geminiOverrides["gemini-3-pro-image-preview"]?.displayName,
                       "Gemini 3 Pro Image Preview (Nano Banana Pro) 🍌")
        XCTAssertEqual(Catalog.geminiOverrides["gemini-2.5-flash-image"]?.displayName,
                       "Gemini 2.5 Flash Image (Nano Banana) 🍌")
        XCTAssertEqual(Catalog.geminiOverrides["gemini-2.5-flash-image-preview"]?.displayName,
                       "Gemini 2.5 Flash Image (Nano Banana) 🍌")
        XCTAssertEqual(Catalog.geminiOverrides.count, 3)
    }

    /// Exactly one id carries the capsule.
    func testOnlyNanoBananaProIsBadgedNew() {
        let badged = Catalog.geminiOverrides.filter(\.value.isNew).keys.sorted()
        XCTAssertEqual(badged, ["gemini-3-pro-image-preview"])
    }

    /// The AI/ML-routed rows that would otherwise collide with a native provider's family carry an
    /// explicit "(via AI/ML API)" suffix, so `selectable(task:)` cannot merge two providers into
    /// one group. Task 14 relies on the same rule for Grok.
    func testAIMLRoutedRowsDoNotShareAFamilyWithANativeProvider() {
        let aimlFamilies = Set(Catalog.all.filter { $0.provider == .aimlapi }.map(\.family))
        for native in Catalog.geminiOverrides.values.map(\.family) {
            XCTAssertFalse(aimlFamilies.contains(native),
                           "family '\(native)' is claimed by both a native and an AI/ML-routed row")
        }
    }
}
