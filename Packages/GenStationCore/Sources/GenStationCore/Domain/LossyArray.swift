import Foundation

extension HistoryFile {

    /// Decodes a JSON array element by element, skipping elements that fail instead of
    /// failing the whole array.
    ///
    /// The standard `[T].self` decode is all-or-nothing, which is how one bad record in
    /// `history_v2.json` could take the user's entire history with it. The wrapper below is
    /// what makes per-element recovery possible: `Lossy` never throws, so the unkeyed
    /// container always advances and decoding continues past a bad element.
    public struct LossyArray<Element: Decodable>: Decodable {
        public let elements: [Element]
        /// How many elements were skipped. Callers log this — a silent drop is how data loss
        /// goes unnoticed.
        public let failureCount: Int

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var elements: [Element] = []
            var failureCount = 0
            while !container.isAtEnd {
                let wrapped = try container.decode(Lossy<Element>.self)
                if let value = wrapped.value {
                    elements.append(value)
                } else {
                    failureCount += 1
                }
            }
            self.elements = elements
            self.failureCount = failureCount
        }

        /// Absorbs a single element's decoding failure. Because this initializer cannot
        /// throw, the enclosing unkeyed container's index advances even for a bad element.
        private struct Lossy<Wrapped: Decodable>: Decodable {
            let value: Wrapped?

            init(from decoder: Decoder) throws {
                value = try? Wrapped(from: decoder)
            }
        }
    }
}

/// Somewhere for nested arrays to report their drops.
///
/// `LossyArray` hands its `failureCount` back by return value, which is enough for the
/// file's outermost array but not for the arrays inside folders: those are decoded deep
/// inside `Folder.init(from:)`, which has no channel back to the caller. A reference box
/// carried on `Decoder.userInfo` gives them one, so a corrupt grandchild is counted like
/// any other dropped record instead of vanishing with no count and no log.
///
/// Deliberately not `Sendable`: it lives for exactly one synchronous decode.
final class DroppedRecordCounter {
    private(set) var count = 0

    func add(_ additional: Int) { count += additional }
}

extension CodingUserInfoKey {
    /// Where `HistoryFile.decode` parks its `DroppedRecordCounter`. Absent for any other
    /// decoder, which is why the nested reporting is a no-op outside that entry point.
    static let droppedRecordCounter = CodingUserInfoKey(rawValue: "art.genstation.droppedRecordCounter")!
}
