import Foundation

/// User-owned, process-local activation with durable accounting. MCP has no mutation API.
/// MainActor gives revocation and synchronous durable submission intent a total ordering.
@MainActor
public final class AgentSpendingThreshold {
    public struct Scope: Codable, Hashable, Sendable {
        public let provider: Provider
        public let model: String
        public init(provider: Provider, model: String) { self.provider = provider; self.model = model }
    }
    private struct Grant: Codable {
        let id: String
        var revision: UInt64 = 1
        var budget: ExactUSD
        let scopes: [Scope]
        let expiresAt: Date
    }
    private struct Entry: Codable {
        let grantID: String
        let jobID: String
        let requestID: String
        let fingerprint: String
        var grantRevision: UInt64
        let scope: Scope
        var state: String // reserved, intent, unresolved, settled, not_submitted
        var evidence: ProviderChargeEvidence?
    }
    private struct Ledger: Codable {
        var version = 1
        var grants: [Grant] = []
        var entries: [Entry] = []
    }
    public let file: URL
    private var ledger = Ledger()
    public private(set) var activeGrantID: String?
    private var storageFailed = false
    public init(file: URL) {
        self.file = file
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file))
                guard ledger.version == 1,
                      Set(ledger.grants.map(\.id)).count == ledger.grants.count,
                      Set(ledger.entries.map(\.jobID)).count == ledger.entries.count,
                      Set(ledger.entries.map(\.requestID)).count == ledger.entries.count,
                      ledger.grants.allSatisfy({ $0.budget.ticks > 0 && $0.revision > 0 && !$0.scopes.isEmpty &&
                          $0.expiresAt.timeIntervalSince1970.isFinite && $0.scopes.allSatisfy { [.aimlapi, .grok].contains($0.provider) } }),
                      ledger.entries.filter({ ["reserved", "intent", "unresolved"].contains($0.state) }).count <= 1,
                      ledger.entries.allSatisfy({ entry in
                          ledger.grants.contains { $0.id == entry.grantID && $0.scopes.contains(entry.scope) && entry.grantRevision > 0 && entry.grantRevision <= $0.revision } &&
                          ["reserved", "intent", "unresolved", "settled", "not_submitted"].contains(entry.state) &&
                          (entry.state != "settled" || entry.evidence?.provider == entry.scope.provider)
                      }) else { throw AgentImageError("Invalid spending ledger.") }
                // No POST can occur before intent. After intent, never infer non-submission.
                var next = ledger
                for index in next.entries.indices {
                    if next.entries[index].state == "reserved" { next.entries[index].state = "not_submitted" }
                    if next.entries[index].state == "intent" { next.entries[index].state = "unresolved" }
                }
                try commit(next)
                for grant in ledger.grants { _ = try total(grant.id) }
            }
        } catch { storageFailed = true }
    }
    private var current: Grant? { ledger.grants.first { $0.id == (activeGrantID ?? ledger.grants.last?.id) } }
    private var obligation: Entry? { ledger.entries.first { ["reserved", "intent", "unresolved"].contains($0.state) } }
    public var spent: ExactUSD { (try? total(current?.id ?? "")) ?? ExactUSD(ticks: 0) }
    private func total(_ grantID: String) throws -> ExactUSD {
        try ledger.entries.filter { $0.grantID == grantID }.reduce(ExactUSD(ticks: 0)) { sum, entry in
            try sum.adding(entry.evidence?.amount ?? ExactUSD(ticks: 0))
        }
    }
    private func commit(_ next: Ledger) throws {
        guard !storageFailed else { throw AgentImageError("Spending storage is unavailable; automatic submission is disabled.") }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            ledger = next
        } catch { storageFailed = true; activeGrantID = nil; throw error }
    }
    public func enable(budget: ExactUSD, scopes: [Scope], expiresAt: Date) throws {
        guard budget.ticks > 0, !scopes.isEmpty, scopes.allSatisfy({ [.aimlapi, .grok].contains($0.provider) }),
              expiresAt > Date(), obligation == nil else { throw AgentImageError("Choose a positive budget, supported image scope and future expiry. Outstanding billing must settle before a new grant.") }
        var next = ledger
        let grant = Grant(id: UUID().uuidString, budget: budget, scopes: scopes, expiresAt: expiresAt)
        next.grants.append(grant)
        try commit(next)
        activeGrantID = grant.id
    }
    /// Cross-check the separate image ledger so a missing spending file cannot erase debt.
    public func verifyRecordedJob(jobID: String, grantID: String, fingerprint: String) throws {
        guard !storageFailed, ledger.entries.contains(where: { $0.jobID == jobID && $0.grantID == grantID && $0.fingerprint == fingerprint }) else {
            storageFailed = true; activeGrantID = nil
            throw AgentImageError("A possibly submitted image has no matching spending record. Restore budget storage before automatic submission.")
        }
    }
    public func disable() throws { activeGrantID = nil; try commit(ledger) }
    public func changeBudget(_ budget: ExactUSD) throws {
        guard budget.ticks > 0, let id = activeGrantID, let index = ledger.grants.firstIndex(where: { $0.id == id }) else { throw AgentImageError("No active grant or invalid budget.") }
        var next = ledger
        next.grants[index].budget = budget
        let revision = next.grants[index].revision.addingReportingOverflow(1)
        guard !revision.overflow else { throw AgentImageError("Grant revision overflow; disable this grant before starting another.") }
        next.grants[index].revision = revision.partialValue
        try commit(next)
    }
    public func covers(_ scope: Scope) -> Bool { activeGrantID != nil && current?.scopes.contains(scope) == true }
    public func pauseReason(grantID: String, now: Date = Date()) -> String? {
        if storageFailed { return "storage_unavailable" }
        if let obligation, obligation.state == "unresolved" { return "billing_unresolved" }
        guard activeGrantID == grantID, let grant = current else { return "grant_revoked" }
        if now >= grant.expiresAt { return "grant_expired" }
        if spent.ticks >= grant.budget.ticks { return "budget_exhausted" }
        if obligation != nil { return "in_flight" }
        return nil
    }
    public func reserve(jobID: String, requestID: String, fingerprint: String, scope: Scope, grantID: String) throws {
        guard ledger.entries.allSatisfy({ $0.jobID != jobID && $0.requestID != requestID }), covers(scope),
              let grant = current, grant.id == grantID, pauseReason(grantID: grantID) == nil else {
            throw AgentImageError(pauseReason(grantID: grantID) ?? "Invalid or repeated budget authorization.")
        }
        var next = ledger
        next.entries.append(Entry(grantID: grantID, jobID: jobID, requestID: requestID, fingerprint: fingerprint, grantRevision: grant.revision, scope: scope, state: "reserved"))
        try commit(next)
    }
    public func markIntent(jobID: String, grantID: String) throws {
        guard !storageFailed, activeGrantID == grantID, let grant = current,
              Date() < grant.expiresAt, spent.ticks < grant.budget.ticks,
              let index = ledger.entries.firstIndex(where: { $0.jobID == jobID && $0.grantID == grantID && $0.state == "reserved" }) else {
            throw AgentImageError("Budget authorization revoked, expired or unavailable before submission.")
        }
        var next = ledger; next.entries[index].state = "intent"; next.entries[index].grantRevision = grant.revision; try commit(next)
    }
    public func releaseUnsubmitted(jobID: String) throws {
        guard let index = ledger.entries.firstIndex(where: { $0.jobID == jobID && $0.state == "reserved" }) else { return }
        var next = ledger; next.entries[index].state = "not_submitted"; try commit(next)
    }
    public func settle(jobID: String, evidence: ProviderChargeEvidence?) throws {
        guard let index = ledger.entries.firstIndex(where: { $0.jobID == jobID }) else { throw AgentImageError("Unknown budget job.") }
        let entry = ledger.entries[index]
        if entry.state == "settled" {
            guard entry.evidence == evidence else { throw AgentImageError("Conflicting billing evidence.") }; return
        }
        guard ["intent", "unresolved"].contains(entry.state), evidence == nil || evidence?.provider == entry.scope.provider else { throw AgentImageError("Invalid settlement.") }
        var next = ledger
        next.entries[index].evidence = evidence
        next.entries[index].state = evidence == nil ? "unresolved" : "settled"
        // Overflow must block, never wrap or release the spending slot.
        if let evidence { _ = try total(entry.grantID).adding(evidence.amount) }
        try commit(next)
    }
    public var snapshot: [String: Any] {
        var value: [String: Any] = ["mode": activeGrantID == nil ? "ask_every_time" : "spending_threshold",
            "state": storageFailed ? "storage_unavailable" : (obligation?.state == "unresolved" ? "billing_unresolved" : (activeGrantID.flatMap { pauseReason(grantID: $0) } ?? (activeGrantID == nil ? "inactive" : "ready"))),
            "shared_by_connected_agents": true, "ends_on_app_quit": true,
            "billing_provenance": "provider_reported_not_independently_reconciled",
            "previous_grants": ledger.grants.filter { $0.id != current?.id }.map {
                ["grant_id": $0.id, "budget_usd": $0.budget.decimal, "spent_usd": ((try? total($0.id)) ?? ExactUSD(ticks: 0)).decimal]
            },
            "unresolved_jobs": ledger.entries.filter { $0.state == "unresolved" }.map(\.jobID)]
        if let grant = current {
            value["grant_id"] = grant.id; value["revision"] = String(grant.revision)
            value["budget_usd"] = grant.budget.decimal; value["spent_usd"] = spent.decimal
            value["remaining_usd"] = ExactUSD(ticks: grant.budget.ticks > spent.ticks ? grant.budget.ticks - spent.ticks : 0).decimal
            value["overage_usd"] = ExactUSD(ticks: spent.ticks > grant.budget.ticks ? spent.ticks - grant.budget.ticks : 0).decimal
            value["expires_at"] = ISO8601DateFormatter().string(from: grant.expiresAt)
            value["scope"] = grant.scopes.map { ["provider": $0.provider.rawValue, "model": $0.model, "kind": "image"] }
        }
        if let obligation { value["active_job_id"] = obligation.jobID }
        return value
    }
}
