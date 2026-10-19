import XCTest
@testable import GenStationCore

final class HistoryFileTests: XCTestCase {

    /// Two good records with one structurally broken record between them: `date` is a
    /// string where a Double is required, so this element cannot decode at all.
    private static let oneCorruptRecord = """
    [
      {"type":"item","content":{"id":"11111111-1111-1111-1111-111111111111","prompt":"good one","responseText":"","date":774316800}},
      {"type":"item","content":{"id":"22222222-2222-2222-2222-222222222222","prompt":"broken","responseText":"","date":"not-a-date"}},
      {"type":"item","content":{"id":"33333333-3333-3333-3333-333333333333","prompt":"good two","responseText":"","date":774489600}}
    ]
    """

    /// One bad top-level record, one bad child, one bad grandchild — three drops spread
    /// across nesting levels, so a leaked `DroppedRecordCounter` would show up as an
    /// inflated count on a second decode rather than being masked by a flat top-level array.
    private static let nestedWithGrandchild = """
    [
      {"type":"item","content":{"id":"11111111-1111-1111-1111-111111111111","prompt":"top level bad","responseText":"","date":"nope"}},
      {"type":"folder","content":{"id":"33333333-3333-3333-3333-333333333333","name":"Outer","children":[
        {"type":"item","content":{"prompt":"bad child"}},
        {"type":"folder","content":{"id":"44444444-4444-4444-4444-444444444444","name":"Inner","children":[
          {"type":"item","content":{"id":"22222222-2222-2222-2222-222222222222","prompt":"good","responseText":"","date":774316800}},
          {"type":"item","content":{"prompt":"bad grandchild"}}
        ]}}
      ]}}
    ]
    """

    func testACorruptRecordIsDroppedAndTheRestSurvive() throws {
        let result = try HistoryFile.decode(Data(Self.oneCorruptRecord.utf8))
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.droppedRecordCount, 1)
        XCTAssertEqual(result.entries.compactMap(\.asItem).map(\.prompt), ["good one", "good two"])
    }

    /// The bug this task exists to kill: before it, this input produced an empty array
    /// that was then written back over the user's file.
    func testAnUnknownProviderRawKeepsTheRecord() throws {
        let json = """
        [{"type":"item","content":{"id":"11111111-1111-1111-1111-111111111111","prompt":"future","responseText":"","date":774316800,"mode":"midjourney"}}]
        """
        let result = try HistoryFile.decode(Data(json.utf8))
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.droppedRecordCount, 0)
        XCTAssertNil(result.entries[0].asItem?.mode)
        XCTAssertEqual(result.entries[0].asItem?.prompt, "future")
    }

    func testAnUnknownEntryTypeTagDropsOnlyThatRecord() throws {
        let json = """
        [
          {"type":"item","content":{"id":"11111111-1111-1111-1111-111111111111","prompt":"keep","responseText":"","date":774316800}},
          {"type":"playlist","content":{}}
        ]
        """
        let result = try HistoryFile.decode(Data(json.utf8))
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.droppedRecordCount, 1)
    }

    func testACorruptChildDropsOnlyThatChildNotTheFolder() throws {
        let json = """
        [{"type":"folder","content":{"id":"33333333-3333-3333-3333-333333333333","name":"Keep me","children":[
          {"type":"item","content":{"id":"11111111-1111-1111-1111-111111111111","prompt":"good","responseText":"","date":774316800}},
          {"type":"item","content":{"prompt":"missing id and date"}}
        ]}}]
        """
        let result = try HistoryFile.decode(Data(json.utf8))
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].asFolder?.name, "Keep me")
        XCTAssertEqual(result.entries[0].asFolder?.children.count, 1)
        XCTAssertEqual(result.droppedRecordCount, 1)
    }

    /// Children are dropped inside `Folder.init(from:)`, which has no return channel — so
    /// without the userInfo counter a corrupt grandchild vanished with no count and no log.
    func testACorruptGrandchildIsCounted() throws {
        let result = try HistoryFile.decode(Data(Self.nestedWithGrandchild.utf8))
        XCTAssertEqual(result.entries.count, 1)
        // One top-level, one child, one grandchild — every level reaches the caller.
        XCTAssertEqual(result.droppedRecordCount, 3)
        let inner = try XCTUnwrap(result.entries[0].asFolder?.children.first?.asFolder)
        XCTAssertEqual(inner.children.count, 1)
    }

    /// The counter is per-decode state, not per-process: two calls must not accumulate.
    /// Uses the nested/grandchild fixture (not `oneCorruptRecord`, which has no folders) so
    /// a leaked `DroppedRecordCounter` — one not reset fresh per `HistoryFile.decode` call —
    /// would surface as an inflated count on the second decode instead of passing by luck.
    func testTheDropCountDoesNotLeakBetweenDecodes() throws {
        let nested = Data(Self.nestedWithGrandchild.utf8)
        XCTAssertEqual(try HistoryFile.decode(nested).droppedRecordCount, 3)
        XCTAssertEqual(try HistoryFile.decode(nested).droppedRecordCount, 3)
    }

    /// A file that is not an array at all must throw, so the caller can leave the
    /// existing in-memory history alone instead of replacing it with nothing.
    func testNonArrayInputThrowsRatherThanReturningEmpty() {
        XCTAssertThrowsError(try HistoryFile.decode(Data(#"{"history":[]}"#.utf8)))
        XCTAssertThrowsError(try HistoryFile.decode(Data("not json at all".utf8)))
    }

    func testAnEmptyArrayIsAValidEmptyHistory() throws {
        let result = try HistoryFile.decode(Data("[]".utf8))
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.droppedRecordCount, 0)
    }

    /// HistoryFile.encode must produce exactly what saveHistory() produced before, so the
    /// existing fixture round-trips through the new entry point too.
    func testEncodeMatchesTheLegacySaveFormat() throws {
        let entries = try HistoryFile.decode(Data(HistoryItemCodingTests.fixture.utf8)).entries
        let data = try HistoryFile.encode(entries)
        XCTAssertEqual(String(data: data, encoding: .utf8), HistoryItemCodingTests.fixture)
    }

    func testLossyArrayCountsFailuresWithoutAbortingTheArray() throws {
        let json = Data(#"[1,"two",3,null,5]"#.utf8)
        let decoded = try JSONDecoder().decode(HistoryFile.LossyArray<Int>.self, from: json)
        XCTAssertEqual(decoded.elements, [1, 3, 5])
        XCTAssertEqual(decoded.failureCount, 2)
    }
}
