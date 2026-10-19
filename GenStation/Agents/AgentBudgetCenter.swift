#if os(macOS)
import SwiftUI
import GenStationCore

@MainActor
final class AgentBudgetCenter: ObservableObject {
    static let shared = AgentBudgetCenter()
    let authority = AgentSpendingThreshold(file: MCPStateStore.fileURL.deletingLastPathComponent().appendingPathComponent("agent_spending_threshold.json"))
    struct Paused: Identifiable {
        let id: String
        let requestID: String
        let prompt: String
        let model: String
        let reason: String
    }
    @Published private(set) var snapshot: [String: Any] = [:]
    @Published private(set) var paused: [Paused] = []
    private var decisions: [String: Bool] = [:]
    private init() { refresh() }
    func refresh() { snapshot = authority.snapshot }
    func pause(_ job: AgentImageJob, prompt: String, model: String, reason: String) {
        paused.removeAll { $0.id == job.id }
        paused.append(Paused(id: job.id, requestID: job.requestID, prompt: prompt, model: model, reason: reason))
        refresh()
    }
    func decide(_ id: String, approved: Bool) { decisions[id] = approved }
    func takeDecision(_ id: String) -> Bool? { decisions.removeValue(forKey: id) }
    func removePaused(_ id: String) { paused.removeAll { $0.id == id }; decisions.removeValue(forKey: id) }
}

struct AgentBudgetControls: View {
    @ObservedObject private var center = AgentBudgetCenter.shared
    @State private var amount = "5"
    @State private var selected: Set<String> = []
    @State private var hours = 1
    @State private var error: String?
    private var models: [(key: String, provider: Provider, model: String)] {
        AgentImageContract.models().compactMap { row in
            guard let name = row["provider"] as? String, let provider = Provider(rawValue: name),
                  [.aimlapi, .grok].contains(provider), let model = row["id"] as? String else { return nil }
            return (name + ":" + model, provider, model)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Image approval").font(.headline)
            Text("Default: Ask every time. Budget approval runs requests one at a time and stops starting requests when recorded spending reaches your budget. The final request can exceed it. Missing billing pauses the grant.").font(.caption)
            Text("Connected agents share this grant and use your configured credentials. Scope includes selected MCP image requests and their reference images; no extra file access. Manual work, video, workflows, other apps, taxes and unrelated account charges are outside this budget. Costs are provider reported, not independently reconciled.").font(.caption).foregroundStyle(.secondary)
            Text("State: \(center.snapshot["state"] as? String ?? "inactive")")
            if let spent = center.snapshot["spent_usd"] as? String {
                Text("Budget $\(center.snapshot["budget_usd"] as? String ?? "0") · Spent $\(spent)\nRemaining $\(center.snapshot["remaining_usd"] as? String ?? "0") · Overage $\(center.snapshot["overage_usd"] as? String ?? "0")")
                    .font(.caption).textSelection(.enabled)
            }
            if center.authority.activeGrantID != nil {
                Text("Expires: \(center.snapshot["expires_at"] as? String ?? "")").font(.caption)
                if let scope = center.snapshot["scope"] as? [[String: String]] {
                    Text("Approved models: " + scope.map { "\($0["provider"] ?? "") · \($0["model"] ?? "")" }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let job = center.snapshot["active_job_id"] as? String { Text("Active or unresolved job: \(job)").font(.caption).textSelection(.enabled) }
            if let previous = center.snapshot["previous_grants"] as? [[String: String]], !previous.isEmpty {
                DisclosureGroup("Previous grant accounting (\(previous.count))") {
                    ForEach(previous, id: \.self) { record in
                        Text("\(record["grant_id"] ?? "") · budget $\(record["budget_usd"] ?? "0") · spent $\(record["spent_usd"] ?? "0")").font(.caption).textSelection(.enabled)
                    }
                }
            }
            HStack {
                TextField("USD budget", text: $amount).frame(width: 120)
                if center.authority.activeGrantID != nil {
                    Button("Change budget") { perform { try center.authority.changeBudget(ExactUSD(decimal: amount)) } }
                    Button("Turn off") { perform { try center.authority.disable() } }
                }
            }
            if center.authority.activeGrantID == nil {
                DisclosureGroup("Select supported providers/models (AIML and xAI)") {
                    ForEach(models, id: \.key) { row in
                        Toggle(row.key, isOn: Binding(get: { selected.contains(row.key) }, set: { on in
                            if on { selected.insert(row.key) } else { selected.remove(row.key) }
                        })).font(.caption)
                    }
                }
                Picker("Expiry", selection: $hours) {
                    Text("1 hour").tag(1); Text("4 hours").tag(4); Text("24 hours").tag(24)
                }
                Text("Ends at expiry or app quit. Accounting survives restart. Starting a new grant preserves previous records and cannot clear unresolved billing.").font(.caption)
                Button("Approve image requests with a budget") {
                    perform {
                        try center.authority.enable(budget: ExactUSD(decimal: amount),
                            scopes: models.filter { selected.contains($0.key) }.map { .init(provider: $0.provider, model: $0.model) },
                            expiresAt: Date().addingTimeInterval(Double(hours) * 3600))
                    }
                }.disabled(selected.isEmpty)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in center.refresh() }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = error.localizedDescription }
        center.refresh()
    }
}

struct AgentBudgetJobsView: View {
    @ObservedObject private var center = AgentBudgetCenter.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if center.authority.activeGrantID != nil || center.snapshot["state"] as? String == "billing_unresolved" {
                Text("Image budget: \(center.snapshot["state"] as? String ?? "inactive") — spent $\(center.snapshot["spent_usd"] as? String ?? "0")").font(.caption)
            }
            ForEach(center.paused) { job in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paused: \(job.reason)").font(.headline)
                    Text("\(job.model)\n\(job.prompt)").textSelection(.enabled)
                    Text("Job \(job.id) · Request \(job.requestID)").font(.caption).textSelection(.enabled)
                    Text("Change the active budget in Agent Access, deny this work, or explicitly approve this separate request. Approval once is outside the grant and may incur an unknown charge even on failure.").font(.caption)
                    HStack {
                        Button("Deny") { center.decide(job.id, approved: false) }
                        Button("Approve once outside budget") { center.decide(job.id, approved: true) }
                    }
                }.padding()
            }
        }.padding(.horizontal)
    }
}
#endif
