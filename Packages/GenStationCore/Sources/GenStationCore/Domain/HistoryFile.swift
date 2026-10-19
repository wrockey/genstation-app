import Foundation

/// The one place `history_v2.json` is encoded and decoded.
///
/// Decoding is deliberately lenient at the record level and strict at the file level: a
/// single unparseable record is dropped and reported, but a file that is not a JSON array
/// throws, so the caller can leave the in-memory history untouched rather than replacing it
/// with nothing and saving that over the file.
public enum HistoryFile {

    public struct LoadResult: Sendable {
        public let entries: [HistoryEntry]
        /// Records that could not be decoded and were skipped. Non-zero means the file on
        /// disk contains something this build cannot read — log it.
        public let droppedRecordCount: Int

        public init(entries: [HistoryEntry], droppedRecordCount: Int) {
            self.entries = entries
            self.droppedRecordCount = droppedRecordCount
        }
    }

    public static func decode(_ data: Data) throws -> LoadResult {
        let decoder = JSONDecoder()
        let nested = DroppedRecordCounter()
        decoder.userInfo[.droppedRecordCounter] = nested
        let lossy = try decoder.decode(LossyArray<HistoryEntry>.self, from: data)
        return LoadResult(entries: lossy.elements,
                          droppedRecordCount: lossy.failureCount + nested.count)
    }

    /// Pretty-printed with sorted keys, matching what the app has always written — so a
    /// save after this change produces a minimal diff against the previous file.
    public static func encode(_ entries: [HistoryEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }
}
