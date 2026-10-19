// The bridge from a catalog row to its parameter table. `EnhancedModel.paramDescriptors` and
// `.paramContext(hasInputImages:)` lived on the registry wrapper; they belong to the Params layer,
// which already knows about model ids, rather than to `CatalogModel`, which must stay readable
// without ParamCatalog.

import XCTest
@testable import GenStationCore

final class CatalogParamBridgeTests: XCTestCase {

    /// `openai/gpt-image-1-mini` and `gpt-image-1-mini` share one `reg()` group and one table
    /// (`ParamCatalog.swift:210`, `:215` — both point at `openAIGPTImage1Extended`). This asserts
    /// against `model.id` rather than the literal, so it holds whichever of the two spellings the
    /// collapse in Task 11 chose as canonical.
    func testDescriptorsForARegisteredRowMatchTheIdLookup() throws {
        let model = try XCTUnwrap(Catalog.model(for: "openai/gpt-image-1-mini"))
        let byId = try XCTUnwrap(ParamCatalog.descriptors(forModelId: model.id))
        XCTAssertEqual(ParamCatalog.descriptors(for: model).map(\.wireKey), byId.map(\.wireKey))
        XCTAssertFalse(byId.isEmpty, "gpt-image-1-mini must have a table, or this test proves nothing")
    }

    /// What `EnhancedModel.paramDescriptors` documented: an unregistered id has no table, and
    /// encoding or decoding against `[]` is a no-op, so the fallback is exactly equivalent rather
    /// than merely similar. `alibaba/qwen-image-3` is served by the live `/models` fixture
    /// (`Fixtures/aiml-models-response.json:633`) and is in no `reg()` group.
    func testDescriptorsForASynthesizedRowAreEmpty() {
        let model = Catalog.synthesized(for: "alibaba/qwen-image-3")
        XCTAssertTrue(ParamCatalog.descriptors(for: model).isEmpty)
    }

    /// Fix C (Stage 3 whole-branch triage, item C). Task 16 made `AdvancedAIMLSettingsView`'s
    /// `else { Text("No advanced parameters for this model") }` branch reachable
    /// (`GenStation/Create/AdvancedAIMLSettingsView.swift:206-212`) by switching that call site from
    /// `enhancedModelFor(id:)` (synthesized unconditionally, so the branch was dead) to
    /// `Catalog.model(for:)` (an honest `nil` for an unregistered id). `ConfigurationSection.swift`'s
    /// `videoParamsSummaryParts` (`:589`) is reachable for the same reason. The Task 16 report proved
    /// this with a throwaway test — never committed — so nothing guarded either branch if
    /// `alibaba/qwen-image-3` ever gained a `reg()` group. This is the permanent replacement.
    ///
    /// If this fails because `Catalog.model(for:)` is no longer nil for this id, the precondition
    /// both call sites depend on no longer holds: find a different id the live fixture serves
    /// (`Fixtures/aiml-models-response.json`) with no `reg()` group in
    /// `Packages/GenStationCore/Sources/GenStationCore/Catalog/Models/AIMLRegisteredModels.swift`
    /// and re-pin against that one instead of quietly deleting the test.
    func testUnregisteredLiveIdIsHonestNilForModelForButResolvesAnyway() {
        XCTAssertNil(Catalog.model(for: "alibaba/qwen-image-3"),
                     "AdvancedAIMLSettingsView's \"No advanced parameters\" branch and "
                     + "ConfigurationSection.videoParamsSummaryParts's empty-array branch are only "
                     + "reachable while this is nil")
        XCTAssertNotNil(Catalog.resolve("alibaba/qwen-image-3"),
                        "resolve() must never return nil, including for an unregistered id — "
                        + "sites 5/6/7/8 in the Task 16 report depend on that")
    }

    /// `isI2I` must be the static catalog flag — that is what `Condition.isTextToVideo` evaluates
    /// against, under frozen legacy semantics — while `hasInputImages` carries the true mode.
    func testContextCarriesTheStaticFlagAndTheTrueMode() throws {
        let model = try XCTUnwrap(Catalog.model(for: "openai/gpt-image-1-mini"))
        let context = ParamCatalog.context(for: model, hasInputImages: true)
        XCTAssertEqual(context.modelId, model.id)
        XCTAssertEqual(context.isI2I, model.isI2I)
        XCTAssertTrue(context.hasInputImages)
    }
}
