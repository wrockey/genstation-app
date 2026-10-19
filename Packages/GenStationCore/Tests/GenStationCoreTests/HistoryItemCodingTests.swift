import XCTest
@testable import GenStationCore

final class HistoryItemCodingTests: XCTestCase {

    /// A realistic `history_v2.json`: one finished image from a batch, one folder holding a
    /// failed video job with the full AIML replay fields, one bare minimum record, and one
    /// ComfyUI-derived child carrying upscale lineage. Keys are sorted and the formatting is
    /// pretty-printed, matching what `saveHistory()` writes.
    ///
    /// Between them these records exercise **every** field on `HistoryItem`, which is the
    /// only reason `testReEncodingTheFixtureIsByteIdentical` can catch a `CodingKeys` or
    /// optionality regression — a field the fixture omits is a field that test cannot guard.
    static let fixture = """
    [
      {
        "content" : {
          "agentGenerated" : false,
          "batchId" : "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "date" : 774316800,
          "id" : "11111111-1111-1111-1111-111111111111",
          "imagePath" : "\\/tmp\\/out\\/a.png",
          "indexInBatch" : 0,
          "mode" : "gemini",
          "modelUsed" : "gemini-3-pro-image-preview",
          "prompt" : "a red bicycle",
          "responseText" : "",
          "task" : "image",
          "totalInBatch" : 2
        },
        "type" : "item"
      },
      {
        "content" : {
          "children" : [
            {
              "content" : {
                "costUSD" : 0.4,
                "customAIMLEndpoint" : "https:\\/\\/api.aimlapi.com\\/v2\\/video\\/generations",
                "customAIMLPayload" : "{\\"model\\":\\"veo-3.1\\"}",
                "date" : 774403200,
                "id" : "22222222-2222-2222-2222-222222222222",
                "jobId" : "job-abc",
                "mode" : "aimlapi",
                "modelUsed" : "google\\/veo-3.1",
                "pollingEndpoint" : "https:\\/\\/api.aimlapi.com\\/v2\\/video\\/generations?generation_id=",
                "prompt" : "a drone shot",
                "responseText" : "Video failed (status: failed)",
                "status" : "failed",
                "task" : "video",
                "videoHasAudio" : true,
                "videoUrl" : "https:\\/\\/cdn.example.com\\/v.mp4"
              },
              "type" : "item"
            }
          ],
          "id" : "33333333-3333-3333-3333-333333333333",
          "name" : "Drone tests"
        },
        "type" : "folder"
      },
      {
        "content" : {
          "date" : 774489600,
          "id" : "44444444-4444-4444-4444-444444444444",
          "prompt" : "minimal record",
          "responseText" : ""
        },
        "type" : "item"
      },
      {
        "content" : {
          "date" : 774576000,
          "id" : "55555555-5555-5555-5555-555555555555",
          "imagePath" : "\\/tmp\\/out\\/a-4x.png",
          "mode" : "comfyUI",
          "parentItemId" : "11111111-1111-1111-1111-111111111111",
          "prompt" : "a red bicycle",
          "responseText" : "",
          "task" : "image",
          "workflowName" : "upscale-4x.json"
        },
        "type" : "item"
      }
    ]
    """

    private func decodeFixture() throws -> [HistoryEntry] {
        try JSONDecoder().decode([HistoryEntry].self, from: Data(Self.fixture.utf8))
    }

    func testDecodesItemsAndFolders() throws {
        let entries = try decodeFixture()
        XCTAssertEqual(entries.count, 4)
        XCTAssertTrue(entries[0].isItem)
        XCTAssertTrue(entries[1].isFolder)
        XCTAssertEqual(entries[1].asFolder?.name, "Drone tests")
        XCTAssertEqual(entries[1].asFolder?.children.count, 1)
    }

    /// Batch bookkeeping and upscale lineage are the fields most likely to be quietly
    /// dropped by a `CodingKeys` edit, and the ones a user would miss most.
    func testDecodesBatchBookkeepingAndUpscaleLineage() throws {
        let entries = try decodeFixture()
        let batched = try XCTUnwrap(entries[0].asItem)
        XCTAssertEqual(batched.batchId, UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        XCTAssertEqual(batched.indexInBatch, 0)
        XCTAssertEqual(batched.totalInBatch, 2)
        XCTAssertEqual(batched.task, .image)

        let derived = try XCTUnwrap(entries[3].asItem)
        XCTAssertEqual(derived.mode, .comfyUI)
        XCTAssertEqual(derived.workflowName, "upscale-4x.json")
        XCTAssertEqual(derived.parentItemId, batched.id)
    }

    func testDecodesEveryFieldOfTheVideoRecord() throws {
        let entries = try decodeFixture()
        let video = try XCTUnwrap(entries[1].asFolder?.children.first?.asItem)
        XCTAssertEqual(video.mode, .aimlapi)
        XCTAssertEqual(video.status, .failed)
        XCTAssertEqual(video.jobId, "job-abc")
        XCTAssertEqual(video.costUSD, 0.4)
        XCTAssertEqual(video.modelUsed, "google/veo-3.1")
        XCTAssertEqual(video.videoUrl, "https://cdn.example.com/v.mp4")
        XCTAssertEqual(video.responseText, "Video failed (status: failed)")
        XCTAssertEqual(video.task, .video)
        XCTAssertEqual(video.videoHasAudio, true)
        XCTAssertEqual(video.pollingEndpoint,
                       "https://api.aimlapi.com/v2/video/generations?generation_id=")
    }

    /// Absent optionals must stay absent, not become nulls — `encodeIfPresent` throughout.
    func testMinimalRecordKeepsItsAbsentFieldsAbsent() throws {
        let entries = try decodeFixture()
        let minimal = try XCTUnwrap(entries[2].asItem)
        XCTAssertNil(minimal.mode)
        XCTAssertNil(minimal.status)
        XCTAssertNil(minimal.imagePath)
        XCTAssertNil(minimal.agentGenerated)
        XCTAssertNil(minimal.task)
        XCTAssertNil(minimal.batchId)
        XCTAssertNil(minimal.indexInBatch)
        XCTAssertNil(minimal.totalInBatch)
        XCTAssertNil(minimal.workflowName)
        XCTAssertNil(minimal.videoHasAudio)
        XCTAssertNil(minimal.parentItemId)
    }

    /// The file-format guarantee: what we write is what was there.
    func testReEncodingTheFixtureIsByteIdentical() throws {
        let entries = try decodeFixture()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reEncoded = try encoder.encode(entries)
        let produced = try XCTUnwrap(String(data: reEncoded, encoding: .utf8))
        XCTAssertEqual(produced, Self.fixture)
    }

    /// The typed field must still land on disk as the same string.
    func testTypedStatusEncodesAsTheLegacyString() throws {
        let item = HistoryItem(prompt: "p", date: Date(timeIntervalSince1970: 774316800),
                              status: .generating)
        let data = try HistoryFile.encode([.item(item)])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains(#""status" : "generating""#), json)
    }

    /// A status string this build does not know must not throw and must not be lost.
    func testUnknownStatusStringSurvivesADecodeEncodeRoundTrip() throws {
        let json = """
        [{"type":"item","content":{"id":"11111111-1111-1111-1111-111111111111","prompt":"p","responseText":"","date":774316800,"status":"in_queue"}}]
        """
        let result = try HistoryFile.decode(Data(json.utf8))
        XCTAssertEqual(result.droppedRecordCount, 0)
        XCTAssertEqual(result.entries[0].asItem?.status, .unknown("in_queue"))
        let reEncoded = try XCTUnwrap(String(data: try HistoryFile.encode(result.entries), encoding: .utf8))
        XCTAssertTrue(reEncoded.contains(#""status" : "in_queue""#), reEncoded)
    }

    func testEntryHelpersWalkNestedFolders() throws {
        let entries = try decodeFixture()
        XCTAssertEqual(entries.flatMap(\.allItems).count, 4)
        XCTAssertEqual(entries[1].imageCount, 1)
        var ids = Set<UUID>()
        entries.forEach { $0.collectAllIDs(into: &ids) }
        XCTAssertEqual(ids.count, 5)  // 4 items + 1 folder
    }

    /// `task` is additive: every record already on disk lacks the key, and must round-trip
    /// without acquiring one — otherwise an older build could no longer read new files.
    func testARecordWithNoTaskKeyRoundTripsWithoutOne() throws {
        let json = """
        [{"type":"item","content":{"id":"11111111-1111-1111-1111-111111111111","prompt":"p","responseText":"","date":774316800}}]
        """
        let result = try HistoryFile.decode(Data(json.utf8))
        XCTAssertEqual(result.droppedRecordCount, 0)
        XCTAssertNil(result.entries[0].asItem?.task)
        let reEncoded = try XCTUnwrap(String(data: try HistoryFile.encode(result.entries), encoding: .utf8))
        XCTAssertFalse(reEncoded.contains("task"), reEncoded)
    }

    /// A `task` value this build does not know (a later `.threeD`, say) must be tolerated
    /// like an unknown `mode` — dropped from the record, never throwing it away.
    func testAnUnknownTaskStringKeepsTheRecord() throws {
        let json = """
        [{"type":"item","content":{"id":"11111111-1111-1111-1111-111111111111","prompt":"p","responseText":"","date":774316800,"task":"threeD"}}]
        """
        let result = try HistoryFile.decode(Data(json.utf8))
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.droppedRecordCount, 0)
        XCTAssertNil(result.entries[0].asItem?.task)
    }
}
