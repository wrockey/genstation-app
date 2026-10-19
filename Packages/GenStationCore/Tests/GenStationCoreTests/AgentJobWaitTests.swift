import XCTest
@testable import GenStationCore

final class AgentJobWaitTests: XCTestCase {
    private func job(_ status: String = "awaiting_approval", pending: Bool = true) -> AgentJobSummary {
        AgentJobSummary(id: "a", requestID: "request-a", kind: "image", createdAt: Date(timeIntervalSince1970: 100),
            status: status, billing: "not_submitted", pendingApproval: pending, recoveryAvailable: false, label: nil)
    }
    @MainActor func testInitialSnapshotTimeoutAndTerminalDoNotSubmit() async throws {
        let pending = job()
        let initial = try await AgentJobWait.wait(since: nil, timeout: 20) { pending }
        XCTAssertEqual(initial["changed"] as? Bool, true)
        let token = initial["state_token"] as! String
        XCTAssertEqual(token, pending.json(now: Date().addingTimeInterval(90))["state_token"] as? String)
        let timeout = try await AgentJobWait.wait(since: token, timeout: 0.01) { pending }
        XCTAssertEqual(timeout["timed_out"] as? Bool, true)
        XCTAssertEqual(timeout["approval_state"] as? String, "pending")
        let done = job("done", pending: false)
        let terminal = try await AgentJobWait.wait(since: done.json(now: Date())["state_token"] as? String, timeout: 20) { done }
        XCTAssertEqual(terminal["terminal_or_attention"] as? Bool, true)
        XCTAssertEqual(terminal["timed_out"] as? Bool, false)
    }
    @MainActor func testWaitRechecksStateAndAccess() async throws {
        let token = job().json(now: Date())["state_token"] as? String
        var checks = 0
        let changed = try await AgentJobWait.wait(since: token, timeout: 1) {
            checks += 1
            return self.job(checks > 1 ? "done" : "awaiting_approval", pending: checks == 1)
        }
        XCTAssertEqual(changed["status"] as? String, "done")
        XCTAssertEqual(checks, 2)
        checks = 0
        do {
            _ = try await AgentJobWait.wait(since: token, timeout: 1) {
                checks += 1
                if checks > 1 { throw AgentImageError("Access revoked") }
                return self.job()
            }
            XCTFail("Revoked access must fail")
        } catch { XCTAssertEqual(checks, 2) }
    }
    @MainActor func testInvalidWaitAndCancellation() async throws {
        for seconds in [-1.0, 21, .infinity, .nan] {
            do { _ = try await AgentJobWait.wait(since: nil, timeout: seconds) { self.job() }; XCTFail("Invalid timeout") }
            catch {}
        }
        let task = Task { @MainActor in
            try await AgentJobWait.wait(since: self.job().json(now: Date())["state_token"] as? String, timeout: 20) { self.job() }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled wait") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
}
