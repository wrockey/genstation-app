import XCTest
@testable import GenStationCore

final class SelectionStateTests: XCTestCase {

    func testDefaultsMatchTheAppsHistoricalLaunchState() {
        // Before persistence existed the app always opened on Gemini, image task.
        let defaults = SelectionState.defaults
        XCTAssertEqual(defaults.provider, .gemini)
        XCTAssertEqual(defaults.task, .image)
        XCTAssertTrue(defaults.modelByProvider.isEmpty)
        XCTAssertEqual(defaults.schemaVersion, SelectionState.currentSchemaVersion)
    }

    func testRoundTripsThroughItsOwnCodec() throws {
        let state = SelectionState.defaults
            .settingModel("google/veo-3.1", for: .aimlapi)
            .settingModel("gemini-3-pro-image-preview", for: .gemini)
        var saved = state
        saved.provider = .aimlapi
        saved.task = .video

        let restored = SelectionState.decode(try saved.encoded())
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(restored?.model(for: .aimlapi), "google/veo-3.1")
        XCTAssertEqual(restored?.model(for: .gemini), "gemini-3-pro-image-preview")
        XCTAssertNil(restored?.model(for: .grok))
    }

    /// Settings are cheap to lose and expensive to get wrong, so an envelope this build
    /// does not understand is rejected whole rather than partially applied.
    func testAFutureSchemaVersionIsRejected() throws {
        let json = #"{"schemaVersion":99,"provider":"gemini","task":"image","modelByProvider":{}}"#
        XCTAssertNil(SelectionState.decode(Data(json.utf8)))
    }

    func testCorruptOrAbsentDataDecodesToNilNotACrash() {
        XCTAssertNil(SelectionState.decode(nil))
        XCTAssertNil(SelectionState.decode(Data()))
        XCTAssertNil(SelectionState.decode(Data("not json".utf8)))
        XCTAssertNil(SelectionState.decode(Data("[]".utf8)))
    }

    /// A provider or task raw this build does not know invalidates the envelope — unlike
    /// history, there is nothing here worth salvaging record by record.
    func testUnknownProviderOrTaskRawIsRejected() {
        let badProvider = #"{"schemaVersion":1,"provider":"midjourney","task":"image","modelByProvider":{}}"#
        let badTask = #"{"schemaVersion":1,"provider":"gemini","task":"audio","modelByProvider":{}}"#
        XCTAssertNil(SelectionState.decode(Data(badProvider.utf8)))
        XCTAssertNil(SelectionState.decode(Data(badTask.utf8)))
    }

    func testSettingAModelReplacesOnlyThatProvidersEntry() {
        let state = SelectionState.defaults
            .settingModel("a", for: .grok)
            .settingModel("b", for: .gemini)
            .settingModel("c", for: .grok)
        XCTAssertEqual(state.model(for: .grok), "c")
        XCTAssertEqual(state.model(for: .gemini), "b")
        XCTAssertEqual(state.modelByProvider.count, 2)
    }

    /// An empty id must not be stored — `selectedAIMLModel` starts as "" and would
    /// otherwise persist a selection that means "nothing selected".
    func testEmptyModelIdIsNotStored() {
        let state = SelectionState.defaults.settingModel("", for: .aimlapi)
        XCTAssertNil(state.model(for: .aimlapi))
        XCTAssertTrue(state.modelByProvider.isEmpty)
    }

    /// Keys are provider raw values, so the persisted blob stays readable and stable.
    func testModelKeysAreProviderRawValues() throws {
        let data = try SelectionState.defaults.settingModel("x", for: .comfyUI).encoded()
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains(#""comfyUI":"x""#) || json.contains(#""comfyUI" : "x""#), json)
    }
}
