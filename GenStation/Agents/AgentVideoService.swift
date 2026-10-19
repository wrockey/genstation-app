#if os(macOS)
import AppKit
import AVFoundation
import Foundation
import GenStationCore

/// Durable AIML video identity wrapping the existing GET-only queue recovery path.
@MainActor
final class AgentVideoService {
    private weak var app: AppState?
    private let file: URL
    private var ledger: AgentVideoLedger
    private var storageError: String?
    var storageReady: Bool { storageError == nil }
    private var enabled = true
    private var revision = 0
    private var running = false
    private var recovering = Set<String>()
    private var lastCheck: [String: Date] = [:]

    init(app: AppState) {
        self.app = app
        file = MCPStateStore.fileURL.deletingLastPathComponent().appendingPathComponent("agent_video_jobs.json")
        do { ledger = try AgentVideoLedger.load(from: file) }
        catch { ledger = AgentVideoLedger(); storageError = "Video request storage cannot be read. Repair it before submitting video requests." }
    }
    func stop() { enabled = false; revision += 1 }
    func start() { enabled = true }

    private func update(_ id: String, _ mutate: (inout AgentVideoJob) -> Void) throws {
        guard var job = ledger.jobs[id] else { throw AgentImageError("Unknown video job.") }
        let before = job
        mutate(&job)
        job.history?.customAIMLPayload = nil
        job.history?.customAIMLEndpoint = nil
        // Local discovery/waits frequently observe unchanged state; avoid rewriting
        // the durable ledger unless the snapshot or its state actually changed.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if try encoder.encode(before) == encoder.encode(job) { return }
        do { try ledger.update(job, at: file) }
        catch {
            storageError = "Video job storage failed. Do not start another request; inspect the library and provider before retrying."
            throw error
        }
    }
    private func prepare(_ args: [String: Any], submitting: Bool) throws -> AgentVideoContract {
        let contract = try AgentVideoContract(args, submitting: submitting)
        guard let app else { throw AgentImageError("App unavailable.") }
        let live = app.aimlModelMatchSet.isEmpty ? Set(app.allAIMLModels) : app.aimlModelMatchSet
        guard live.isEmpty || live.contains(contract.model.id) || contract.model.aliases.contains(where: live.contains) else {
            throw MCPError(code: .modelUnavailable, message: "This video model is not currently served. Discover models again.")
        }
        try MCPError.requireSafePrompt(contract.prompt)
        do { try MCPImageInputs.validate(contract.inputImages) }
        catch let error as MCPImageInputError { throw MCPError(code: .inputImageInvalid, message: "Input image \(error.index): \(error.reason)") }
        if !contract.inputImages.isEmpty {
            let hosted = app.settings.imageSubmissionMethod == .imgBB && contract.model.acceptsPublicURL
            guard hosted || contract.model.acceptsBase64 else { throw AgentImageError("This model needs public image hosting. Configure ImgBB in the app or choose a model supporting data URI inputs.") }
            if hosted, !ImgBBClient.isPlausibleKey(app.settings.imgbbApiKey) { throw AgentImageError("Configure a valid ImgBB key before using public frame hosting.") }
        }
        return contract
    }
    func validate(_ args: [String: Any]) throws -> [String: Any] {
        let contract = try prepare(args, submitting: false)
        return ["valid": true, "provider": "aimlapi", "model": contract.model.id, "input_count": contract.inputImages.count,
                "credential_configured": !(app?.settings.aimlapiKey.isEmpty ?? true), "network_requests": 0,
                "approval": "individual_request", "price_status": "unknown", "storage_ready": storageError == nil]
    }
    func submit(_ args: [String: Any]) throws -> [String: Any] {
        if let storageError { throw AgentImageError(storageError) }
        guard enabled else { throw AgentImageError("Agent access is disabled.") }
        // Check replay before credentials/catalog validation: an old job must remain retrievable.
        guard let requestID = args["request_id"] as? String else { throw AgentImageError("Video request_id is required. Keep the exact arguments for reconnects.") }
        if let existing = try ledger.existing(requestID: requestID, arguments: args) { return try status(existing.id)! }
        guard !running else { throw AgentImageError("An agent video generation is already active. Poll it before starting another.") }
        let contract = try prepare(args, submitting: true)
        guard app?.settings.aimlapiKey.isEmpty == false else { throw MCPError(code: .modelUnavailable, message: "Configure your AIML API key in GenStation.") }
        let job = try ledger.register(requestID: requestID, arguments: args, at: file)
        running = true
        Task { await run(job.id, contract: contract) }
        return result(job)
    }
    private func snapshot(_ id: String, item: HistoryItem) throws {
        try update(id) { job in
            var merged = item
            merged.videoUrl = item.videoUrl ?? job.history?.videoUrl
            merged.sourceAssetURL = item.sourceAssetURL ?? job.history?.sourceAssetURL
            merged.costUSD = item.costUSD ?? job.history?.costUSD
            job.history = merged
            if let cost = item.costUSD, cost.isFinite, cost >= 0 { job.billing = "reported" }
        }
    }
    private func run(_ id: String, contract: AgentVideoContract) async {
        defer { running = false }
        let accessRevision = revision
        var queueID: UUID?
        do {
            guard let app else { throw AgentImageError("App unavailable.") }
            let method = app.settings.imageSubmissionMethod
            let hosted = !contract.inputImages.isEmpty && method == .imgBB && contract.model.acceptsPublicURL
            let details = String(data: try JSONSerialization.data(withJSONObject: contract.parameters, options: [.sortedKeys]), encoding: .utf8) ?? ""
            let approved = await AgentImageService.approve(jobID: id, requestID: ledger.jobs[id]?.requestID, requestLabel: ledger.jobs[id]?.requestLabel, createdAt: ledger.jobs[id]?.createdAt, prompt: contract.prompt,
                model: "AIML video • \(contract.model.id)\nInput images: \(contract.inputImages.count)\n\(details)",
                notice: "One video request. Price and maximum charge are unknown; provider charges may apply even after a failure or local cancellation. " + (hosted ? "Input images will be uploaded to ImgBB as public links before submission." : "Input images, if present, go directly to the selected provider."))
            guard approved, enabled, accessRevision == revision else {
                try update(id) { $0.status = "denied"; $0.message = "Denied or agent access disabled. No generation submitted." }; return
            }
            guard method == app.settings.imageSubmissionMethod else { throw AgentImageError("Image submission settings changed during approval. No generation submitted.") }
            try update(id) { $0.status = "preparing" }
            let refs = contract.inputImages.isEmpty ? [] : try await MCPImageInputs.build(from: contract.inputImages, model: contract.model, appState: app)
            guard enabled, accessRevision == revision else { throw AgentImageError("Agent access disabled before video submission. Any completed public image uploads may remain at the host.") }
            let body = try contract.body(references: refs)
            guard let url = URL(string: contract.model.generationEndpoint), let polling = contract.model.pollingEndpoint else { throw AgentImageError("Video endpoints unavailable.") }
            var request = URLRequest(url: url, timeoutInterval: 300)
            request.httpMethod = "POST"
            request.setValue("Bearer \(app.settings.aimlapiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            var queued = VideoJobRequest(urlRequest: request, modelId: contract.model.id, prompt: contract.prompt,
                pollingEndpoint: polling, submittedEndpoint: contract.model.generationEndpoint,
                submittedPayload: String(data: request.httpBody!, encoding: .utf8), apiKey: app.settings.aimlapiKey)
            queued.persistSubmissionIntent = { [weak self] in
                guard let self, self.enabled, self.revision == accessRevision else { throw CancellationError() }
                try self.update(id) { $0.status = "submitting"; $0.billing = "unknown" }
            }
            queued.recordSubmissionRejected = { [weak self] in
                try self?.update(id) { $0.status = "failed" }
            }
            queued.persistRemoteSnapshot = { [weak self] item in
                guard let self else { throw CancellationError() }
                try self.snapshot(id, item: item) // provider ID durable before local history/polling
                try self.update(id) { $0.status = item.videoUrl == nil ? "polling" : "saving" }
            }
            let qid = app.jobQueue.beginJob(modelId: contract.model.id, prompt: contract.prompt, focused: false, agentOriginated: true)
            queueID = qid
            let task = Task { try await app.jobQueue.runPreparedJob(jobID: qid, request: queued, onPosted: { [weak self] in
                // A failed linkage write must never authorize another submission.
                try? self?.update(id) { $0.historyLinked = true }
            }) }
            app.jobQueue.track(qid, task: task)
            try await task.value
            try refresh(id)
        } catch {
            if let queueID { app?.jobQueue.finishPreparing(queueID, error: error) }
            let message = ProviderFailure.redact((error as? MCPError)?.message ?? (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            try? refresh(id)
            try? update(id) { job in
                if job.history?.jobId != nil { job.status = (error is CancellationError || (error as? URLError)?.code == .cancelled) ? "cancelled" : "recoverable" }
                else if job.billing == "unknown" && job.status != "failed" { job.status = "submission_unknown" }
                else { job.status = "failed" }
                job.message = message + (job.status == "submission_unknown" ? " Submission may have reached the provider. No automatic resubmission." : "")
                if let error = error as? MCPError { job.errorCode = error.code.rawValue; job.filterReasons = error.filterReasons }
                if AIMLEndpoints.isInsufficientCredits(message) { job.errorCode = "insufficient_credits" }
            }
        }
    }

    private func currentItem(_ job: AgentVideoJob, restoreGap: Bool = false) -> HistoryItem? {
        guard let saved = job.history, let app else { return nil }
        if case .item(var current)? = app.historyState.findEntry(by: saved.id) {
            guard current.jobId == saved.jobId, current.pollingEndpoint == saved.pollingEndpoint else { return nil }
            current.videoUrl = current.videoUrl ?? saved.videoUrl
            current.sourceAssetURL = current.sourceAssetURL ?? saved.sourceAssetURL
            current.costUSD = current.costUSD ?? saved.costUSD
            return current
        }
        // Only repair the recorded provider-acceptance/history-write crash gap, not user deletion.
        if restoreGap && !job.historyLinked {
            app.historyState.history.append(.item(saved)); app.historyState.saveHistory()
            return saved
        }
        return nil
    }
    private func refresh(_ id: String) throws {
        guard let job = ledger.jobs[id], let item = currentItem(job), let app else { return }
        try snapshot(id, item: item)
        var completedManifest = job.manifest
        if item.status == .completed && item.fileExists(appState: app) && !AgentAssetAccess.revoked(item.id) {
            let directory = app.settings.outputDirectory
            let scoped = directory?.startAccessingSecurityScopedResource() ?? false
            defer { if scoped { directory?.stopAccessingSecurityScopedResource() } }
            guard let path = item.imagePath, AppStorageContext.permitsOriginal(URL(fileURLWithPath: path)) else { throw AgentImageError("Video original is unavailable in this workspace.") }
            let url = URL(fileURLWithPath: path)
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, (attributes.fileSize ?? Int.max) <= 200_000_000,
                  let type = ["mp4": "video/mp4", "m4v": "video/x-m4v", "mov": "video/quicktime", "webm": "video/webm"][url.pathExtension.lowercased()] else { throw AgentImageError("Video original must be a supported regular file within 200 MB.") }
            // Reuse durable completion metadata; get_asset verifies bytes again on handoff.
            if completedManifest == nil {
                completedManifest = AgentAssetManifest(assetID: item.id, data: try Data(contentsOf: url, options: .mappedIfSafe), mediaType: type,
                    width: nil, height: nil, model: item.modelUsed, prompt: item.prompt)
            }
        }
        try update(id) { value in
            if item.status == .completed && item.fileExists(appState: app) {
                value.status = "done"; value.message = nil; value.manifest = completedManifest
            } else if app.jobQueue.activeJob(forHistoryItem: item.id) != nil {
                value.status = item.videoUrl == nil ? "polling" : "saving"
            } else if item.status == .cancelled {
                value.status = "cancelled"; value.message = "Tracking stopped locally; the provider may continue processing and charging. Recovery is GET-only."
            } else if item.videoUrl != nil || item.sourceAssetURL != nil {
                value.status = "recoverable"; value.message = "Existing output can be downloaded again without generation. Use recover_video_job."
            } else if item.status?.isInProgress == true {
                value.status = "polling"
            } else {
                value.status = "failed"; value.message = ProviderFailure.redact(item.responseText)
            }
        }
        if ledger.jobs[id]?.status == "done", completedManifest != nil, !AgentAssetAccess.revoked(item.id) {
            if !AgentAssetAccess.shared(item.id) { AgentAssetAccess.set(item.id, shared: true) }
        }
    }
    func manifest(for id: UUID) -> AgentAssetManifest? {
        guard enabled, !AgentAssetAccess.revoked(id) else { return nil }
        return ledger.jobs.values.compactMap(\.manifest).first { $0.assetID == id }
    }
    func observation(_ id: String) throws -> AgentJobSummary? {
        guard enabled else { throw AgentImageError("Agent access is disabled.") }
        if let storageError { throw AgentImageError(storageError) }
        if ledger.jobs[id] != nil { try refresh(id) }
        return ledger.jobs[id].map { summary($0) }
    }
    func discovery() throws -> [AgentJobSummary] {
        guard enabled else { throw AgentImageError("Agent access is disabled.") }
        if let storageError { throw AgentImageError(storageError) }
        for id in Array(ledger.jobs.keys) { try refresh(id) }
        return ledger.jobs.values.map { summary($0) }
    }
    private func summary(_ job: AgentVideoJob) -> AgentJobSummary {
        AgentJobSummary(id: job.id, requestID: job.requestID, kind: "video", createdAt: job.createdAt,
            status: job.status, billing: job.billing,
            pendingApproval: AgentApprovalCenter.shared.pending.contains { $0.id == job.id },
            recoveryAvailable: job.history?.jobId != nil, label: job.requestLabel)
    }
    func status(_ id: String) throws -> [String: Any]? {
        guard let job = ledger.jobs.values.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { return nil }
        try refresh(job.id)
        guard let current = ledger.jobs[job.id] else { return nil }
        if current.status == "polling", !recovering.contains(job.id),
           let item = currentItem(current), app?.jobQueue.activeJob(forHistoryItem: item.id) == nil,
           Date().timeIntervalSince(lastCheck[job.id] ?? .distantPast) >= 5 {
            try recover(job.id)
        }
        return result(ledger.jobs[job.id] ?? current)
    }
    func recoverRequest(_ params: [String: Any]) throws -> [String: Any] {
        guard Set(params.keys) == ["job_id"], let id = params["job_id"] as? String,
              let job = ledger.jobs.values.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { throw AgentImageError("Use a known durable video job_id.") }
        try recover(job.id)
        return result(ledger.jobs[job.id]!)
    }
    private func recover(_ id: String) throws {
        guard enabled, storageError == nil, let app, let job = ledger.jobs[id],
              let original = job.history, let providerID = original.jobId, !providerID.isEmpty,
              let endpoint = original.pollingEndpoint, let url = URL(string: endpoint + providerID),
              url.scheme == "https", url.host == "api.aimlapi.com" else {
            throw AgentImageError("No recoverable provider job ID, or recovery is unavailable. Unknown submissions must not be automatically resent.")
        }
        guard let item = currentItem(job, restoreGap: true) else { throw AgentImageError("Video history item was deleted. No generation or recovery started.") }
        guard item.pollingEndpoint == original.pollingEndpoint, item.jobId == original.jobId else { throw AgentImageError("History recovery identity changed. No request sent.") }
        guard !recovering.contains(id), app.jobQueue.activeJob(forHistoryItem: item.id) == nil else { return }
        if item.status == .completed && item.fileExists(appState: app) { try refresh(id); return }
        try update(id) { $0.status = item.videoUrl == nil && item.sourceAssetURL == nil ? "polling" : "saving"; $0.historyLinked = true; $0.message = nil }
        recovering.insert(id); lastCheck[id] = Date()
        Task { [weak self] in
            guard let self else { return }
            defer { self.recovering.remove(id) }
            if item.videoUrl != nil || item.sourceAssetURL != nil {
                app.jobQueue.redownload(item)
            } else {
                await app.jobQueue.resumePendingJobs([item])
            }
            try? self.refresh(id)
        }
    }
    func restoreKnownJobs() {
        for job in ledger.jobs.values where job.status == "recoverable" {
            try? recover(job.id) // GET only; never invokes submit or uploads.
        }
    }
    private func result(_ job: AgentVideoJob) -> [String: Any] {
        var result: [String: Any] = ["job_id": job.id, "request_id": job.requestID, "kind": "video", "status": job.status,
            "billing_status": job.billing, "resubmit_safe": false, "recovery_available": job.history?.jobId != nil]
        result.merge(summary(job).json(now: Date())) { _, new in new }
        if let message = job.message { result["message"] = message }
        if let errorCode = job.errorCode { result["error_code"] = errorCode }
        if let reasons = job.filterReasons { result["filter_source"] = "genstation_local"; result["filter_reasons"] = reasons.map(\.json) }
        if let manifest = job.manifest, !AgentAssetAccess.revoked(manifest.assetID) {
            result["asset_ids"] = [manifest.assetID.uuidString]
            result["asset_manifests"] = [manifest.json]
        }
        if let providerID = job.history?.jobId { result["provider_job_id"] = providerID }
        if let cost = job.history?.costUSD, cost.isFinite, cost >= 0 { result["cost_usd"] = cost }
        if let item = currentItem(job), !AgentAssetAccess.revoked(item.id), job.status == "done", let path = item.imagePath, let app {
            guard AppStorageContext.permitsOriginal(URL(fileURLWithPath: path)) else { return result }
            result["file_path"] = path
            let directory = app.settings.outputDirectory
            let access = directory?.startAccessingSecurityScopedResource() ?? false
            defer { if access { directory?.stopAccessingSecurityScopedResource() } }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 512, height: 512)
            if let frame = try? generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil),
               let data = NSImage(cgImage: frame, size: .zero).pngData() { result["preview_png_base64"] = data.base64EncodedString() }
        }
        return result
    }
}
#endif
