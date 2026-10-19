// Pins the captured `/models` response: its size, its duplicate count, its entry shape, and that the
// extended decode keeps every field it claims to keep.
//
// These numbers are measurements taken from the file committed at `b16f840`, not conventions. Task 22
// removes ids by subtraction and needs a baseline that was observed rather than remembered.

import XCTest
@testable import GenStationCore

final class AIMLModelsFixtureTests: XCTestCase {

    private static let expectedEntryCount = 902
    private static let expectedUniqueIDCount = 760
    private static let expectedSpellingCount = 1416

    /// The five keys every entry carries — all five at 902/902.
    private static let observedEntryKeys: Set<String> = ["aliases", "id", "info", "tags", "type"]

    /// The eleven keys the `info` blocks carry between them. Seven are modelled on
    /// `AIMLEndpoints.ModelEntry.Info`; `contextLength`, `cutoffAt`, `outputMax` and `url` are
    /// deliberately not, and are recorded here so they are documented rather than invisible.
    private static let observedInfoKeys: Set<String> = [
        "contextLength", "cutoffAt", "description", "developer", "docsJson", "docsUrl",
        "isHottest", "name", "outputMax", "releasedAt", "url",
    ]

    func testFixtureDecodes() throws {
        let response = try AIMLModelsFixture.response()
        XCTAssertEqual(response.data.count, Self.expectedEntryCount)
        XCTAssertFalse(response.data.contains { $0.id.isEmpty },
                       "an entry with an empty id would poison every lookup built on this fixture")
    }

    /// The duplicate baseline. 902 entries over 760 unique ids: the same model served on several
    /// endpoint families appears once per family. This is the duplicate-`ForEach`-identity bug's
    /// root cause, measured.
    func testFixtureRecordsItsDuplicateCount() throws {
        let ids = try AIMLModelsFixture.response().data.map { $0.id.lowercased() }
        XCTAssertEqual(ids.count, Self.expectedEntryCount)
        XCTAssertEqual(Set(ids).count, Self.expectedUniqueIDCount)
        XCTAssertEqual(try AIMLModelsFixture.servedIDs().count, Self.expectedUniqueIDCount)
        XCTAssertEqual(try AIMLModelsFixture.servedIDsAndAliases().count, Self.expectedSpellingCount)

        var seen: Set<String> = []
        var duplicates: [String] = []
        for id in ids where !seen.insert(id).inserted { duplicates.append(id) }
        XCTAssertEqual(
            duplicates.count,
            Self.expectedEntryCount - Self.expectedUniqueIDCount,
            "duplicated ids (first 20): \(Set(duplicates).sorted().prefix(20))")
    }

    /// The union of top-level keys over every entry, and the count of entries carrying each. All
    /// five are total. Anything the wire grows that this type does not model fails here rather than
    /// vanishing the way `type`, `tags` and `info` did.
    func testFixtureEntryKeysAreWhatWasObserved() throws {
        var counts: [String: Int] = [:]
        for entry in try AIMLModelsFixture.rawEntries() {
            for key in entry.keys { counts[key, default: 0] += 1 }
        }
        XCTAssertEqual(
            Set(counts.keys), Self.observedEntryKeys,
            "the /models entry shape moved. Extend AIMLEndpoints.ModelEntry or update this set "
            + "deliberately — do not just paste the new set in.")
        for key in Self.observedEntryKeys {
            XCTAssertEqual(counts[key], Self.expectedEntryCount,
                           "`\(key)` is no longer carried by every entry "
                           + "(\(counts[key] ?? 0)/\(Self.expectedEntryCount))")
        }
    }

    /// The `info` sub-shape, with the coverage of each key. The two that matter downstream are
    /// `releasedAt` at 894/902 — spec § 3.8's ordering needs a fallback for the other 8 — and
    /// `isHottest` at 57/902, which is the Recommended group.
    func testTheInfoKeysAreWhatWasObserved() throws {
        var counts: [String: Int] = [:]
        for entry in try AIMLModelsFixture.rawEntries() {
            guard let info = entry["info"] as? [String: Any] else {
                return XCTFail("entry \(entry["id"] ?? "?") has no info block")
            }
            for key in info.keys { counts[key, default: 0] += 1 }
        }
        XCTAssertEqual(Set(counts.keys), Self.observedInfoKeys,
                       "the /models info shape moved: \(counts.sorted { $0.key < $1.key })")
        XCTAssertEqual(counts["name"], Self.expectedEntryCount)
        XCTAssertEqual(counts["developer"], Self.expectedEntryCount)
        XCTAssertEqual(counts["docsUrl"], Self.expectedEntryCount)
        XCTAssertEqual(counts["docsJson"], Self.expectedEntryCount)
        XCTAssertEqual(counts["releasedAt"], 894, "8 entries lack releasedAt; ordering needs a fallback")
        XCTAssertEqual(counts["description"], 770)
        XCTAssertEqual(counts["isHottest"], 57, "the vendor's own Recommended set")
    }

    /// Every field the extended `ModelEntry` declares round-trips from the raw JSON. Compared
    /// against `JSONSerialization`, not against another decode, so a silently-dropped field fails
    /// here. This is the assertion that would have caught `type` being thrown away for a year.
    func testDecodeIsLosslessForTheFieldsWeKeep() throws {
        let raw = try AIMLModelsFixture.rawEntries()
        let decoded = try AIMLModelsFixture.response().data
        XCTAssertEqual(raw.count, decoded.count)

        for (index, rawEntry) in raw.enumerated() {
            let model = decoded[index]
            XCTAssertEqual(rawEntry["id"] as? String, model.id, "id mismatch at index \(index)")
            XCTAssertEqual(rawEntry["aliases"] as? [String], model.aliases, "aliases: \(model.id)")
            XCTAssertEqual(rawEntry["type"] as? String, model.type, "type: \(model.id)")
            XCTAssertEqual(rawEntry["tags"] as? [String], model.tags, "tags: \(model.id)")

            let rawInfo = rawEntry["info"] as? [String: Any] ?? [:]
            XCTAssertEqual(rawInfo["name"] as? String, model.info?.name, "info.name: \(model.id)")
            XCTAssertEqual(rawInfo["developer"] as? String, model.info?.developer,
                           "info.developer: \(model.id)")
            XCTAssertEqual(rawInfo["docsUrl"] as? String, model.info?.docsUrl, "info.docsUrl: \(model.id)")
            XCTAssertEqual(rawInfo["docsJson"] as? String, model.info?.docsJson,
                           "info.docsJson: \(model.id)")
            XCTAssertEqual(rawInfo["releasedAt"] as? String, model.info?.releasedAt,
                           "info.releasedAt: \(model.id)")
            XCTAssertEqual(rawInfo["description"] as? String, model.info?.description,
                           "info.description: \(model.id)")
            XCTAssertEqual(rawInfo["isHottest"] as? Bool, model.info?.isHottest,
                           "info.isHottest: \(model.id)")
        }
    }

    /// A missing field must degrade a feature, never break the decode. Asserted directly, because
    /// "every field is optional" is a rule nobody can enforce by reading a struct six months later.
    func testTheDecodeToleratesEveryFieldDisappearing() throws {
        let minimal = Data(#"{"data":[{"id":"only-an-id"}]}"#.utf8)
        let response = try JSONDecoder().decode(AIMLEndpoints.ModelsResponse.self, from: minimal)
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].id, "only-an-id")
        XCTAssertNil(response.data[0].aliases)
        XCTAssertNil(response.data[0].type)
        XCTAssertNil(response.data[0].tags)
        XCTAssertNil(response.data[0].info)

        let emptyInfo = Data(#"{"data":[{"id":"x","info":{}}]}"#.utf8)
        let second = try JSONDecoder().decode(AIMLEndpoints.ModelsResponse.self, from: emptyInfo)
        XCTAssertNotNil(second.data[0].info)
        XCTAssertNil(second.data[0].info?.name)

        // The old app-target type required `object: String`. The new one must decode a body without it.
        XCTAssertNoThrow(
            try JSONDecoder().decode(AIMLEndpoints.ModelsResponse.self,
                                     from: Data(#"{"data":[]}"#.utf8)))
    }

    /// The `info` winner for a spelling served on several endpoint families is chosen by
    /// `infoPreferenceOrder`, not by JSON order. Task 12 reads `displayName` through this, so a
    /// non-deterministic answer would mean a catalog that changes under a re-capture that changed
    /// nothing.
    func testInfoSelectionIsDeterministicForMultiFamilySpellings() throws {
        let info = try AIMLModelsFixture.infoBySpelling()
        XCTAssertEqual(info["google/gemini-2.5-flash-image"]?.name, "Gemini 2.5 Flash Image",
                       "the image-generations entry must win over the chat-completions one")
        XCTAssertEqual(info["google/gemini-3-pro-image-preview"]?.name, "Gemini 3 Pro Image")
        XCTAssertEqual(info.count, Self.expectedSpellingCount)
    }
}
