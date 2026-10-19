import XCTest
@testable import GenStationCore

/// Property tests on the record itself. There is no catalog yet — these prove the type can hold
/// what the catalog will need it to hold, including the two shapes that are easy to get wrong:
/// an optional `ClosedRange<TimeInterval>` surviving a Codable round trip, and a row whose
/// `isRegistered` is false (the "unregistered" badge's data, which `lifecycle` cannot carry
/// because a synthesized model has no lifecycle we know).
final class CatalogModelTests: XCTestCase {

    /// A registered video row with every field set to a distinguishable value. The ids are real
    /// registry ids (`ModelRegistry.swift:146-2079`) so nothing here invents a model that the
    /// later equivalence gate would then have to explain.
    private static func sample(
        id: String = "alibaba/wan-2-7-i2v",
        wallClock: ClosedRange<TimeInterval>? = 120...360,
        isRegistered: Bool = true,
        task: CreateTask = .video
    ) -> CatalogModel {
        CatalogModel(
            id: id,
            aliases: ["alibaba/wan2.7-i2v", "wan-2-7-i2v"],
            provider: .aimlapi,
            displayName: "Wan 2.7 Image-to-Video",
            family: "Wan",
            lifecycle: .current,
            typicalWallClock: wallClock,
            isRegistered: isRegistered,
            task: task,
            isI2I: true,
            requiresInputImage: true,
            supportsMask: false,
            maxInputImages: 1,
            imageInputParam: "image_url",
            secondImageParam: nil,
            acceptsMultiImages: false,
            acceptsBase64: true,
            acceptsPublicURL: true,
            acceptsBinary: false,
            generationEndpoint: AIMLEndpoints.videoGeneration,
            pollingEndpoint: AIMLEndpoints.videoGenerationPoll)
    }

    /// The round trip has to survive `ClosedRange<TimeInterval>?`, which is the only field whose
    /// Codable conformance comes from the standard library rather than from synthesis here.
    func testCodableRoundTripPreservesEveryField() throws {
        let model = Self.sample()
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(CatalogModel.self, from: data)

        XCTAssertEqual(decoded, model)
        XCTAssertEqual(decoded.typicalWallClock, 120...360)
        XCTAssertEqual(decoded.typicalWallClock?.lowerBound, 120)
        XCTAssertEqual(decoded.typicalWallClock?.upperBound, 360)
        XCTAssertEqual(decoded.aliases, ["alibaba/wan2.7-i2v", "wan-2-7-i2v"])
        XCTAssertEqual(decoded.provider, .aimlapi)
        XCTAssertEqual(decoded.task, .video)
        XCTAssertNil(decoded.secondImageParam)
    }

    /// The nil case separately: an image model must be able to say "no wall-clock estimate", and
    /// a `nil` inside an optional-of-a-container is exactly where a hand-written `Codable` slips.
    func testCodableRoundTripPreservesANilWallClock() throws {
        let model = Self.sample(id: "alibaba/qwen-image", wallClock: nil, task: .image)
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(CatalogModel.self, from: data)

        XCTAssertEqual(decoded, model)
        XCTAssertNil(decoded.typicalWallClock)
    }

    /// Hashable is load-bearing: `Catalog` keys a dictionary by id and `CatalogGroup` holds these
    /// inside a `Hashable` value, so equality must actually compare the fields.
    func testHashableComparesFieldsRatherThanIdentity() {
        let a = Self.sample()
        let b = Self.sample()
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertEqual(Set([a, b]).count, 1)

        XCTAssertNotEqual(a, Self.sample(wallClock: 120...480))
        XCTAssertNotEqual(a, Self.sample(id: "alibaba/wan-2-7-t2v"))
        XCTAssertNotEqual(a, Self.sample(isRegistered: false))
    }

    /// `isVideo` is a view onto `task`, not a second field that can disagree with it — that
    /// disagreement is what `AIMLModel`'s separate `isVideo: Bool` allowed.
    func testIsVideoAgreesWithTask() {
        XCTAssertTrue(Self.sample(task: .video).isVideo)
        XCTAssertFalse(Self.sample(task: .image).isVideo)
        for task in CreateTask.allCases {
            XCTAssertEqual(Self.sample(task: task).isVideo, task == .video)
        }
    }

    /// The provenance flag the picker's "unregistered" badge reads. A value with
    /// `isRegistered == false` must be constructible without any other field changing meaning.
    func testAnUnregisteredRowIsConstructible() {
        let synthesized = Self.sample(id: "alibaba/qwen-image-3", wallClock: nil,
                                      isRegistered: false, task: .image)
        XCTAssertFalse(synthesized.isRegistered)
        XCTAssertEqual(synthesized.id, "alibaba/qwen-image-3")
        XCTAssertEqual(synthesized.lifecycle, .current)
        XCTAssertEqual(Lifecycle.allCases, [.current, .superseded, .dead])
        XCTAssertEqual(Lifecycle.dead.rawValue, "dead")
    }
}
