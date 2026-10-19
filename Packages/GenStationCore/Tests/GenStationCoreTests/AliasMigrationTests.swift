// The collapse (Task 11) left three alias-keyed persisted stores pointing at spellings that are no
// longer catalog row ids. This is the pure half of the fix: the list transform favorites and recents
// run once on load. The app-layer wiring has no test harness and is verified by the compile gates
// plus the live-test checklist.
//
// `ParamCatalog` is deliberately NOT part of this problem: it keeps a key per alias
// (`ParamCatalog.swift:9-11`), so every spelling still resolves a descriptor table. What the collapse
// changed is which spellings are *catalog row ids*, and that is what these three stores name.

import XCTest
@testable import GenStationCore

final class AliasMigrationTests: XCTestCase {

    func testCanonicalizesAnAliasSpellingToItsCanonicalId() throws {
        // Pick a real alias out of the recorded grouping rather than naming one, so the test cannot
        // go vacuous if Task 11's canonical-spelling rule picks the other member of the pair.
        let group = try XCTUnwrap(AliasGroups.groups.first { $0.count > 1 })
        let canonical = try XCTUnwrap(Catalog.canonicalID(for: group[0]))
        let alias = try XCTUnwrap(group.first { $0 != canonical })
        XCTAssertEqual(AliasMigration.canonicalizedUnique([alias]), [canonical])
    }

    func testDedupesWhenTwoSpellingsCollapseOntoOneCanonical() throws {
        let group = try XCTUnwrap(AliasGroups.groups.first { $0.count > 1 })
        let result = AliasMigration.canonicalizedUnique(group)
        XCTAssertEqual(result.count, 1, "\(group) should dedupe to one id, got \(result)")
        XCTAssertEqual(result, [try XCTUnwrap(Catalog.canonicalID(for: group[0]))])
    }

    func testPreservesOrderAndKeepsTheFirstOccurrence() throws {
        let a = try XCTUnwrap(AliasGroups.groups.first { $0.count > 1 })
        let b = try XCTUnwrap(AliasGroups.groups.last { $0.count > 1 && $0[0] != a[0] })
        let result = AliasMigration.canonicalizedUnique([a[1], b[0], a[0]])
        XCTAssertEqual(result, [try XCTUnwrap(Catalog.canonicalID(for: a[0])),
                                try XCTUnwrap(Catalog.canonicalID(for: b[0]))],
                       "the first occurrence wins and the order is preserved")
    }

    func testKeepsAnUnknownIdUnchangedRatherThanDroppingIt() {
        // Advanced mode lets the user pick a raw API id the catalog has never heard of. Dropping it
        // would silently empty a favourites list the user curated.
        XCTAssertNil(Catalog.canonicalID(for: "alibaba/qwen-image-3"),
                     "this id must stay unregistered, or the test proves nothing")
        XCTAssertEqual(AliasMigration.canonicalizedUnique(["alibaba/qwen-image-3"]),
                       ["alibaba/qwen-image-3"])
    }

    func testDropsEmptyStrings() {
        XCTAssertEqual(AliasMigration.canonicalizedUnique(["", "  "]), [])
    }

    /// Idempotence is what makes it safe to run the migration on a store that has already been
    /// migrated — the one-shot flag can be lost (a restored plist, a new machine).
    func testIsIdempotent() {
        let input = AliasGroups.groups.flatMap { $0 }
        let once = AliasMigration.canonicalizedUnique(input)
        XCTAssertEqual(AliasMigration.canonicalizedUnique(once), once)
        XCTAssertEqual(once.count, AliasGroups.groups.count,
                       "every recorded spelling must collapse onto exactly one canonical per group")
    }
}
