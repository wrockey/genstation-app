import XCTest
@testable import GenStationCore

final class JobSchedulerCoreTests: XCTestCase {

    func testSlotsAvailableIsCapMinusRunning() {
        let core = JobSchedulerCore(maxConcurrent: 4)
        XCTAssertEqual(core.slotsAvailable(running: 0), 4)
        XCTAssertEqual(core.slotsAvailable(running: 3), 1)
        XCTAssertEqual(core.slotsAvailable(running: 4), 0)
    }

    func testSlotsAvailableNeverGoesNegative() {
        let core = JobSchedulerCore(maxConcurrent: 2)
        XCTAssertEqual(core.slotsAvailable(running: 5), 0)
    }

    func testIdsToStartPreservesFIFOOrderAndRespectsCap() {
        let core = JobSchedulerCore(maxConcurrent: 3)
        let queued = (0..<5).map { _ in UUID() }
        let started = core.idsToStart(queued: queued, runningCount: 1)
        XCTAssertEqual(started, Array(queued.prefix(2)))
    }

    func testIdsToStartReturnsEmptyWhenSaturated() {
        let core = JobSchedulerCore(maxConcurrent: 2)
        let queued = [UUID(), UUID()]
        XCTAssertTrue(core.idsToStart(queued: queued, runningCount: 2).isEmpty)
    }

    func testIdsToStartHandlesEmptyQueue() {
        let core = JobSchedulerCore(maxConcurrent: 4)
        XCTAssertTrue(core.idsToStart(queued: [], runningCount: 0).isEmpty)
    }

    func testZeroCapStartsNothing() {
        let core = JobSchedulerCore(maxConcurrent: 0)
        XCTAssertTrue(core.idsToStart(queued: [UUID()], runningCount: 0).isEmpty)
    }
}
