import XCTest
@testable import GenStationCore

/// `typicalWallClock` replaces `ModelRegistry.typicalDurationsByFamily` — 11 substring tokens,
/// first match wins, applied to whatever id string the caller happened to hold.
///
/// Stage 2's playbook: pin equivalence with the thing being replaced FIRST, then state the
/// invariant. The expectation below is the old token table re-expressed against the 30 video
/// families Task 12 authored, so every video row keeps exactly the range the app showed on
/// 2026-07-27 — with the deviations listed in `testTheDeliberateDeviations` and nowhere else.
final class CatalogWallClockTests: XCTestCase {

    /// family -> the range the old token table gave that family's ids.
    /// nil means the old table had no token for it and this stage does not invent one.
    static let expectedByFamily: [String: ClosedRange<TimeInterval>?] = [
        // ("veo", 120...300)
        "Veo 2": 120...300, "Veo 3": 120...300, "Veo 3.1": 120...300,
        // ("sora", 120...360)
        "Sora 2": 120...360,
        // ("kling", 180...480)
        "Kling 1.0": 180...480, "Kling 1.6": 180...480, "Kling 2.0": 180...480,
        "Kling 2.1": 180...480, "Kling 2.5": 180...480, "Kling 2.6": 180...480,
        "Kling 3.0": 180...480, "Kling O1": 180...480,
        // ("wan", 120...360)
        "Wan 2.1": 120...360, "Wan 2.2": 120...360, "Wan 2.5": 120...360,
        "Wan 2.6": 120...360, "Wan 2.7": 120...360,
        // ("seedance", 120...300)
        "Seedance 1.0": 120...300, "Seedance 1.5": 120...300, "Seedance 2.0": 120...300,
        // ("hailuo", 180...480) and ("minimax", 180...480)
        "MiniMax Hailuo": 180...480, "MiniMax Video": 180...480,
        // ("luma", 60...240)
        "Luma Ray": 60...240,
        // ("runway", 60...180)
        "Runway Gen-3": 60...180, "Runway Gen-4": 60...180,
        // ("pixverse", 60...180)
        "PixVerse V5": 60...180, "PixVerse V5.5": 60...180,
        // ("ltx", 60...180)
        "LTX Video 2": 60...180,
        // No token existed for these two, and no published or observed figure exists either.
        // nil is the honest value: VideoJobFormat.progressLine degrades to elapsed + status.
        "Wan 3.0": nil, "Seedance 2.5": nil, "MiniMax H3": nil,
        "OmniHuman": nil,
        "Kandinsky 5": nil,
    ]

    func testEveryVideoRowCarriesItsFamilysWallClock() {
        let videoRows = Catalog.all.filter { $0.task == .video }
        XCTAssertEqual(videoRows.count, 77,
                       "expected 74 canonical video rows after the collapse, got \(videoRows.count)")
        XCTAssertEqual(Set(videoRows.map(\.family)), Set(Self.expectedByFamily.keys),
                       "the video families and the expectation table have drifted apart")

        for model in videoRows {
            guard let expected = Self.expectedByFamily[model.family] else {
                XCTFail("video family '\(model.family)' (\(model.id)) is missing from "
                        + "expectedByFamily — add it here and to the row files together")
                continue
            }
            XCTAssertEqual(model.typicalWallClock, expected,
                           "\(model.id) — family '\(model.family)'")
        }
    }

    /// Design § 3.6, invariant 7. This is the 13-id bug turned into something a test forbids.
    /// Note honestly: it is green the moment it is written, because Task 8 emitted every row nil.
    /// It is not reproducing a bug — it is preventing the bug from being re-introduced by the
    /// per-row seeding below, and forever after.
    func testWallClockIsNilForEveryNonVideoModel() {
        let offenders = Catalog.all
            .filter { $0.task != .video && $0.typicalWallClock != nil }
            .map(\.id)
        XCTAssertTrue(
            offenders.isEmpty,
            "\(offenders.count) non-video rows carry a generation-time estimate — the old token "
                + "table did this for 13 image ids: \(offenders.joined(separator: ", "))"
        )
    }

    /// Ranges are generation time in SECONDS, 60…480. A value in the 5…15 band means someone wrote
    /// output clip length into this field.
    func testRangesAreGenerationTimeNotClipLength() {
        for model in Catalog.all {
            guard let range = model.typicalWallClock else { continue }
            XCTAssertGreaterThanOrEqual(range.lowerBound, 60,
                "\(model.id): \(range) looks like clip length (seconds of video), not generation time")
            XCTAssertLessThanOrEqual(range.upperBound, 480, "\(model.id): \(range)")
        }
    }
}

extension CatalogWallClockTests {

    /// The move from a token table to per-model data changes the answer for exactly 21 ids.
    /// Listing them here is what makes the change reviewable rather than a silent behaviour edit.
    /// Every lookup below goes through the alias index (Task 11), so this is also an alias check.
    func testTheDeliberateDeviations() {
        // 13 image ids that the token table wrongly gave a generation-time estimate. Every one has
        // `pollingEndpoint: nil`, so none of them can ever be a polled job.
        let imageIDsThatUsedToGetARange = [
            "klingai/image-o1",
            "wan2.2-t2i-plus", "wan2.2-t2i-flash", "wan2.5-t2i-preview",
            "alibaba/wan2.2-t2i-plus", "alibaba/wan2.2-t2i-flash", "alibaba/wan2.5-t2i-preview",
            "alibaba/wan2.6-image", "alibaba/wan2.7-image", "alibaba/wan2.7-image-pro",
            "wan2.6-image", "wan2.7-image", "wan2.7-image-pro",
        ]
        for id in imageIDsThatUsedToGetARange {
            let model = Catalog.model(for: id)
            XCTAssertNotNil(model, "\(id) must still resolve — this is an alias-index check too")
            XCTAssertEqual(model?.task, .image, "\(id)")
            XCTAssertNil(model?.typicalWallClock, "\(id) is an image model")
        }

        // 8 video alias spellings the token table missed while their siblings matched. Storing the
        // value per model rather than per id spelling is what fixes these. `video-01` is a MiniMax
        // Video row (180…480) and `gen3a_turbo` a Runway Gen-3 row (60…180); asserting one shared
        // range for all eight would be wrong.
        let expectedForAliases: [String: ClosedRange<TimeInterval>] = [
            "video-01": 180...480, "gen3a_turbo": 60...180,
            "alibaba/happyhorse-1.0-t2v": 120...360, "happyhorse-1.0-t2v": 120...360,
            "alibaba/happyhorse-1.0-i2v": 120...360, "happyhorse-1.0-i2v": 120...360,
            "alibaba/happyhorse-1.0-r2v": 120...360, "happyhorse-1.0-r2v": 120...360,
        ]
        for (id, expected) in expectedForAliases {
            let model = Catalog.model(for: id)
            XCTAssertNotNil(model, "\(id)")
            XCTAssertEqual(model?.task, .video, "\(id)")
            XCTAssertEqual(model?.typicalWallClock, expected,
                           "\(id) must now agree with its canonical row")
        }
    }
}
