import Foundation

/// Bounded local-state observation. The snapshot closure must recheck authority and
/// must not submit, recover or approve jobs. A token observes summary state only.
public enum AgentJobWait {
    @MainActor
    public static func wait(since: String?, timeout: TimeInterval,
                            snapshot: () throws -> AgentJobSummary) async throws -> [String: Any] {
        guard timeout.isFinite, timeout >= 0, timeout <= 20 else { throw AgentImageError("timeout_seconds must be from 0 to 20.") }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(Int64(timeout * 1000)))
        while true {
            try Task.checkCancellation()
            let job = try snapshot()
            var result = job.json(now: Date())
            let changed = since == nil || result["state_token"] as? String != since
            let terminal = ["done", "failed", "denied", "cancelled", "interrupted", "recoverable", "submission_unknown"].contains(job.status)
            if changed || terminal || clock.now >= deadline {
                result["changed"] = changed
                result["timed_out"] = !changed && !terminal && clock.now >= deadline
                result["terminal_or_attention"] = terminal
                result["next_step"] = terminal || changed ? "Read get_job_status for results or failure details. Never resubmit to resume." : "Keep the same IDs and wait/poll again. Approval remains the user's decision."
                return result
            }
            try await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(500))))
        }
    }
}
