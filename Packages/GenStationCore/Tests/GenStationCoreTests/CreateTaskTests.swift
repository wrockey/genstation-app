import XCTest
@testable import GenStationCore

final class CreateTaskTests: XCTestCase {

    /// These two strings are an agent-facing contract: the MCP `list_models` `type`
    /// filter accepts exactly them, and `tools/genstation-mcp` documents them.
    func testRawValuesAreTheFrozenAgentContract() {
        XCTAssertEqual(CreateTask.image.rawValue, "image")
        XCTAssertEqual(CreateTask.video.rawValue, "video")
        XCTAssertEqual(CreateTask.allCases.map(\.rawValue), ["image", "video"])
    }

    func testRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode([CreateTask.video, .image])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["video","image"]"#)
        XCTAssertEqual(try JSONDecoder().decode([CreateTask].self, from: data), [.video, .image])
    }

    /// The MCP layer rejects an unknown `type` with a structured error rather than
    /// defaulting, so the parse must fail rather than fall back.
    func testUnknownRawValueIsRejected() {
        XCTAssertNil(CreateTask(rawValue: "audio"))
        XCTAssertNil(CreateTask(rawValue: "Video"))
        XCTAssertNil(CreateTask(rawValue: ""))
    }

    /// The AIML catalog's per-model flag is a Bool; this is the one conversion.
    func testIsVideoBridge() {
        XCTAssertEqual(CreateTask(isVideo: true), .video)
        XCTAssertEqual(CreateTask(isVideo: false), .image)
        XCTAssertTrue(CreateTask.video.isVideo)
        XCTAssertFalse(CreateTask.image.isVideo)
    }
}
