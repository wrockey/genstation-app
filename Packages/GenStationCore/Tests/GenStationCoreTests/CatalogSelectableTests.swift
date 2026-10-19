import XCTest
@testable import GenStationCore

/// `Catalog.selectable(task:)` — spec § 3.6 invariant 4, and the grouping the picker (Task 23)
/// and MCP `list_models` (Task 21) both read.
///
/// The first five methods run against a **hand-built** list, not against `Catalog.all`. They
/// have to: at this point in the plan every real row is `.current` and carries `family: ""`, so
/// there is no `.dead` model and no second family in the catalog to test with. The internal
/// `selectable(task:from:)` seam exists for exactly this, and the public entry point is a
/// one-line call to it, so testing the seam tests the thing.
///
/// The last method runs against the real catalog and is written to mean something both now and
/// after Task 12 supplies families: it asserts the groups are exactly the distinct families of
/// the non-dead rows of that task. Today that is one group; after Task 12 it is about thirty;
/// after Task 22 the `.dead` exclusion starts removing rows. The assertion does not change.
final class CatalogSelectableTests: XCTestCase {

    private static func make(_ id: String, family: String,
                             lifecycle: Lifecycle = .current,
                             task: CreateTask = .image) -> CatalogModel {
        CatalogModel(
            id: id, aliases: [], provider: .aimlapi, displayName: id, family: family,
            lifecycle: lifecycle, typicalWallClock: nil, isRegistered: true, task: task,
            isI2I: false, requiresInputImage: false, supportsMask: false, maxInputImages: 0,
            imageInputParam: "", secondImageParam: nil, acceptsMultiImages: false,
            acceptsBase64: true, acceptsPublicURL: true, acceptsBinary: false,
            generationEndpoint: AIMLEndpoints.imageGeneration, pollingEndpoint: nil)
    }

    /// Deliberately unsorted, with one family whose only member is dead.
    private static let fixture: [CatalogModel] = [
        make("zeta/one", family: "Zeta"),
        make("alpha/two", family: "Alpha"),
        make("alpha/one", family: "Alpha", lifecycle: .superseded),
        make("alpha/zero", family: "Alpha", lifecycle: .dead),
        make("gone/only", family: "Gone", lifecycle: .dead),
        make("vid/one", family: "Zeta", task: .video),
    ]

    /// Invariant 4, and its other half: `.superseded` is still *selectable*. Only `.dead` is
    /// filtered. A model the API still serves must stay pickable even once a newer one exists.
    func testDeadIsExcludedAndSupersededIsIncluded() {
        let groups = Catalog.selectable(task: .image, from: Self.fixture)
        let ids = groups.flatMap { $0.models.map(\.id) }
        XCTAssertEqual(ids, ["alpha/one", "alpha/two", "zeta/one"])
        XCTAssertFalse(ids.contains("alpha/zero"))
        XCTAssertFalse(ids.contains("gone/only"))
        XCTAssertEqual(groups.map(\.family), ["Alpha", "Zeta"])
    }

    /// Stable order, from an input that is in neither order. A dictionary-backed grouping that
    /// forgot to sort would pass this only by luck, so equality of two calls is asserted too.
    func testGroupsAreSortedByFamilyAndModelsByID() {
        let groups = Catalog.selectable(task: .image, from: Self.fixture)
        XCTAssertEqual(groups.map(\.family), groups.map(\.family).sorted())
        for group in groups {
            XCTAssertEqual(group.models.map(\.id), group.models.map(\.id).sorted(), group.family)
        }
        XCTAssertEqual(Catalog.selectable(task: .image, from: Self.fixture), groups)
    }

    /// "Gone" exists as a family in the input and must not appear as a heading with nothing
    /// under it — an empty section is a UI bug that only shows up with real lifecycle data.
    func testAFamilyWithNoSurvivingModelProducesNoGroup() {
        let groups = Catalog.selectable(task: .image, from: Self.fixture)
        XCTAssertFalse(groups.contains { $0.models.isEmpty })
        XCTAssertFalse(groups.contains { $0.family == "Gone" })
    }

    func testTheTaskFilterIsExact() {
        let image = Catalog.selectable(task: .image, from: Self.fixture)
        let video = Catalog.selectable(task: .video, from: Self.fixture)
        XCTAssertEqual(video.flatMap { $0.models.map(\.id) }, ["vid/one"])
        XCTAssertFalse(image.flatMap { $0.models }.contains { $0.task == .video })
        XCTAssertFalse(video.flatMap { $0.models }.contains { $0.task == .image })
    }

    func testACatalogGroupHoldsItsFamilyAndModels() {
        let one = Self.make("zeta/one", family: "Zeta")
        let group = CatalogGroup(family: "Zeta", models: [one])
        XCTAssertEqual(group.family, "Zeta")
        XCTAssertEqual(group.models, [one])
        XCTAssertEqual(Set([group, CatalogGroup(family: "Zeta", models: [one])]).count, 1)
        XCTAssertNotEqual(group, CatalogGroup(family: "Zeta", models: []))
    }

    /// The real catalog, both tasks. Written as "the groups are exactly the distinct families of
    /// the surviving rows", which is true with one provisional family today and with thirty after
    /// Task 12. **Task 12 tightens this** by adding `XCTAssertFalse(group.family.isEmpty)`; that
    /// line cannot be written here because every row's family is `""` and it would fail on data
    /// this task deliberately does not have.
    func testTheRealCatalogGroupsIntoExactlyItsDistinctFamilies() {
        for task in CreateTask.allCases {
            let expected = Catalog.all.filter { $0.task == task && $0.lifecycle != .dead }
            let groups = Catalog.selectable(task: task)

            XCTAssertEqual(Set(groups.map(\.family)), Set(expected.map(\.family)), "\(task)")
            XCTAssertEqual(groups.count, Set(expected.map(\.family)).count, "\(task)")
            XCTAssertEqual(groups.flatMap { $0.models.map(\.id) }.sorted(),
                           expected.map(\.id).sorted(), "\(task)")
            XCTAssertFalse(groups.contains { $0.models.isEmpty }, "\(task)")
            XCTAssertFalse(groups.flatMap(\.models).contains { $0.lifecycle == .dead }, "\(task)")
        }
    }
}
