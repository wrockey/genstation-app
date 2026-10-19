// JobQueue.swift
// Central queue for remote async generation jobs (AIML video submit + poll + download).
//
// The queue owns everything from the generation POST onward: create the pending
// history item, poll the job, download and save the result. Request-body building
// (image uploads, privacy notices) stays with the form code in
// ContentView+Generation.swift, which hands the queue a fully built URLRequest.
//
// WS-7 (MCP server) binds to this interface: submit(_:) -> JobID, cancel(_:),
// status(_:), and the observable `jobs` list / `onJobEvent` stream.
import Foundation
import SwiftUI
import UserNotifications
import GenStationCore

// MARK: - Job model

/// A submission for the job queue: fully built HTTP request plus the metadata the
/// poll/download pipeline needs.
struct VideoJobRequest {
    let urlRequest: URLRequest
    let modelId: String
    let prompt: String
    let pollingEndpoint: String
    let submittedEndpoint: String
    let submittedPayload: String?
    let apiKey: String
    var provider: Provider = .aimlapi
    var requiresUserReview: Bool = false
    /// MCP durability hooks; UI callers leave these nil. Fail closed before POST or polling.
    var persistSubmissionIntent: (() throws -> Void)? = nil
    var persistRemoteSnapshot: ((HistoryItem) throws -> Void)? = nil
    var recordSubmissionRejected: (() throws -> Void)? = nil
}

enum VideoJobState: Equatable {
    case preparing   // uploading input images / building the request (pre-POST)
    case queued      // submitted to the provider; waiting for a poll slot
    case running     // actively polling the provider
    case completed
    case failed(String)
    case cancelled

    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        case .preparing, .queued, .running: return false
        }
    }
}

struct VideoJob: Identifiable {
    enum Kind { case generation, resumeCheck, redownload }
    let id: UUID
    let kind: Kind
    let modelId: String
    let prompt: String
    let createdAt: Date = Date()
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
    var state: VideoJobState = .queued
    var providerStatus: GenerationStatus? = nil   // last status the poll returned
    var historyItemID: UUID? = nil      // set once the pending history item exists
    var agentOriginated: Bool = false   // submitted via the MCP server (WS-7)
}

/// ContentView-coupled operations the job pipeline needs (dialogs, file saving,
/// success toast). Registered once from ContentView.performOnAppear.
struct JobQueueBridge {
    let showRetryDialog: (String) async -> Bool
    /// data, prompt, modelUsed -> saved path + whether the configured output
    /// folder was NOT used (fallback to Downloads/tmp)
    let saveGeneratedMedia: (Data, String, String?) -> (path: String, usedFallback: Bool)?
    let saveRecoveredImage: (Data, String, String?, Provider) -> (path: String, usedFallback: Bool)?
    let detectVideoHasAudio: (String) async -> Bool
    let notifyRecovered: (String) -> Void
}

// MARK: - JobQueue

@MainActor
final class JobQueue: ObservableObject {
    private let transport = GenerationTransport()
    @Published var pendingReview: VideoReview?
    private var reviewContinuation: CheckedContinuation<Bool, Never>?

    func resolveReview(_ approved: Bool) {
        let continuation = reviewContinuation
        reviewContinuation = nil
        pendingReview = nil
        continuation?.resume(returning: approved)
    }

    private func review(_ request: VideoJobRequest, jobID: UUID) async -> Bool {
        guard reviewContinuation == nil else { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                reviewContinuation = continuation
                pendingReview = VideoReview(id: jobID, request: request)
            }
        } onCancel: {
            Task { @MainActor in
                if self.pendingReview?.id == jobID { self.resolveReview(false) }
            }
        }
    }

    @Published private(set) var jobs: [VideoJob] = []

    /// Remote async (server-side polled) jobs only — each is a lightweight
    /// polling loop, so several can run at once. Local/synchronous generation
    /// (ComfyUI, Gemini, Grok, AIML image) stays on the existing serial
    /// isLoading path — that path is the serial lane.
    var maxConcurrent: Int = 4 {
        didSet {
            scheduler.maxConcurrent = maxConcurrent
            resumeWaitersIfPossible()
        }
    }

    private(set) weak var appState: AppState?
    private var bridge: JobQueueBridge?

    /// Fires on every job state transition (queued → running → finished).
    var onJobEvent: ((VideoJob) -> Void)?

    private var scheduler = JobSchedulerCore(maxConcurrent: 4)  // keep in sync with maxConcurrent's default
    /// Per-job cancellation, type-erased so both throwing (retry) and
    /// error-handled (submitVideoPrompt) driving tasks can be tracked uniformly.
    private var jobCancellers: [UUID: () -> Void] = [:]
    private var runningCount = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    /// The one job allowed to write the shared response area
    /// (outputTexts/outputImages/outputPaths/errorItem/stage): the most recently
    /// submitted job. Concurrent non-focused jobs surface through their own
    /// notification + Jobs panel row, never clobbering the display.
    private(set) var focusedJobID: UUID?

    nonisolated init() {}

    /// Wires the queue to app state and the ContentView-coupled operations.
    /// Called once at launch (ContentView.performOnAppear).
    func configure(appState: AppState, bridge: JobQueueBridge) {
        self.appState = appState
        self.bridge = bridge

        // Periodic age scan (20h warning / 24h expiry) for long-running sessions;
        // foregrounding also triggers a scan via checkPendingVideoJobs.
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanPendingJobAges() }
        }
    }

    // MARK: Interface

    /// Creates a generation job in `.preparing` and returns its ID. The caller
    /// (submitVideoPrompt) then runs the preparing work — input-image upload +
    /// payload build — and hands the built request to
    /// `runPreparedJob(jobID:request:onPosted:)`. Splitting creation from the run
    /// lets the Jobs panel show and cancel the job during the upload phase, before
    /// any HTTP request exists. The new job becomes the focused one — unless
    /// `focused` is false (MCP/agent jobs, which must never own the shared
    /// response display).
    func beginJob(modelId: String, prompt: String, focused: Bool = true, agentOriginated: Bool = false) -> UUID {
        let job = VideoJob(id: UUID(), kind: .generation, modelId: modelId, prompt: prompt,
                           state: .preparing, agentOriginated: agentOriginated)
        appendJob(job)
        if focused { focusedJobID = job.id }
        emit(job.id)
        return job.id
    }

    /// Associates the driving task with a job so `cancel(_:)` can stop it during
    /// any phase (preparing upload, POST, or polling).
    func track<Failure>(_ id: UUID, task: Task<Void, Failure>) {
        jobCancellers[id] = { task.cancel() }
    }

    /// Runs a job whose record already exists (created via `beginJob`).
    ///
    /// The POST happens immediately — it is NOT gated by the concurrency cap — so
    /// the provider job is created server-side and the pending history item (with
    /// its poll URL) is persisted right away. This consumes any ImgBB input-image
    /// URLs at POST time (they can't expire while queued) and makes every posted
    /// job recoverable via the resume path. `onPosted` fires once the history item
    /// is written (the caller clears the form there — finding B). Only the polling
    /// phase acquires a concurrency slot.
    func runPreparedJob(jobID: UUID, request: VideoJobRequest, onPosted: @escaping () -> Void) async throws {
        do {
            if request.provider == .aimlapi,
               let issue = ReleaseModelPolicy.validateRequest(modelID: request.modelId, task: .video,
                   customPayload: request.submittedPayload, endpoint: request.submittedEndpoint) {
                throw GenerationError.apiError(issue)
            }
            if request.requiresUserReview || jobs.first(where: { $0.id == jobID })?.agentOriginated != true {
                let reviewStarted = Date()
                guard await review(request, jobID: jobID) else { throw CancellationError() }
                if Date().timeIntervalSince(reviewStarted) > 480,
                   let data = request.urlRequest.httpBody,
                   let body = try? JSONSerialization.jsonObject(with: data),
                   VideoSubmissionSummary.containsHostedInput(body) {
                    throw GenerationError.apiError("The hosted input may have expired while reviewing. Reattach the frames and prepare a new review.")
                }
            }
            try Task.checkCancellation()
            try await runGeneration(jobID: jobID, request: request, onPosted: onPosted)
            finishJob(jobID, state: .completed)
        } catch {
            if isCancellation(error) {
                finishJob(jobID, state: .cancelled)
                throw CancellationError()
            }
            let networkError = error as NSError
            if networkError.domain == NSURLErrorDomain {
                let phase: ProviderFailure.Phase = jobs.first(where: { $0.id == jobID })?.historyItemID == nil ? .submission : .polling
                let diagnosis = ProviderFailure.classify(provider: request.provider, phase: phase, transportCode: networkError.code)
                finishJob(jobID, state: .failed(diagnosis.message))
                throw GenerationError.apiError(diagnosis.message)
            }
            let message = (error as? GenerationError)?.errorDescription ?? error.localizedDescription
            finishJob(jobID, state: .failed(message))
            throw error
        }
    }

    /// Submits a fully-built request as a new job on a detached task (used by the
    /// Jobs panel's retry, where there is no separate preparing phase, and by the
    /// MCP service with focused: false). Returns immediately with the job ID.
    @discardableResult
    func submit(_ request: VideoJobRequest, focused: Bool = true, agentOriginated: Bool = false) -> UUID {
        let jobID = beginJob(modelId: request.modelId, prompt: request.prompt,
                             focused: focused, agentOriginated: agentOriginated)
        let task = Task { [weak self] in
            guard let self else { return }
            try await self.runPreparedJob(jobID: jobID, request: request, onPosted: {})
        }
        track(jobID, task: task)
        return jobID
    }

    /// Cancels a preparing, queued, or running job.
    func cancel(_ id: UUID) {
        jobCancellers[id]?()
    }

    /// Terminates a job that failed or was cancelled during the preparing phase —
    /// before `runPreparedJob` took over its lifecycle (e.g. an input-image upload
    /// or payload-build error). No-op if the job already reached a terminal state
    /// (the run path finishes its own jobs), so callers can invoke it defensively.
    func finishPreparing(_ id: UUID, error: Error?) {
        guard let job = jobs.first(where: { $0.id == id }), !job.state.isFinished else { return }
        if let error = error, !isCancellation(error) {
            let message = (error as? GenerationError)?.errorDescription ?? error.localizedDescription
            finishJob(id, state: .failed(message))
        } else {
            finishJob(id, state: .cancelled)
        }
    }

    /// User cancellation surfaces as either `CancellationError` (Task.cancel) or
    /// `URLError.cancelled` (an in-flight URLSession task being torn down). Treat
    /// both identically everywhere in the queue so a user cancel never becomes a
    /// failure notification or a retry dialog.
    nonisolated func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    func status(_ id: UUID) -> VideoJobState? {
        jobs.first(where: { $0.id == id })?.state
    }

    /// True while any generation job is queued or running.
    var hasActiveGenerationWork: Bool {
        jobs.contains { $0.kind == .generation && !$0.state.isFinished }
    }

    /// The live (unfinished) job backing a history item, if any.
    func activeJob(forHistoryItem id: UUID) -> VideoJob? {
        jobs.first { $0.historyItemID == id && !$0.state.isFinished }
    }

    // MARK: Panel actions (retry / re-download)

    /// A failed/expired job can be retried when its exact submission is stored.
    ///
    /// It deliberately does **not** check the polling endpoint any more. The old check resolved a
    /// missing one through the registry, whose unregistered-id branch synthesized a per-provider
    /// poll URL — the same synthesis `RegistryEndpointTests` shows disagreeing with the catalog for
    /// most video models. Dropping it means a job with no persisted `pollingEndpoint` still offers
    /// Retry and `retry(_:)` tells the user why it cannot proceed, instead of the button silently
    /// vanishing.
    nonisolated static func canRetry(_ item: HistoryItem) -> Bool {
        guard item.task != .image, let payload = item.customAIMLPayload,
              let data = payload.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil,
              let endpoint = item.customAIMLEndpoint,
              URL(string: endpoint) != nil else { return false }
        return true
    }

    /// Re-submits a job from the exact payload/endpoint stored on its history
    /// item. Produces a fresh job (and pending history item); the old item keeps
    /// its failed state. Note: ImgBB-hosted input images expire (~10 min), so a
    /// late retry of an i2v job may fail server-side.
    @discardableResult
    func retry(_ item: HistoryItem) -> UUID? {
        guard let appState = self.appState,
              let payload = item.customAIMLPayload,
              let body = payload.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: body)) != nil,
              let endpoint = item.customAIMLEndpoint,
              let url = URL(string: endpoint) else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: body), VideoSubmissionSummary.containsHostedInput(json) {
            HistoryDraftCoordinator.prepareVideoRetry(item, app: appState)
            return nil
        }
        if item.mode == .grok {
            guard endpoint == GrokVideoClient.generationsURL.absoluteString,
                  item.pollingEndpoint == GrokVideoClient.pollingEndpoint,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  json["model"] as? String == GrokVideoClient.model else {
                appState.errorItem = AlertError(message: "This Grok video request cannot be retried. Create a new video from the form.", fullMessage: nil)
                return nil
            }
        }
        if item.mode != .grok, let issue = ReleaseModelPolicy.validateRequest(modelID: item.modelUsed ?? "", task: .video,
                                                          customPayload: payload, endpoint: endpoint) {
            appState.errorItem = AlertError(message: issue, fullMessage: nil)
            return nil
        }
        guard let pollingEndpoint = item.pollingEndpoint else {
            // Reachable as of this change: `canRetry` no longer gates on the polling endpoint, so
            // a job submitted before the endpoint was persisted lands here and is told, rather than
            // being retried against a synthesized URL that is wrong for most video models.
            appState.errorItem = AlertError(
                message: "This job can no longer be retried — its polling endpoint was not recorded.",
                fullMessage: nil)
            return nil
        }

        // Same headers the video submit path uses
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(item.mode == .grok ? appState.settings.grokApiKey : appState.settings.aimlapiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.httpBody = body

        // Preserve agent provenance across retry so badges, ledger reconciliation,
        // and dialog gating survive: an agent-originated job stays agent-originated
        // and non-focused (it must never own the shared response display).
        let wasAgent = item.agentGenerated == true
        return submit(VideoJobRequest(
            urlRequest: request,
            modelId: item.modelUsed ?? "AI/ML video",
            prompt: item.prompt,
            pollingEndpoint: pollingEndpoint,
            submittedEndpoint: endpoint,
            submittedPayload: payload,
            apiKey: item.mode == .grok ? appState.settings.grokApiKey : appState.settings.aimlapiKey,
            provider: item.mode ?? .aimlapi,
            requiresUserReview: true
        ), focused: !wasAgent, agentOriginated: wasAgent)
    }

    /// Re-downloads a completed-but-undownloaded video (source URL persisted on
    /// the history item). Tracked as a lightweight job record for panel feedback.
    func redownload(_ item: HistoryItem) {
        guard activeJob(forHistoryItem: item.id) == nil, let videoUrlStr = item.videoUrl ?? item.sourceAssetURL else { return }
        let record = VideoJob(id: UUID(), kind: .redownload, modelId: item.modelUsed ?? "AI/ML video",
                              prompt: item.prompt, startedAt: Date(), state: .running, historyItemID: item.id)
        appendJob(record)
        Task { [weak self] in
            guard let self = self else { return }
            let ok = await self.downloadAndFinalize(item: item, videoUrlStr: videoUrlStr, recoveredToast: false)
            self.finishJob(record.id, state: ok ? .completed : .failed("Download failed"))
        }
    }

    func beginAssetRead(_ item: HistoryItem) -> UUID {
        let record = VideoJob(id: UUID(), kind: .redownload, modelId: item.modelUsed ?? "Image",
                              prompt: item.prompt, state: .running, historyItemID: item.id)
        appendJob(record)
        return record.id
    }

    func finishAssetRead(_ id: UUID, saved: Bool) {
        finishJob(id, state: saved ? .completed : .failed("Download or save interrupted. Download again to recover the existing asset."))
    }

    // MARK: Expiry monitoring (silent 24h expiry fix)

    /// AIML server-side results are gone after ~24h; warn at 20h.
    static let maxJobAge: TimeInterval = 24 * 60 * 60
    static let expiryWarningAge: TimeInterval = 20 * 60 * 60
    private static let expiryWarnedKey = "videoJobExpiryWarnedIDs"
    private var expiryTimer: Timer?

    /// Marks >24h pending jobs expired (notifying) and posts a one-time warning
    /// for jobs approaching expiry (~20h). Runs on foreground scans
    /// (checkPendingVideoJobs) and a periodic timer for long-running sessions.
    func scanPendingJobAges() {
        guard let appState = self.appState else { return }
        let now = Date()
        var warned = Set(AppStorageContext.defaults.stringArray(forKey: Self.expiryWarnedKey) ?? [])
        var warnedChanged = false

        for entry in appState.historyState.history {
            guard case .item(let item) = entry,
                  let jobId = item.jobId, !jobId.isEmpty,
                  let status = item.status, status.isInProgress,
                  item.mode == .aimlapi else { continue }

            let age = now.timeIntervalSince(item.date)
            if age > Self.maxJobAge {
                updateHistoryItemStatus(id: item.id, status: .expired,
                    responseText: "Video job expired (older than 24 hours). Job ID: \(jobId)")
                JobNotifier.post(title: "Video job expired",
                                 body: "The provider no longer has the result. \(JobNotifier.snippet(item.prompt))")
            } else if age > Self.expiryWarningAge && !warned.contains(item.id.uuidString) {
                warned.insert(item.id.uuidString)
                warnedChanged = true
                JobNotifier.post(title: "Video job expiring soon",
                                 body: "Still pending after 20 hours; the provider discards results at 24h. \(JobNotifier.snippet(item.prompt))")
            }
        }

        if warnedChanged {
            // Cap remembered IDs so the list doesn't grow forever
            AppStorageContext.defaults.set(Array(warned.suffix(100)), forKey: Self.expiryWarnedKey)
        }
    }

    // MARK: Slot gate (concurrency cap)

    private func acquireSlot(_ id: UUID) async throws {
        try Task.checkCancellation()
        if scheduler.slotsAvailable(running: runningCount) > 0 && waiters.isEmpty {
            runningCount += 1
            return
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.failWaiter(id) }
        }
    }

    private func releaseSlot() {
        runningCount -= 1
        resumeWaitersIfPossible()
    }

    private func resumeWaitersIfPossible() {
        while scheduler.slotsAvailable(running: runningCount) > 0, !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            runningCount += 1
            waiter.continuation.resume()
        }
    }

    private func failWaiter(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    // MARK: Job record bookkeeping

    private func appendJob(_ job: VideoJob) {
        jobs.append(job)
        // Trim old finished records so the list doesn't grow unbounded.
        let finished = jobs.filter { $0.state.isFinished }
        if finished.count > 50 {
            let cutoff = finished.count - 50
            var removed = 0
            jobs.removeAll { job in
                guard removed < cutoff, job.state.isFinished else { return false }
                removed += 1
                return true
            }
        }
    }

    private func updateJob(_ id: UUID, _ mutate: (inout VideoJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }

    private func finishJob(_ id: UUID, state: VideoJobState) {
        updateJob(id) { $0.state = state; $0.finishedAt = Date() }
        emit(id)

        // On cancel, stamp a terminal "cancelled" status on the pending history item
        // (if the POST already created one) so it neither lists as active nor gets
        // resurrected by a resume scan. If the focused job was cancelled, drop the
        // focus so a later concurrent job may own the display.
        if case .cancelled = state {
            if let job = jobs.first(where: { $0.id == id }), let itemID = job.historyItemID {
                updateHistoryItemStatus(id: itemID, status: .cancelled, responseText: "Tracking stopped locally. The provider may continue processing and billing.")
            }
            if focusedJobID == id { focusedJobID = nil }
        }

        // User notification on completion/failure of real generation jobs
        if let job = jobs.first(where: { $0.id == id }), job.kind == .generation {
            switch state {
            case .completed:
                JobNotifier.post(title: "Video ready", body: JobNotifier.snippet(job.prompt))
            case .failed(let message):
                JobNotifier.post(title: "Video generation failed", body: message)
            case .preparing, .cancelled, .queued, .running:
                break
            }
        }
    }

    private func emit(_ id: UUID) {
        if let job = jobs.first(where: { $0.id == id }) {
            onJobEvent?(job)
        }
    }

    // MARK: - Generation pipeline (moved verbatim from ContentView.asyncGenerate)

    /// POST → create pending history item → (fire onPosted) → acquire poll slot →
    /// poll → download → save.
    ///
    /// The POST and the pending-history-item write happen immediately, before any
    /// concurrency-slot acquisition, so the provider job is created and persisted
    /// (with its poll URL) the moment the user submits — input-image URLs are
    /// consumed at POST time and every posted job is resumable. Only the polling
    /// phase is capped. Shared response-area writes are gated to the focused job.
    private func runGeneration(jobID: UUID, request videoRequest: VideoJobRequest, onPosted: @escaping () -> Void) async throws {
        guard let appState = self.appState, let bridge = self.bridge else {
            throw GenerationError.apiError("Job queue is not configured.")
        }
        if videoRequest.provider == .aimlapi,
           let issue = ReleaseModelPolicy.validateRequest(modelID: videoRequest.modelId, task: .video,
               customPayload: videoRequest.submittedPayload, endpoint: videoRequest.submittedEndpoint) {
            throw GenerationError.apiError(issue)
        }
        let finalPrompt = videoRequest.prompt
        let selectedModel = videoRequest.modelId
        let submittedPayload = videoRequest.submittedPayload
        let submittedEndpoint = videoRequest.submittedEndpoint
        let request = videoRequest.urlRequest

        // Only the focused job may write the shared response area; a non-focused
        // concurrent job surfaces through its notification + Jobs panel row.
        func display(_ write: () -> Void) { if focusedJobID == jobID { write() } }

        // Use custom session for large video payloads to avoid QUIC packet fragmentation issues
        let videoSessionConfig = URLSessionConfiguration.default
        videoSessionConfig.timeoutIntervalForRequest = 600  // 10 minutes for large uploads
        videoSessionConfig.timeoutIntervalForResource = 900  // 15 minutes total
        videoSessionConfig.httpAdditionalHeaders = [
            "Connection": "keep-alive"
        ]
        let videoSession = URLSession(configuration: videoSessionConfig)

        try Task.checkCancellation()
        let (data, response) = try await AgentVideoSubmission.perform(request, jobID: jobID, transport: transport,
            session: videoSession, persistIntent: { try videoRequest.persistSubmissionIntent?() })
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            try videoRequest.recordSubmissionRejected?()
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GenerationError.apiError(videoRequest.provider == .aimlapi ? AIMLEndpoints.friendlyError(status: status, body: data) : ProviderFailure.message(provider: videoRequest.provider, status: status, body: data, phase: .submission))
        }
        Log.debug("Initial response: HTTP \(httpResponse.statusCode), \(data.count) bytes")

        let responseDecoded: AIMLEndpoints.VideoGenerationResponse
        do {
            responseDecoded = try JSONDecoder().decode(AIMLEndpoints.VideoGenerationResponse.self, from: videoRequest.provider == .grok ? GrokVideoClient.normalizedResponse(data, submission: true) : data)
        } catch {
            Log.debug("Failed to decode initial response: \(error.localizedDescription), body: \(String(data: data, encoding: .utf8) ?? "No data")")
            throw GenerationError.apiError("Failed to decode response: \(error.localizedDescription)")
        }

        if let error = responseDecoded.error {
            try videoRequest.recordSubmissionRejected?()
            let formattedError = OpenAICompatible.formatError(error)
            display {
                appState.ui.outputTexts = [formattedError]
                appState.ui.outputImages = []
                appState.ui.outputPaths = []
            }
            throw GenerationError.apiError(error.message ?? "Unknown error")
        }

        guard let genId = responseDecoded.id else {
            throw GenerationError.apiError("No generation ID returned")
        }

        let pollingEndpoint = videoRequest.pollingEndpoint
        let pollUrlString = pollingEndpoint + genId  // Assuming it ends with ?generation_id=

        let isAgentJob = jobs.first(where: { $0.id == jobID })?.agentOriginated == true
        let pendingItem = HistoryItem(
            prompt: finalPrompt,
            responseText: "Video generation queued with model: \(selectedModel). Job ID: \(genId). Poll URL: \(pollUrlString). Check back later or retrieve manually.",
            imagePath: nil,
            date: Date(),
            mode: videoRequest.provider,
            task: .video,
            workflowName: nil,
            modelUsed: selectedModel,
            batchId: nil,
            indexInBatch: nil,
            totalInBatch: nil,
            jobId: genId,
            status: .queued,
            pollingEndpoint: pollingEndpoint,
            customAIMLPayload: submittedPayload,
            customAIMLEndpoint: submittedEndpoint,
            agentGenerated: isAgentJob ? true : nil
        )
        try videoRequest.persistRemoteSnapshot?(pendingItem)
        appState.historyState.history.append(.item(pendingItem))
        appState.ui.sessionGeneratedIDs.append(pendingItem.id)  // Track in session gallery
        appState.historyState.saveHistory()
        updateJob(jobID) { $0.historyItemID = pendingItem.id }

        // The provider job now exists and is persisted (poll URL on the history
        // item): safe to free the form for the next prompt (finding B).
        onPosted()

        display {
            appState.ui.outputTexts = ["Video queued with ID: \(genId)."]
            appState.ui.outputImages = [nil]
            appState.ui.outputPaths = [nil]
            appState.ui.currentOutputIndex = 0
        }

        guard let pollUrl = URL(string: pollUrlString) else {
            throw GenerationError.invalidURL
        }

        // Concurrency cap applies to the POLLING phase only (the POST above already
        // created the server-side job). While waiting for a slot the job sits in
        // .queued; if the app is killed the resume path picks it up from history.
        updateJob(jobID) { $0.state = .queued }
        emit(jobID)
        try await acquireSlot(jobID)
        defer { releaseSlot() }
        updateJob(jobID) { $0.state = .running; $0.startedAt = Date() }
        emit(jobID)

        var videoUrlStr: String?
        let startTime = Date()
        let timeoutSeconds = 1800
        var networkErrorCount = 0

        // Honest progress only: elapsed + typical range + provider status
        // (the old pollCount/60 percent was fabricated; WS-3 stage 3)
        display {
            appState.ui.videoGenerationStage = "Starting video generation..."
        }

        while Date().timeIntervalSince(startTime) < TimeInterval(timeoutSeconds) {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 10_000_000_000)

            var pollRequest = URLRequest(url: pollUrl, timeoutInterval: 120)
            pollRequest.httpMethod = "GET"
            pollRequest.addValue("Bearer \(videoRequest.apiKey)", forHTTPHeaderField: "Authorization")
            pollRequest.addValue("application/json", forHTTPHeaderField: "Accept")
            pollRequest.addValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")

            // Network error resilience - retry on connection failures
            let pollData: Data
            let pollResponse: URLResponse
            do {
                (pollData, pollResponse) = try await GenerationTransport.recover(pollRequest)
                networkErrorCount = 0  // Reset on success
            } catch {
                // A user cancel (URLError.cancelled) is not a network failure — never
                // count it toward the retry dialog; unwind as cancellation.
                if isCancellation(error) { throw CancellationError() }
                networkErrorCount += 1
                Log.debug("Video poll network error (\(networkErrorCount)): \(error.localizedDescription)")

                // Agent-originated jobs never show interactive dialogs. Retry
                // silently up to 3 times (the 10s poll interval is the backoff),
                // then fail with a structured error the agent reads via
                // get_job_status.
                if isAgentJob {
                    if networkErrorCount > 3 {
                        let failMessage = "Connection lost while polling (gave up after 3 retries): \(error.localizedDescription)"
                        if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
                           case .item(var item) = appState.historyState.history[index] {
                            item.status = .failed
                            item.responseText = "Video generation failed: \(failMessage)"
                            appState.historyState.history[index] = .item(item)
                            appState.historyState.saveHistory()
                        }
                        throw GenerationError.apiError(failMessage)
                    }
                    continue
                }

                // After 3 consecutive network errors, offer retry dialog
                if networkErrorCount >= 3 {
                    display {
                        appState.ui.videoGenerationStage = "Connection lost, waiting to retry..."
                    }
                    let shouldRetry = await bridge.showRetryDialog("Lost connection while polling video status:\n\(error.localizedDescription)\n\nRetry?")
                    if !shouldRetry {
                        // Mark as failed and exit
                        if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
                           case .item(var item) = appState.historyState.history[index] {
                            item.status = .failed
                            item.responseText = "Video generation failed: Connection lost"
                            appState.historyState.history[index] = .item(item)
                            appState.historyState.saveHistory()
                        }
                        display { appState.ui.videoGenerationStage = "" }
                        throw GenerationError.apiError("Connection lost during video polling")
                    }
                    networkErrorCount = 0
                }
                // Wait and retry
                continue
            }
            let pollStatusCode = (pollResponse as? HTTPURLResponse)?.statusCode ?? -1
            Log.debug("Poll response: HTTP \(pollStatusCode), \(pollData.count) bytes")

            guard let httpPollResponse = pollResponse as? HTTPURLResponse,
                  (200...299).contains(httpPollResponse.statusCode) else {
                let bodyString = String(data: pollData, encoding: .utf8) ?? "No body"
                Log.debug("Polling failed with body: \(bodyString)")
                let status = (pollResponse as? HTTPURLResponse)?.statusCode ?? -1
                let errorMessage = bodyString.contains("Invalid id") || bodyString.contains("Id not found") ?
                "Invalid or expired job ID: \(genId). Please restart the generation." : "Poll status \(status): \(bodyString)"
                if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
                   case .item(var updatedItem) = appState.historyState.history[index] {
                    updatedItem.status = .failed
                    updatedItem.responseText = "Video generation failed: \(errorMessage) with model: \(selectedModel). Job ID: \(genId)."
                    appState.historyState.history[index] = .item(updatedItem)
                    appState.historyState.saveHistory()
                    display {
                        appState.ui.outputTexts = ["Video generation failed: \(errorMessage) with ID: \(genId)."]
                        appState.ui.outputImages = [nil]
                        appState.ui.outputPaths = [nil]
                        appState.errorItem = AlertError(message: "Video generation failed: \(errorMessage)", fullMessage: nil)
                    }
                }
                throw GenerationError.apiError(errorMessage)
            }

            var pollResponseOptional: AIMLEndpoints.VideoPollResponse?

            do {
                pollResponseOptional = try JSONDecoder().decode(AIMLEndpoints.VideoPollResponse.self, from: videoRequest.provider == .grok ? GrokVideoClient.normalizedResponse(pollData) : pollData)
            } catch {
                // Try to decode as error response
                if let errorResponse = try? JSONDecoder().decode(AIMLEndpoints.VideoErrorResponse.self, from: pollData),
                   let error = errorResponse.error {

                    let code = error.code.flatMap { "\($0)" } ?? "unknown"
                    let message = error.message ?? "Unknown server error"
                    Log.debug("Sora rejected: [\(code)] \(message)")

                    if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
                       case .item(var item) = appState.historyState.history[index] {
                        item.status = code == "moderation_blocked" ? .blocked : .failed
                        item.responseText = "Blocked: \(message)"
                        appState.historyState.history[index] = .item(item)
                        appState.historyState.saveHistory()
                    }
                    display {
                        let userMessage = code == "moderation_blocked"
                        ? "Sora blocked this generation (content moderation)"
                        : "Generation failed: \(message)"

                        appState.ui.outputTexts = [userMessage]
                        appState.ui.outputImages = [nil]
                        appState.ui.outputPaths = [nil]
                        appState.errorItem = AlertError(
                            message: "Generation blocked",
                            fullMessage: "Code: \(code)\nMessage: \(message)\n\nTip: Use safe subjects like robots, animals, toys, or landscapes."
                        )
                    }
                    throw GenerationError.apiError("Generation blocked: \(message)")
                }

                let body = String(data: pollData, encoding: .utf8) ?? "binary"
                Log.debug("Failed to decode poll response: \(error)\nBody: \(body)")
                throw GenerationError.apiError("Invalid server response")
            }

            // Successfully decoded normal response
            guard let pollResponse = pollResponseOptional else {
                throw GenerationError.apiError("No poll response")
            }

            // Handle legacy error field
            if let error = pollResponse.error {
                let message = error.message ?? "Unknown error"
                if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
                   case .item(var item) = appState.historyState.history[index] {
                    item.status = .failed
                    item.responseText = "Failed: \(message)"
                    appState.historyState.history[index] = .item(item)
                    appState.historyState.saveHistory()
                }
                display {
                    appState.ui.outputTexts = ["Generation failed: \(message)"]
                    appState.ui.outputImages = [nil]
                    appState.errorItem = AlertError(message: "Generation failed", fullMessage: message)
                }
                throw GenerationError.apiError(message)
            }

            // Extract status — now safe
            let status = pollResponse.status
            let parsedStatus = GenerationStatus(legacy: status)
            Log.debug("Poll status: '\(status)', video url: \(pollResponse.video?.url ?? "nil")")
            updateJob(jobID) { $0.providerStatus = parsedStatus }

            // Update UI/history
            if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
               case .item(var item) = appState.historyState.history[index] {
                item.status = parsedStatus

                switch parsedStatus {
                case .waiting, .queued:
                    item.responseText = "Video generation \(status)… (Job ID: \(genId))"
                    display {
                        appState.ui.outputTexts = ["Video \(status)…"]
                        appState.ui.videoGenerationStage = "Waiting in queue..."
                    }
                case .generating, .active, .processing:
                    item.responseText = "Video generation \(status)… (Job ID: \(genId))"
                    display {
                        appState.ui.outputTexts = ["Video \(status)…"]
                        appState.ui.videoGenerationStage = "Rendering video..."
                    }
                case .completed:
                    item.responseText = "Video completed — downloading…"
                    display {
                        appState.ui.outputTexts = ["Video completed — downloading…"]
                        appState.ui.videoGenerationStage = "Downloading video..."
                    }
                default:
                    item.status = .failed
                    item.responseText = "Video failed (status: \(status))"
                    display {
                        appState.ui.outputTexts = ["Video generation failed (\(status))"]
                        appState.ui.videoGenerationStage = ""
                        appState.errorItem = AlertError(message: "Generation failed", fullMessage: "Status: \(status)")
                    }
                }
                appState.historyState.history[index] = .item(item)
                appState.historyState.saveHistory()
            }

            // Continue polling while the provider reports an in-progress status.
            if parsedStatus.isInProgress {
                continue
            }

            if parsedStatus == .completed {
                videoUrlStr = pollResponse.video?.url
                let videoCost = ProviderChargeEvidence.observe(provider: videoRequest.provider, data: pollData, httpStatus: pollStatusCode).evidence?.amount.displayUSD
                // Persist the source URL (and actual cost) immediately — before downloading —
                // so an expensive video stays recoverable even if the download fails or the
                // app is quit.
                if videoUrlStr != nil || videoCost != nil {
                    var recoverySnapshot = pendingItem
                    recoverySnapshot.videoUrl = videoUrlStr
                    recoverySnapshot.costUSD = videoCost
                    recoverySnapshot.status = .completed
                    try videoRequest.persistRemoteSnapshot?(recoverySnapshot)
                    await MainActor.run {
                        if let videoCost = videoCost { appState.ui.sessionSpendUSD += videoCost }
                        if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
                           case .item(var item) = appState.historyState.history[index] {
                            if let u = videoUrlStr { item.videoUrl = u }
                            if let videoCost = videoCost { item.costUSD = videoCost }
                            appState.historyState.history[index] = .item(item)
                            appState.historyState.saveHistory()
                        }
                    }
                }
            } else {
                throw GenerationError.apiError("Generation ended with status: \(status)")
            }

            break
        }

        // Check if we exited due to timeout
        if videoUrlStr == nil && Date().timeIntervalSince(startTime) >= TimeInterval(timeoutSeconds) {
            let timeoutMinutes = timeoutSeconds / 60
            if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
               case .item(var item) = appState.historyState.history[index] {
                item.status = .timeout
                item.responseText = "Video generation timed out after \(timeoutMinutes) minutes. Job ID: \(genId)"
                appState.historyState.history[index] = .item(item)
                appState.historyState.saveHistory()
            }
            display {
                appState.ui.outputTexts = ["Video generation timed out after \(timeoutMinutes) minutes"]
                appState.errorItem = AlertError(
                    message: "Video generation timed out",
                    fullMessage: "The video generation took longer than \(timeoutMinutes) minutes. The job may still be processing on the server.\n\nJob ID: \(genId)\n\nUse Check status in Jobs to retrieve the existing job. Stopping tracking does not cancel provider billing."
                )
                appState.ui.videoGenerationStage = ""
            }
            throw GenerationError.apiError("Video generation timed out after \(timeoutSeconds / 60) minutes")
        }

        guard let videoUrlStr = videoUrlStr,
              let videoUrl = URL(string: videoUrlStr) else {
            if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
               case .item(var item) = appState.historyState.history[index] {
                item.status = .failed
                item.responseText = "Failed: No video URL returned"
                appState.historyState.history[index] = .item(item)
                appState.historyState.saveHistory()
            }
            display {
                appState.ui.outputTexts = ["Error: No video URL received"]
                appState.errorItem = AlertError(message: "No video URL", fullMessage: "The server reported completion but did not provide a video URL.\n\nJob ID: \(genId)")
                appState.ui.videoGenerationStage = ""
            }
            throw GenerationError.apiError("No video URL")
        }

        // Video download with retry support
        var videoData: Data?
        var downloadRetryCount = 0
        let maxDownloadRetries = 3

        while downloadRetryCount <= maxDownloadRetries {
            do {
                let (data, videoResponse) = try await GenerationTransport.recover(URLRequest(url: videoUrl))
                let dlStatus = (videoResponse as? HTTPURLResponse)?.statusCode ?? -1
                Log.debug("Video download: HTTP \(dlStatus)")

                guard let httpResp = videoResponse as? HTTPURLResponse,
                      (200...299).contains(httpResp.statusCode) else {
                    let statusCode = (videoResponse as? HTTPURLResponse)?.statusCode ?? -1
                    throw GenerationError.apiError("HTTP \(statusCode)")
                }

                videoData = data
                break  // Success, exit retry loop

            } catch {
                // A user cancel (URLError.cancelled) must not trigger the retry
                // dialog or a failure record — unwind as cancellation.
                if isCancellation(error) { throw CancellationError() }
                downloadRetryCount += 1
                Log.debug("Video download failed (attempt \(downloadRetryCount)/\(maxDownloadRetries)): \(error.localizedDescription)")

                // Agent-originated jobs never show interactive dialogs: retry
                // silently, and on exhaustion leave the item in the 'needs
                // download' recovery state (source URL kept, no imagePath) so it
                // can be re-downloaded from the Jobs panel — no prompt.
                if isAgentJob {
                    if downloadRetryCount <= maxDownloadRetries {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                    if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
                       case .item(var item) = appState.historyState.history[index] {
                        item.status = .failed
                        item.responseText = "Video generated but download failed after \(maxDownloadRetries) attempts — re-download it from the Jobs panel."
                        item.videoUrl = videoUrlStr
                        appState.historyState.history[index] = .item(item)
                        appState.historyState.saveHistory()
                    }
                    throw GenerationError.apiError("Video download failed after \(maxDownloadRetries) attempts")
                }

                if downloadRetryCount <= maxDownloadRetries {
                    display {
                        appState.ui.videoGenerationStage = "Download failed, retrying..."
                    }
                    let shouldRetry = await bridge.showRetryDialog("Failed to download video (attempt \(downloadRetryCount)/\(maxDownloadRetries)):\n\(error.localizedDescription)\n\nRetry?")
                    if !shouldRetry {
                        // Mark as failed and exit
                        if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
                           case .item(var item) = appState.historyState.history[index] {
                            item.status = .failed
                            item.responseText = "Video generated but download failed: \(error.localizedDescription)"
                            item.videoUrl = videoUrlStr
                            appState.historyState.history[index] = .item(item)
                            appState.historyState.saveHistory()
                        }
                        display {
                            appState.ui.outputTexts = ["Video download failed: \(error.localizedDescription)"]
                            appState.errorItem = AlertError(message: "Video download failed", fullMessage: "\(error.localizedDescription)\n\nThe video is still available — open it in History to copy the source URL or retry the download:\n\(videoUrlStr)")
                            appState.ui.videoGenerationStage = ""
                        }
                        throw GenerationError.apiError("Video download failed: \(error.localizedDescription)")
                    }
                } else {
                    // Exhausted retries
                    if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
                       case .item(var item) = appState.historyState.history[index] {
                        item.status = .failed
                        item.responseText = "Video generated but download failed after \(maxDownloadRetries) attempts"
                        item.videoUrl = videoUrlStr
                        appState.historyState.history[index] = .item(item)
                        appState.historyState.saveHistory()
                    }
                    display {
                        appState.ui.outputTexts = ["Video download failed after \(maxDownloadRetries) attempts"]
                        appState.errorItem = AlertError(message: "Video download failed", fullMessage: "Failed after \(maxDownloadRetries) attempts.\n\n\(error.localizedDescription)\n\nThe video is still available — open it in History to copy the source URL or retry the download:\n\(videoUrlStr)")
                        appState.ui.videoGenerationStage = ""
                    }
                    throw GenerationError.apiError("Video download failed after \(maxDownloadRetries) attempts")
                }
            }
        }

        guard let videoData = videoData else {
            throw GenerationError.apiError("Video download failed: No data received")
        }

        let savedPath = bridge.saveGeneratedMedia(videoData, finalPrompt, selectedModel)?.path
        guard savedPath != nil else {
            let message = ProviderFailure.classify(provider: videoRequest.provider, phase: .save).message
            updateHistoryItemStatus(id: pendingItem.id, status: .failed, responseText: message)
            throw GenerationError.apiError(message)
        }

        // Detect if video has audio tracks
        var hasAudio = false
        if let path = savedPath {
            hasAudio = await bridge.detectVideoHasAudio(path)
            Log.debug("Video audio detection: hasAudio = \(hasAudio)")
        }

        if let index = appState.historyState.history.firstIndex(where: { $0.id == pendingItem.id }),
           case .item(var item) = appState.historyState.history[index] {
            item.imagePath = savedPath
            item.responseText = "Video generated successfully and saved"
            item.status = .completed
            item.videoHasAudio = hasAudio
            item.customAIMLPayload = submittedPayload
            item.customAIMLEndpoint = submittedEndpoint
            appState.historyState.history[index] = .item(item)
            appState.historyState.saveHistory()
        }
        display {
            appState.ui.outputImages = [nil]
            appState.ui.outputTexts = ["Video saved to \(userFriendlyPath(savedPath ?? "unknown location"))"]
            appState.ui.outputPaths = [savedPath]
            appState.ui.currentOutputIndex = 0
            // Reset video generation progress
            appState.ui.videoGenerationStage = ""
        }
    }

    // MARK: - Silent resume (moved verbatim from ContentView's resume path)

    /// Performs a single status check for each pending video job.
    /// Runs concurrently for all jobs so one slow job doesn't block others.
    /// Resume checks are bounded single polls, so they run outside the
    /// concurrency cap (the pre-queue code polled all pending jobs concurrently).
    func resumePendingJobs(_ items: [HistoryItem]) async {
        await withTaskGroup(of: Void.self) { group in
            for item in items {
                group.addTask { @MainActor in
                    await self.singlePollVideoJob(item)
                }
            }
        }
    }

    /// Single poll for one video job. Downloads if completed, updates status otherwise.
    private func singlePollVideoJob(_ item: HistoryItem) async {
        guard let appState = self.appState, let bridge = self.bridge else { return }
        guard activeJob(forHistoryItem: item.id) == nil, let jobId = item.jobId else { return }

        // Track the check as a queue job so the panel/badge reflects it
        let checkJob = VideoJob(id: UUID(), kind: .resumeCheck, modelId: item.modelUsed ?? "AI/ML video",
                                prompt: item.prompt, state: .running, historyItemID: item.id)
        appendJob(checkJob)
        defer {
            if let index = jobs.firstIndex(where: { $0.id == checkJob.id }), !jobs[index].state.isFinished {
                finishJob(checkJob.id, state: .completed)
            }
        }

        // Reconstruct poll URL. Same decision as `canRetry`: only the endpoint recorded at
        // submission is trusted; the registry fallback synthesized one for unregistered ids.
        if item.mode == .grok && item.pollingEndpoint != GrokVideoClient.pollingEndpoint {
            updateHistoryItemStatus(id: item.id, status: .failed, responseText: "Cannot resume: invalid Grok poll endpoint")
            return
        }
        let endpoint: String? = item.pollingEndpoint

        guard let pollingEndpoint = endpoint else {
            Log.debug("Cannot check job \(jobId): no polling endpoint")
            updateHistoryItemStatus(id: item.id, status: .failed, responseText: "Cannot resume: polling endpoint unknown")
            return
        }

        let pollUrlString = pollingEndpoint + jobId
        guard let pollUrl = URL(string: pollUrlString) else {
            updateHistoryItemStatus(id: item.id, status: .failed, responseText: "Cannot resume: invalid poll URL")
            return
        }

        Log.debug("Single-polling video job \(jobId) at \(pollUrlString)")

        var request = URLRequest(url: pollUrl, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.addValue("Bearer \(item.mode == .grok ? appState.settings.grokApiKey : appState.settings.aimlapiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let pollData: Data
        let pollResponse: URLResponse
        do {
            (pollData, pollResponse) = try await GenerationTransport.recover(request)
        } catch {
            Log.debug("Video check network error for \(jobId): \(error.localizedDescription)")
            // Network error on single check — leave status unchanged, will retry next foreground
            return
        }

        guard let httpResp = pollResponse as? HTTPURLResponse,
              (200...299).contains(httpResp.statusCode) else {
            let statusCode = (pollResponse as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: pollData, encoding: .utf8) ?? ""
            let isInvalidId = body.contains("Invalid id") || body.contains("Id not found") || (item.mode == .grok && [404, 410].contains(statusCode))
            if isInvalidId {
                updateHistoryItemStatus(id: item.id, status: .failed, responseText: "Video job expired or not found (ID: \(jobId))")
            } else {
                Log.debug("Video check HTTP \(statusCode) for \(jobId) — will retry next foreground")
            }
            return
        }

        // Adapt xAI's pending/done states to the shared queue contract.
        let normalizedData: Data
        do { normalizedData = item.mode == .grok ? try GrokVideoClient.normalizedResponse(pollData) : pollData }
        catch { Log.debug("Invalid Grok video status: \(error)"); return }
        let result = AIMLEndpoints.decodeVideoPoll(normalizedData, provider: item.mode ?? .aimlapi)

        switch result {
        case .inProgress(let status):
            let parsedStatus = GenerationStatus(legacy: status)
            updateJob(checkJob.id) { $0.providerStatus = parsedStatus }
            updateHistoryItemStatus(id: item.id, status: parsedStatus, responseText: "Video \(status)… (Job ID: \(jobId))")
            Log.debug("Job \(jobId) still \(status) — will check again on next foreground return")

        case .failed(let message):
            updateHistoryItemStatus(id: item.id, status: .failed, responseText: "Failed: \(message)")
            JobNotifier.post(title: "Video generation failed", body: message)

        case .decodingError(let body):
            Log.debug("Invalid poll response for \(jobId): \(body ?? "nil") — will retry next foreground")

        case .completed(let videoUrlStr, let costUSD):
            // Persist the source URL and the actual cost BEFORE downloading, matching
            // the live poll path: usd_spent only appears in the completion poll
            // response, and this (resume) path used to drop it — completed video
            // jobs recovered after a relaunch/foreground ended up with costUSD nil.
            appState.historyState.updateItem(id: item.id) { updated in
                updated.videoUrl = videoUrlStr
                if let costUSD { updated.costUSD = costUSD }
            }
            if await downloadAndFinalize(item: item, videoUrlStr: videoUrlStr, recoveredToast: true) {
                Log.debug("Video resume complete for job \(jobId)")
            }
        }
    }

    /// Downloads a finished job's video (1 retry) and finalizes its history item.
    /// Shared by the silent-resume path and the Jobs panel's re-download action.
    @discardableResult
    private func downloadAndFinalize(item: HistoryItem, videoUrlStr: String, recoveredToast: Bool) async -> Bool {
        guard let appState = self.appState, let bridge = self.bridge else { return false }
        appState.historyState.updateItem(id: item.id) { saved in
            if item.task == .image { saved.sourceAssetURL = videoUrlStr }
            else { saved.videoUrl = videoUrlStr }
        }
        guard let videoUrl = URL(string: videoUrlStr) else {
            updateHistoryItemStatus(id: item.id, status: .failed, responseText: "Invalid video URL returned")
            return false
        }

        // Download with 1 retry
        var videoData: Data?
        for attempt in 1...2 {
            do {
                let (data, response) = try await GenerationTransport.recover(URLRequest(url: videoUrl))
                guard let httpVideoResp = response as? HTTPURLResponse,
                      (200...299).contains(httpVideoResp.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    Log.debug("Video download attempt \(attempt) failed: HTTP \(code)")
                    if attempt < 2 {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                    updateHistoryItemStatus(id: item.id, status: .failed, responseText: "Video download failed (HTTP \(code))")
                    return false
                }
                videoData = data
                break
            } catch {
                Log.debug("Video download attempt \(attempt) error: \(error.localizedDescription)")
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                updateHistoryItemStatus(id: item.id, status: .failed, responseText: "Video download failed: \(error.localizedDescription)")
                return false
            }
        }

        guard let data = videoData else { return false }

        if item.task == .image && PlatformImage(platformData: data) == nil {
            updateHistoryItemStatus(id: item.id, status: .failed, responseText: "The source returned unreadable image data. Check provider availability; no new generation was started.")
            return false
        }
        let saved = item.task == .image
            ? bridge.saveRecoveredImage(data, item.prompt, item.modelUsed, item.mode ?? .aimlapi)
            : bridge.saveGeneratedMedia(data, item.prompt, item.modelUsed)
        guard let savedPath = saved?.path else {
            updateHistoryItemStatus(id: item.id, status: .failed, responseText: "Media downloaded but failed to save to disk")
            return false
        }

        let hasAudio = item.task == .image ? false : await bridge.detectVideoHasAudio(savedPath)

        // Update history — preserve customAIMLPayload/customAIMLEndpoint
        // Persistence handled by HistoryState.history didSet
        appState.historyState.updateItem(id: item.id) { updatedItem in
            updatedItem.imagePath = savedPath
            updatedItem.responseText = "Original media downloaded and saved"
            updatedItem.status = .completed
            updatedItem.videoHasAudio = item.task == .image ? nil : hasAudio
        }

        if recoveredToast {
            // Notify user that a background video was recovered
            bridge.notifyRecovered("Video ready — recovered from background")
            JobNotifier.post(title: "Video ready", body: JobNotifier.snippet(item.prompt))
        }

        Log.debug("Video download finalized for item \(item.id), saved to \(savedPath)")
        return true
    }

    /// Helper to update a history item's status and response text.
    /// Persistence is handled automatically by HistoryState.history's didSet.
    private func updateHistoryItemStatus(id: UUID, status: GenerationStatus, responseText: String) {
        guard let appState = self.appState else { return }
        appState.historyState.updateItem(id: id) { item in
            item.status = status
            item.responseText = ProviderFailure.redact(responseText)
        }
    }
}

// MARK: - User notifications

/// Posts user notifications for job completion/failure/expiry on both platforms.
/// Gated by the "Video job notifications" toggle in General Options (default on).
enum JobNotifier {
    static let enabledKey = "jobNotificationsEnabled"

    private static var enabled: Bool {
        AppStorageContext.defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Shows banners even while the app is frontmost (default is to suppress them).
    private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
        static let shared = ForegroundPresenter()
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }
    }

    static func snippet(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(no prompt)" }
        return trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
    }

    static func post(title: String, body: String) {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = ForegroundPresenter.shared
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}
