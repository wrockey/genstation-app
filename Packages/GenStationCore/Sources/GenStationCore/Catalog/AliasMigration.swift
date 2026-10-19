// The collapse (design § 4.3) left three alias-keyed persisted stores naming spellings that are no
// longer catalog row ids. Two of them — `favoriteAIMLModels` and `recentAIMLModels` — are plain id
// lists in UserDefaults and are canonicalized once on load and written back. This is that transform,
// kept in the package so it is testable; the app owns the one-shot flag and the write-back.
//
// The third store, `history_v2.json`'s `modelUsed`, is deliberately NOT migrated here. It is 147 MB,
// it is a byte-identical golden fixture, and Stage 4 owns that mutation surface. History is
// canonicalized at read time, in `HistoryView.loadSubmission(item:)`.
//
// An id the catalog does not know is kept unchanged, not dropped: advanced mode lets the user pick a
// raw API id that has no catalog row, and a favourites list is user-curated data.

import Foundation

public enum AliasMigration {

    /// Maps every id through the alias index, drops blanks, and dedupes while preserving order
    /// (first occurrence wins). Idempotent, because a canonical id maps to itself.
    public static func canonicalizedUnique(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let canonical = Catalog.canonicalID(for: trimmed) ?? trimmed
            guard seen.insert(canonical).inserted else { continue }
            result.append(canonical)
        }
        return result
    }
}
