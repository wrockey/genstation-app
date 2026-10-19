// JobsPanelView.swift
// Queue manager for remote video jobs: live queue state plus history-backed
// jobs needing attention. Per-job actions: cancel (queued/running), retry
// (failed, when the exact submission is stored), re-download
// (completed-but-undownloaded), open in history.
import SwiftUI
import GenStationCore

struct JobsPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        // Indirection so the panel observes the queue itself (appState doesn't
        // republish JobQueue changes).
        VStack(spacing: 0) {
            #if os(macOS)
            AgentBudgetJobsView()
            AgentPendingApprovalsView()
            #endif
            WorkflowRecoverySection(store: appState.workflowJobs)
            JobsPanelContent(queue: appState.jobQueue)
        }
    }
}

private struct WorkflowRecoverySection: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var store: WorkflowJobStore
    private var pending: [AgentImageJob] { store.jobs.filter { $0.workflow != nil && $0.status != "done" } }

    var body: some View {
        if !pending.isEmpty || store.storageError != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("ComfyUI Workflows").font(.headline)
                if let error = store.storageError { Text(error).font(.caption).foregroundStyle(.red) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(pending, id: \.id) { job in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(job.workflow?.workflowName ?? "Workflow").font(.subheadline.weight(.medium))
                                    Text(job.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
                                    if let message = job.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if store.canStopNamed(job.id) { Button("Stop Waiting") { store.stopNamed(job.id) } }
                                if job.workflow?.promptID != nil {
                                    Button("Recover Result") { store.recover(job, app: appState) }
                                        .disabled(store.activeIDs.contains(job.id) || store.storageError != nil)
                                        .accessibilityIdentifier("genstation.workflow.recover")
                                }
                            }
                        }
                    }
                }.frame(maxHeight: 180)
                Text("Recovery retrieves an existing job. It never starts generation again.").font(.caption).foregroundStyle(.secondary)
            }.padding()
            Divider()
        }
    }
}

private struct JobsPanelContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var queue: JobQueue
    @Environment(\.dismiss) private var dismiss

    /// One row per job: a history item (post-submission), optionally paired with
    /// its live queue record — plus queue records that have no history item yet
    /// (submitting) or represent auxiliary work (re-downloads).
    private struct JobRow: Identifiable {
        let id: String
        let item: HistoryItem?
        let liveJob: VideoJob?
        let date: Date
    }

    private func needsDownload(_ item: HistoryItem) -> Bool {
        (item.videoUrl != nil || item.sourceAssetURL != nil) && !item.fileExists(appState: appState)
    }

    private var rows: [JobRow] {
        var rows: [JobRow] = []
        var representedItems = Set<UUID>()

        // Live queue records first (running/queued, or finished within this session)
        for job in queue.jobs where job.kind != .resumeCheck {
            guard !jobFinishedAndSettled(job) else { continue }
            let item = job.historyItemID.flatMap { id in
                appState.historyState.history.flatMap { $0.allItems }.first { $0.id == id }
            }
            if let item = item { representedItems.insert(item.id) }
            rows.append(JobRow(id: "job-\(job.id)", item: item, liveJob: job, date: item?.date ?? job.createdAt))
        }

        // History-backed jobs needing attention (from any session)
        let historyJobs = appState.historyState.history.flatMap { $0.allItems }
            .filter { item in
                guard !representedItems.contains(item.id) else { return false }
                if needsDownload(item) { return true }
                guard let status = item.status else { return false }
                return status.isInProgress || status.needsAttention || (status == .cancelled && item.jobId != nil)
            }
        for item in historyJobs {
            rows.append(JobRow(id: "item-\(item.id)", item: item, liveJob: nil, date: item.date))
        }

        // Terminal rows the user removed / cleared stay hidden (history untouched).
        rows.removeAll { isTerminal($0) && appState.ui.dismissedJobsPanelIDs.contains(dismissalID(for: $0)) }

        return rows.sorted { $0.date > $1.date }
    }

    // MARK: Dismissals ("Remove" / "Clear Finished")

    /// Terminal = the row can't change anymore (completed / failed / cancelled /
    /// expired / timeout / blocked, or a finished live record). Only terminal rows
    /// are removable; active rows keep Cancel (cancelling a queued job IS its
    /// removal).
    private func isTerminal(_ row: JobRow) -> Bool {
        if let job = row.liveJob { return job.state.isFinished }
        guard let item = row.item else { return false }
        if let status = item.status, status.isInProgress { return false }
        return true
    }

    /// Stable key for the dismissed set: the history item id when one exists
    /// (survives relaunch), else the live job id (session-only rows).
    private func dismissalID(for row: JobRow) -> String {
        row.item?.id.uuidString ?? row.liveJob?.id.uuidString ?? row.id
    }

    private func dismissRow(_ row: JobRow) {
        appState.ui.dismissedJobsPanelIDs.insert(dismissalID(for: row))
    }

    private func clearFinished() {
        let ids = rows.filter(isTerminal).map(dismissalID(for:))
        guard !ids.isEmpty else { return }
        appState.ui.dismissedJobsPanelIDs.formUnion(ids)
    }

    /// Drops dismissed ids whose history item / live job no longer exists, so the
    /// persisted set can't grow forever.
    private func pruneDismissedIDs() {
        let valid = Set(appState.historyState.history.flatMap { $0.allItems }.map { $0.id.uuidString })
            .union(queue.jobs.map { $0.id.uuidString })
        let pruned = appState.ui.dismissedJobsPanelIDs.filter { valid.contains($0) }
        if pruned.count != appState.ui.dismissedJobsPanelIDs.count {
            appState.ui.dismissedJobsPanelIDs = pruned
        }
    }

    /// Finished queue records whose history item no longer needs attention are
    /// hidden (their outcome lives in History).
    private func jobFinishedAndSettled(_ job: VideoJob) -> Bool {
        guard job.state.isFinished else { return false }
        guard let itemID = job.historyItemID,
              let item = appState.historyState.history.flatMap({ $0.allItems }).first(where: { $0.id == itemID }) else {
            // No history item (e.g. cancelled before the POST returned):
            // only failures are worth keeping visible.
            if case .failed = job.state { return false }
            return true
        }
        if needsDownload(item) || (item.status == .cancelled && item.jobId != nil) { return false }
        if let status = item.status, status.needsAttention { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                        Text("No generation or download activity")
                            .font(.headline)
                        Text("Generation and download jobs needing attention appear here. Pending agent approvals and recoverable workflows appear above when available.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(rows) { row in jobRow(row) }
                        } footer: {
                            Text("In-progress jobs resume automatically when the app opens. Provider results expire, so download completed videos promptly.")
                        }
                    }
                }
            }
            .navigationTitle("Jobs")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Dismisses every terminal-state row at once; history items
                    // are untouched. Hidden when there is nothing to clear.
                    if rows.contains(where: isTerminal) {
                        Button("Clear Finished") { clearFinished() }
                            .help("Remove all finished jobs from this list (History is not affected)")
                            .accessibilityLabel("Clear finished jobs")
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: 440, minHeight: 440)
        .onAppear { pruneDismissedIDs() }
    }

    // MARK: Rows

    @ViewBuilder private func jobRow(_ row: JobRow) -> some View {
        HStack(spacing: 12) {
            statusBadge(for: row)
            VStack(alignment: .leading, spacing: 3) {
                Text(promptText(for: row))
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(modelText(for: row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if isAgentOriginated(row) {
                        AgentBadge()
                    }
                }
                if let job = row.liveJob, !job.state.isFinished, job.kind == .generation {
                    // Same elapsed/typical-range/status presentation as LoadingView
                    TimelineView(.periodic(from: job.createdAt, by: 1)) { context in
                        Text(VideoJobFormat.progressLine(job: job, now: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else if let detail = detailText(for: row) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            actionButtons(for: row)
        }
        .contentShape(Rectangle())
    }

    private func promptText(for row: JobRow) -> String {
        let prompt = row.item?.prompt ?? row.liveJob?.prompt ?? ""
        return prompt.isEmpty ? "(no prompt)" : prompt
    }

    private func modelText(for row: JobRow) -> String {
        row.item?.modelUsed ?? row.liveJob?.modelId ?? "AI/ML video"
    }

    private func isAgentOriginated(_ row: JobRow) -> Bool {
        row.item?.agentGenerated == true || row.liveJob?.agentOriginated == true
    }

    private func detailText(for row: JobRow) -> String? {
        if let job = row.liveJob, !job.state.isFinished {
            if job.kind == .redownload { return "Re-downloading…" }
            if let status = job.providerStatus { return "Provider status: \(status.wireValue)" }
            switch job.state {
            case .preparing: return "Preparing (uploading)…"
            case .queued: return "Waiting for a slot…"
            default: return "Submitting…"
            }
        }
        if case .failed(let message)? = row.liveJob?.state { return message }
        // Pending job from a previous session (no live poll loop yet)
        if let item = row.item, let status = item.status, status.isInProgress {
            var parts = ["\(VideoJobFormat.elapsed(Date().timeIntervalSince(item.date))) since submission"]
            if let modelId = item.modelUsed,
               let range = Catalog.model(for: modelId)?.typicalWallClock {
                parts.append("usually \(VideoJobFormat.typicalRange(range))")
            }
            return parts.joined(separator: " · ")
        }
        return nil
    }

    // MARK: Actions

    @ViewBuilder private func actionButtons(for row: JobRow) -> some View {
        HStack(spacing: 10) {
            // Cancel a queued/running job
            if let job = row.liveJob, !job.state.isFinished, job.kind == .generation {
                Button {
                    queue.cancel(job.id)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Stop tracking; provider billing may continue")
                .accessibilityLabel("Stop tracking")
            }

            if let item = row.item, row.liveJob?.state.isFinished ?? true {
                HistoryRecoveryActions(item: item)
            }

            // Open in history
            if let item = row.item {
                Button {
                    appState.presentedModal = .fullHistoryItem(item.id)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderless)
                .help("Open in History")
                .accessibilityLabel("Open in History")
            }

            // Remove a finished (terminal) row from this list — the history item
            // is kept. Running jobs only get Cancel; a queued job's Cancel IS its
            // removal.
            if isTerminal(row) {
                Button {
                    dismissRow(row)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove from this list (keeps the History item)")
                .accessibilityLabel("Remove from list")
            }
        }
        .font(.system(size: 16))
    }

    // MARK: Badges

    @ViewBuilder private func statusBadge(for row: JobRow) -> some View {
        let (label, color) = badgeInfo(for: row)
        Text(label)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .frame(minWidth: 64)
    }

    private func badgeInfo(for row: JobRow) -> (String, Color) {
        if let job = row.liveJob, !job.state.isFinished {
            if job.state == .preparing { return ("Preparing", .blue) }
            if job.state == .queued { return ("Queued", .blue) }
            if let status = row.item?.status ?? job.providerStatus {
                return (status.displayLabel, .blue)
            }
            return ("Running", .blue)
        }
        if case .cancelled? = row.liveJob?.state { return ("Tracking stopped", .orange) }
        guard let item = row.item else {
            if case .failed? = row.liveJob?.state { return ("Failed", .red) }
            return ("—", .secondary)
        }
        let status = item.status
        if needsDownload(item) && !(status?.isInProgress ?? false) { return ("Ready", .green) }
        guard let status else { return ("—", .secondary) }
        if status.isInProgress { return (status.displayLabel, .blue) }
        if status == .timeout || status == .expired { return (status.displayLabel, .orange) }
        if status.needsAttention { return (status.displayLabel, .red) }
        return ("—", .secondary)
    }
}
