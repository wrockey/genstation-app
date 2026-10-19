import XCTest
@testable import GenStationCore

/// Guards the rule that a model's posting URL comes from the catalog, never from
/// `AIMLEndpoints.videoEndpoint(modelID:)` synthesis.
///
/// The file keeps its Stage-1 name. It was written when the model set was `ModelRegistry` in the app
/// target and these tests could only reach it by reading Swift source as text; the subject is the
/// same rule, so the history is worth more than the accuracy of the noun.
///
/// Why it exists: Stage 1 introduced `videoEndpoint(modelID:)` and `GenStationApp.swift` began using
/// it to recompute an already-overridden `customAIMLEndpoint` on model switch. Synthesis builds a
/// path from the model id's first component, which is wrong for most registered video models, so
/// those silently posted to a URL that does not exist. `AIMLEndpointsTests` missed it because it
/// only exercises synthetic ids (`kling/v2-master`) that are not in the catalog.
///
/// The first method now enumerates the catalog directly. The second still scans app source, because
/// what it asserts is a property of *how a call site is written*, which no enumeration can see.
final class RegistryEndpointTests: XCTestCase {

    private static var appSourcesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../../GenStation")
            .standardizedFileURL
    }

    private static var aimlVideoModels: [CatalogModel] {
        Catalog.all.filter { $0.provider == .aimlapi && $0.isVideo }
    }

    /// The fact that makes the catalog mandatory: synthesis is *wrong* for most video models.
    /// `luma/ray-2` is the worked example — the catalog posts it to the shared v2 video endpoint,
    /// synthesis invents a per-provider `luma` path that does not exist.
    func testVideoEndpointSynthesisIsNotASubstituteForTheCatalog() throws {
        let video = Self.aimlVideoModels

        // Vacuity guard only. It replaces the old `models.filter(\.isVideo).count == 129`, which was
        // there to prove the *parse* had found everything; there is no parse now, and pinning the
        // exact number would just re-freeze a model set that § 4.4 deliberately changes.
        XCTAssertGreaterThan(video.count, 30, "the catalog resolved \(video.count) AI/ML video models")

        let ray2 = try XCTUnwrap(Catalog.model(for: "luma/ray-2"))
        XCTAssertEqual(ray2.generationEndpoint, AIMLEndpoints.videoGeneration)
        XCTAssertNotEqual(
            AIMLEndpoints.videoEndpoint(modelID: ray2.id).absoluteString,
            AIMLEndpoints.videoGeneration,
            "if synthesis ever agrees for luma/ray-2, this whole file is obsolete")

        let disagreeing = video.filter {
            AIMLEndpoints.videoEndpoint(modelID: $0.id).absoluteString != $0.generationEndpoint
        }
        // This was `XCTAssertEqual(disagreeing.count, 91)`, and it is not re-pinned as any number.
        //
        // 91 was a census of a defect over a population that no longer exists: it counted *alias*
        // spellings, 91 of 129, one row per registry key. This filter runs over canonical rows, of
        // which there are far fewer, so any figure printed here is a different quantity — not a
        // corrected 91.
        //
        // And the consumer it was measuring is gone. It existed to size the risk of
        // `JobQueue.canRetry`/`retry(_:)` falling back to a synthesized polling endpoint; Stage 3
        // Task 16 deleted that fallback, so no production code substitutes synthesis for the catalog
        // any more. What survives is the only part that was ever a contract — the two are not
        // interchangeable, so no future call site may substitute one for the other.
        XCTAssertFalse(
            disagreeing.isEmpty,
            "synthesis now agrees with the catalog for every video model — if that is really true, "
            + "delete this file; if it is not, the catalog's generationEndpoint data has been "
            + "flattened onto the synthesis rule")
    }

    /// The regression itself. `GenStationApp`'s model-switch handler resets an already-overridden
    /// `customAIMLEndpoint`, and that reset must land on the URL a non-overridden generation would
    /// have posted to — the catalog's `generationEndpoint`.
    ///
    /// This scans app source deliberately. The handler lives in `SettingsState`, whose `imageSlots`
    /// subscription was never actually built until the Stage 3 bug-fix wave, so this assertion
    /// guarded dead code for its whole life and guards live code now.
    func testModelSwitchResolvesTheVideoEndpointThroughTheCatalog() throws {
        let source = try String(
            contentsOf: Self.appSourcesURL.appendingPathComponent("App/GenStationApp.swift"),
            encoding: .utf8)

        XCTAssertTrue(
            source.contains(
                "customAIMLEndpoint = Catalog.model(for: selectedAIMLModel)?.generationEndpoint"),
            "the model-switch handler must take the endpoint from the catalog")
        XCTAssertFalse(
            source.contains("customAIMLEndpoint = AIMLEndpoints.videoEndpoint("),
            "synthesis must not be assigned directly — it is wrong for most video models; "
            + "it may only appear as the ?? fallback for an id the catalog does not know")
    }
}
