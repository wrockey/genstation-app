import XCTest
@testable import GenStationCore

/// The two ids the Grok picker actually sends. Neither is a registry key under any spelling — the
/// registry's only Grok line names `x-ai/grok-imagine-image` and `x-ai/grok-imagine-image-pro`,
/// which are the AI/ML-routed models and a different pair of ids. Before these rows existed, no
/// Grok selection could resolve through the catalog at all.
final class CatalogGrokTests: XCTestCase {

    func testBothPickerIDsResolve() {
        XCTAssertNotNil(Catalog.model(for: "grok-imagine-image"))
        XCTAssertNotNil(Catalog.model(for: "grok-imagine-image-quality"))
    }

    func testTheGrokRowsAreExactlyTheseTwo() {
        let ids = Catalog.all.filter { $0.provider == .grok }.map(\.id).sorted()
        XCTAssertEqual(ids, ["grok-imagine-image", "grok-imagine-image-2.0", "grok-imagine-image-quality"])

    }

    /// The picker labels move out of ConfigurationSection.swift:479-482 verbatim, em dash included.
    /// The closed label used to show the raw id; after this task it shows these.
    func testDisplayNamesAreTodaysPickerLabels() {
        XCTAssertEqual(Catalog.model(for: "grok-imagine-image")?.displayName,
                       "Grok Imagine Image")
        XCTAssertEqual(Catalog.model(for: "grok-imagine-image-quality")?.displayName,
                       "Grok Imagine Image — Quality (2K)")
    }

    /// `AppState.canAddImages` returns false for `.grok` (GenStationApp.swift:2441-2442) and
    /// `maxImageSlots` returns 0 (`:2453-2454`). The rows say the same thing as data.
    func testGrokTakesNoInputImages() throws {
        for id in ["grok-imagine-image", "grok-imagine-image-quality"] {
            let model = try XCTUnwrap(Catalog.model(for: id))
            XCTAssertEqual(model.task, .image)
            XCTAssertFalse(model.isVideo)
            XCTAssertFalse(model.isI2I, id)
            XCTAssertFalse(model.requiresInputImage, id)
            XCTAssertFalse(model.supportsMask, id)
            XCTAssertEqual(model.maxInputImages, 0, id)
            XCTAssertEqual(model.imageInputParam, "", id)
            XCTAssertNil(model.secondImageParam, id)
            XCTAssertFalse(model.acceptsMultiImages, id)
            XCTAssertFalse(model.acceptsBase64, id)
            XCTAssertFalse(model.acceptsPublicURL, id)
            XCTAssertFalse(model.acceptsBinary, id)
        }
    }

    /// Grok posts once and reads the image from the response; there is no job to poll.
    func testGrokPostsToXAIAndNeverPolls() throws {
        for id in ["grok-imagine-image", "grok-imagine-image-quality"] {
            let model = try XCTUnwrap(Catalog.model(for: id))
            XCTAssertEqual(model.generationEndpoint,
                           "https://api.x.ai/v1/images/generations", id)
            XCTAssertNil(model.pollingEndpoint, id)
            XCTAssertNil(model.typicalWallClock, id)   // image model — Task 13's invariant
            XCTAssertTrue(model.isRegistered, id)
            XCTAssertEqual(model.lifecycle, .current, id)
        }
    }

    /// The catalog is now cross-provider, so `selectable(task:)` returns rows from more than one
    /// provider. Every picker MUST filter by provider; this test is the reminder.
    func testSelectableSpansProviders() {
        let providers = Set(Catalog.selectable(task: .image).flatMap(\.models).map(\.provider))
        XCTAssertTrue(providers.contains(.grok))
        XCTAssertTrue(providers.contains(.aimlapi))
    }

    /// Task 12 suffixed the AI/ML-routed Grok family so the two cannot merge into one group.
    func testTheAIMLRoutedGrokRowIsADifferentFamily() throws {
        let native = try XCTUnwrap(Catalog.model(for: "grok-imagine-image"))
        let viaAIML = try XCTUnwrap(Catalog.model(for: "x-ai/grok-imagine-image"))
        XCTAssertEqual(native.family, "Grok Imagine")
        XCTAssertEqual(viaAIML.family, "Grok Imagine (via AI/ML API)")
        XCTAssertEqual(viaAIML.provider, .aimlapi)
    }
}

// MARK: - Note for the future ParamCatalog migration (design § 8) — recorded, NOT fixed here
//
// The native Grok picker and the AI/ML-routed `grokImagine` descriptor table disagree about the
// same two controls. Nothing in Stage 3 touches either; this is written down so the migration that
// folds Grok's parameters into ParamCatalog starts from a known state rather than rediscovering it.
//
//                | native Grok (app)                        | ParamCatalog.grokImagine
//   aspect ratio | @AppStorage "grokAspectRatio"             | ParamDescriptor .aspectRatio
//                | GenStationApp.swift:155, default "1:1"    | ImageXAI.swift:28-29, default "16:9"
//                | 14 options (ConfigurationSection:449-450) | 8 options (ImageXAI.swift:28)
//                | 1:1 16:9 9:16 4:3 3:4 3:2 2:3 2:1 1:2     | 1:1 3:4 4:3 9:16 16:9 2:3 3:2 auto
//                | 19.5:9 9:19.5 20:9 9:20 auto              |
//                | -> 6 extra: 2:1 1:2 19.5:9 9:19.5         |
//                |             20:9 9:20                     |
//     resolution | @AppStorage "grokResolution", "2k"        | ImageXAI.swift:40-41, "2k" — agree
//                | 1K / 2K (ConfigurationSection:460-463)    | 1k / 2k — agree
//
// The two surfaces drive DIFFERENT ids (`grok-imagine-image` natively vs `x-ai/grok-imagine-image`
// through AI/ML), so this is not necessarily a bug on either side — but the defaults differ, and
// one of the two lists is wrong about what xAI accepts. Neither question is answerable from this
// repository (Stage 2 design § 2).
