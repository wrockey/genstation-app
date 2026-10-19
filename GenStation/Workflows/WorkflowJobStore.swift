import Foundation
import Combine
import GenStationCore

/// GUI workflow records use the same durable record format as saved-workflow MCP
/// jobs, with a separate ledger so GUI output is never implicitly agent-shared.
final class WorkflowJobStore: ObservableObject {
    @Published private(set) var jobs: [AgentImageJob] = []
    @Published private(set) var activeIDs: Set<String> = []
    @Published private(set) var storageError: String?
    private let file: URL
    private var ledger = AgentImageLedger()
    private var namedTasks: [String: Task<Void, Never>] = [:]

    init() {
        file = AppStorageContext.current.supportDirectory.appendingPathComponent("gui_workflow_jobs.json")
        do { ledger = try AgentImageLedger.load(from: file); refresh() }
        catch { storageError = "Workflow job storage could not be read. Repair it before submitting workflows." }
    }
    private func refresh() { jobs = ledger.jobs.values.sorted { $0.createdAt > $1.createdAt } }
    func begin(_ snapshot: WorkflowRecoverySnapshot, preparingInputs: Bool = false) throws -> AgentImageJob {
        if let storageError { throw AgentImageError(storageError) }
        var job = try ledger.register(requestID: "gui-" + UUID().uuidString,
            arguments: ["graph_digest": snapshot.graphDigest, "server": snapshot.serverURL], at: file)
        job.workflow = snapshot; job.status = preparingInputs ? "uploading" : "submitting"; job.billing = preparingInputs ? "not_submitted" : "unknown"
        try update(job)
        activeIDs.insert(job.id)
        return job
    }
    func update(_ job: AgentImageJob) throws {
        do { try ledger.update(job, at: file); storageError = nil; refresh() }
        catch { storageError = "Workflow job could not be saved. Check storage before making another request."; throw error }
    }
    func finishTracking(_ id: String) { activeIDs.remove(id) }
    func canStopNamed(_ id: String) -> Bool { namedTasks[id] != nil }
    func stopNamed(_ id: String) { namedTasks[id]?.cancel() }

    @MainActor func startNamed(_ request: WorkflowNamedRequest, app: AppState) throws -> String {
        try request.verifyCurrent(app: app)
        var snapshot = WorkflowRecoverySnapshot(workflowID: request.prepared.saved.id, workflowRevision: request.prepared.saved.revision,
            graphDigest: try WorkflowRecoverySnapshot.digest(request.prepared.graph), serverURL: request.prepared.server,
            selectedOutputNodeID: request.prepared.saved.outputNodeID, workflowName: request.prepared.saved.name,
            displayPrompt: request.prepared.prompt ?? request.prepared.saved.name)
        snapshot.inputAssets = request.images.map(\.snapshot)
        snapshot.effectiveInputs = request.prepared.effectiveValues
        snapshot.selectedOutputNodeIDs = request.prepared.saved.outputNodeIDs
        let initial = try begin(snapshot, preparingInputs: true)
        namedTasks[initial.id] = Task { @MainActor in
            defer { self.activeIDs.remove(initial.id); self.namedTasks.removeValue(forKey: initial.id) }
            var job = initial
            do {
                let current = try await WorkflowGraphPreparation.prepare(saved: request.prepared.saved, serverURL: app.settings.comfyServerURL, contract: request.contract)
                guard try WorkflowRecoverySnapshot.digest(current.graph) == WorkflowRecoverySnapshot.digest(request.prepared.graph) else {
                    throw AgentImageError("Server definitions changed after review. Validate and approve again.")
                }
                try request.verifyCurrent(app: app)
                var graph = request.prepared.graph
                let transport = try ComfyUITransport(serverURL: request.prepared.server)
                for (index, image) in request.images.enumerated() {
                    try request.verifyCurrent(app: app)
                    let uploaded = try await transport.uploadPNG(image.pngData)
                    job.workflow?.inputAssets?[index].uploadedFileID = uploaded.serverFileID
                    try update(job)
                    guard let definition = request.prepared.saved.exposedInputs.first(where: { $0.name == image.name }),
                          var node = graph[definition.nodeID] as? [String: Any], var inputs = node["inputs"] as? [String: Any] else { throw AgentImageError("Image binding is missing.") }
                    inputs[definition.inputKey] = uploaded.serverFileID; node["inputs"] = inputs; graph[definition.nodeID] = node
                }
                try request.verifyCurrent(app: app)
                job.workflow?.submittedGraphDigest = try WorkflowRecoverySnapshot.digest(graph)
                let promptID = try await transport.submit(apiWorkflow: graph, clientID: UUID().uuidString,
                    persistIntent: {
                        try request.verifyCurrent(app: app)
                        job.status = "submitting"; job.billing = "unknown"; try self.update(job)
                    }, persistPromptID: { id in job.workflow?.promptID = id; job.status = "queued"; try self.update(job) })
                let outputs = try await ComfyUIRunner.waitForOutputs(promptID: promptID, serverURL: request.prepared.url,
                    timeout: TimeInterval(app.settings.comfyGenerationTimeout), outputNodeID: snapshot.selectedOutputNodeID,
                    outputNodeIDs: snapshot.selectedOutputNodeIDs ?? [])
                try job.workflow?.recordOutputs(outputs); try update(job)
                try await retrieveNamedOutputs(job: &job, app: app)
            } catch {
                let uploadedOnly = job.status == "uploading"
                job.status = job.workflow?.promptID != nil ? "recoverable" : (uploadedOnly ? "failed" : "submission_unknown")
                if uploadedOnly || error is ComfyUISubmissionRejected || error is WorkflowPromptSafety.Blocked {
                    job.status = "failed"; job.billing = "not_submitted"
                }
                job.message = error is CancellationError ? "Local waiting stopped. Known server execution may continue; recovery never submits again." : ProviderFailure.redact(error.localizedDescription)
                do { try update(job) } catch { /* update surfaces storage failure */ }
            }
        }
        return initial.id
    }

    @MainActor private func retrieveNamedOutputs(job: inout AgentImageJob, app: AppState) async throws {
        guard let snapshot = job.workflow, let outputs = snapshot.resultAssets else { throw AgentImageError("Recorded outputs are unavailable.") }
        let transport = try ComfyUITransport(serverURL: snapshot.serverURL)
        for index in outputs.indices {
            try Task.checkCancellation()
            var record = job.workflow!.resultAssets![index]
            do {
                if record.localPath == nil, case .item(let existing)? = app.historyState.findEntry(by: record.assetID) { record.localPath = existing.imagePath }
                let exists = record.localPath.map { AppStorageContext.permitsOriginal(URL(fileURLWithPath: $0)) && FileManager.default.fileExists(atPath: $0) } ?? false
                if !exists {
                    job.status = "downloading"; try update(job)
                    let data = try await transport.download(record.descriptor)
                    let otherBytes = job.workflow!.resultAssets!.filter { $0.id != record.id }.reduce(0) { $0 + ($1.byteCount ?? 0) }
                    guard otherBytes + data.count <= 200_000_000 else { throw AgentImageError("Selected outputs exceed the 200 MB total limit.") }
                    let metadata = try WorkflowOutputMetadata.inspect(data, filename: record.descriptor.filename)
                    let saved = try WorkflowOriginalStore.save(data, assetID: record.assetID, filename: record.descriptor.filename, app: app)
                    record.localPath = saved.path; record.usedFallback = saved.usedFallback; record.mediaType = metadata.mediaType
                    record.width = metadata.width; record.height = metadata.height; record.byteCount = data.count
                }
                record.errorMessage = nil; job.workflow?.resultAssets?[index] = record
                if index == 0 { job.workflow?.localPath = record.localPath; job.workflow?.isVideo = record.mediaType?.hasPrefix("video/") == true }
                job.status = "saving"; try update(job)
                guard let path = record.localPath else { throw AgentImageError("Saved output path is missing.") }
                if record.width == nil, record.mediaType?.hasPrefix("video/") == true,
                   let dimensions = await WorkflowOutputMetadata.videoDimensions(at: path) {
                    record.width = dimensions.0; record.height = dimensions.1
                    job.workflow?.resultAssets?[index] = record; try update(job)
                }
                try Task.checkCancellation()
                if app.historyState.findEntry(by: record.assetID) == nil {
                    var item = HistoryItem(id: record.assetID, prompt: snapshot.displayPrompt, responseText: "Saved ComfyUI workflow.",
                        imagePath: path, date: job.createdAt, mode: .comfyUI, task: CreateTask(isVideo: record.mediaType?.hasPrefix("video/") == true),
                        workflowName: snapshot.workflowName, batchId: snapshot.assetID, indexInBatch: index, totalInBatch: outputs.count,
                        jobId: snapshot.promptID, status: .completed)
                    item.parentAssetIDs = snapshot.inputAssets.map { Array(Set($0.map(\.assetID))).sorted { $0.uuidString < $1.uuidString } }
                    item.workflowInputs = snapshot.effectiveInputs
                    item.parentItemId = item.parentAssetIDs?.first; item.sourceWorkflowID = snapshot.workflowID; item.sourceWorkflowRevision = snapshot.workflowRevision
                    app.historyState.history.append(.item(item))
                } else { app.historyState.updateItem(id: record.assetID) { $0.imagePath = path; $0.status = .completed } }
                try app.historyState.saveHistoryNow()
                if !job.assetIDs.contains(record.assetID) { job.assetIDs.append(record.assetID) }
                try update(job)
            } catch {
                if error is CancellationError || storageError != nil { throw error }
                record.errorMessage = ProviderFailure.redact(error.localizedDescription)
                job.workflow?.resultAssets?[index] = record; try update(job)
            }
        }
        let count = job.workflow!.resultAssets!.filter { $0.errorMessage == nil && job.assetIDs.contains($0.assetID) }.count
        job.status = count == outputs.count ? "done" : "recoverable"
        job.message = "\(count) of \(outputs.count) originals saved. " + (count == outputs.count ? "" : "Recover retrieves missing outputs without a new generation.")
        if job.workflow!.resultAssets!.contains(where: { $0.usedFallback == true }) { job.message! += " Fallback storage was used." }
        try update(job)
    }
    func markCompleted(_ id: String) throws {
        guard var job = ledger.jobs[id] else { return }
        job.status = "done"; job.message = "Original saved to the library."
        try update(job)
    }

    @MainActor func recover(_ initial: AgentImageJob, app: AppState) {
        guard !activeIDs.contains(initial.id), let snapshot = initial.workflow, snapshot.promptID != nil else { return }
        activeIDs.insert(initial.id)
        namedTasks[initial.id] = Task { @MainActor in
            defer { self.activeIDs.remove(initial.id); self.namedTasks.removeValue(forKey: initial.id) }
            var job = initial
            do {
                if let storageError { throw AgentImageError(storageError) }
                job.status = "recovering"; try update(job)
                if snapshot.resultAssets != nil || snapshot.selectedOutputNodeIDs != nil {
                    if snapshot.resultAssets == nil {
                        guard let url = URL(string: snapshot.serverURL), let promptID = snapshot.promptID else { throw AgentImageError("Recorded server job is unavailable.") }
                        let outputs = try await ComfyUIRunner.waitForOutputs(promptID: promptID, serverURL: url,
                            timeout: TimeInterval(app.settings.comfyGenerationTimeout), outputNodeID: snapshot.selectedOutputNodeID,
                            outputNodeIDs: snapshot.selectedOutputNodeIDs ?? [])
                        try job.workflow?.recordOutputs(outputs); try update(job)
                    }
                    try await retrieveNamedOutputs(job: &job, app: app)
                    return
                }
                let existingItem: HistoryItem? = {
                    if case .item(let item)? = app.historyState.findEntry(by: snapshot.assetID) { return item }
                    return nil
                }()
                var path = snapshot.localPath ?? existingItem?.imagePath
                var video = existingItem?.task == .video || snapshot.isVideo
                if path == nil || !AppStorageContext.permitsOriginal(URL(fileURLWithPath: path!)) || !FileManager.default.fileExists(atPath: path!) {
                    let transport = try ComfyUITransport(serverURL: snapshot.serverURL)
                    guard let url = URL(string: transport.serverURL), let promptID = snapshot.promptID else { throw AgentImageError("Recovery server is invalid.") }
                    let output: ComfyUIRunResult
                    if let descriptor = snapshot.outputs.first {
                        output = ComfyUIRunResult(data: try await transport.download(descriptor), descriptor: descriptor, promptID: promptID)
                    } else {
                        output = try await ComfyUIRunner.recover(promptID: promptID, serverURL: url,
                            timeout: TimeInterval(app.settings.comfyGenerationTimeout), outputNodeID: snapshot.selectedOutputNodeID,
                            onOutputs: { outputs in
                                job.workflow?.outputs = outputs; job.status = "downloading"; try self.update(job)
                            })
                    }
                    let directory = AppStorageContext.current.supportDirectory.appendingPathComponent("RecoveredWorkflowOutputs", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let ext = (output.filename as NSString).pathExtension.lowercased()
                    guard !ext.isEmpty, ext.count <= 8, ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { throw AgentImageError("Output has an unsupported extension.") }
                    let destination = directory.appendingPathComponent(snapshot.assetID.uuidString + "." + ext)
                    try output.data.write(to: destination, options: .atomic)
                    path = destination.path; video = ["mp4", "mov", "m4v", "webm", "avi"].contains(ext)
                    job.workflow?.localPath = path; job.workflow?.isVideo = video; job.status = "saving"
                    try update(job)
                }
                if existingItem == nil {
                    app.historyState.history.append(.item(HistoryItem(id: snapshot.assetID, prompt: snapshot.displayPrompt,
                        responseText: "Recovered ComfyUI output without generating again.", imagePath: path, date: job.createdAt,
                        mode: .comfyUI, task: CreateTask(isVideo: video), workflowName: snapshot.workflowName,
                        jobId: snapshot.promptID, status: .completed)))
                } else {
                    app.historyState.updateItem(id: snapshot.assetID) { $0.imagePath = path; $0.status = .completed }
                }
                try app.historyState.saveHistoryNow()
                job.status = "done"; job.message = "Original recovered without a new generation."
                try update(job)
            } catch {
                job.status = "recoverable"; job.message = ProviderFailure.redact(error.localizedDescription)
                try? update(job)
                app.errorItem = AlertError(message: job.message ?? "Workflow recovery failed.", fullMessage: nil)
            }
        }
    }
}
