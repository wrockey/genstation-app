// Standalone, provider-free AppKit regression check. Compile alongside
// GenStation/Agents/AgentApprovalCenter.swift; never calls a generation service.
import AppKit
import Foundation

@main
struct ApprovalRegression {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let center = AgentApprovalCenter()
        var decisions: [Bool] = []
        let first = Task { @MainActor in
            let value = await center.request(jobID: "test-first", requestID: "panel-request", requestLabel: "Panel One", createdAt: Date(timeIntervalSince1970: 1000), prompt: "UI regression fixture; no provider request", model: "Test only", notice: "No generation or upload occurs.")
            decisions.append(value)
        }
        while center.pending.isEmpty { await Task.yield() }
        precondition(center.pending.first?.requestID == "panel-request" && center.pending.first?.requestLabel == "Panel One")
        precondition(center.pending.first?.createdAt == Date(timeIntervalSince1970: 1000))
        // Exercise the actual red-close-button path, not just Review Later.
        let window = NSApp.windows.first { $0.title == "Review Agent Generation" }!
        window.performClose(nil)
        await Task.yield()
        precondition(center.pending.count == 1 && decisions.isEmpty, "Closing must not deny or drop a request")
        center.review("test-first")
        precondition(NSApp.windows.contains { $0.title == "Review Agent Generation" && $0.isVisible })
        center.hideReview()
        precondition(center.pending.count == 1 && decisions.isEmpty, "Review Later must preserve the original decision")
        center.review("test-first")
        center.decide("test-first", approved: true)
        center.decide("test-first", approved: false)
        await first.value
        precondition(decisions == [true] && center.pending.isEmpty, "A decision must resume exactly once")

        let second = Task { @MainActor in
            decisions.append(await center.request(jobID: "test-second", prompt: "Fixture", model: "Test", notice: nil))
        }
        let third = Task { @MainActor in
            decisions.append(await center.request(jobID: "test-third", prompt: "Fixture", model: "Test", notice: nil))
        }
        while center.pending.count < 2 { await Task.yield() }
        let duplicate = await center.request(jobID: "test-second", prompt: "Duplicate", model: "Test", notice: nil)
        precondition(!duplicate && center.pending.count == 2)
        center.hideReview()
        center.denyAll()
        await second.value
        await third.value
        precondition(decisions == [true, false, false] && center.pending.isEmpty, "Revocation must settle all waiting decisions")
        print("PASS: close, reopen, defer, exactly-once decision, concurrent pending requests, duplicate protection and revocation; zero provider calls")
    }
}
