#if os(macOS)
import AppKit
import Foundation
import GenStationCore

/// Saved-library execution only. Durable request identities use a separate ledger from cloud images.
@MainActor
final class AgentWorkflowService {
    private weak var app: AppState?
    private let bridge: MCPBridge
    private let imageService: AgentImageService
    private let file: URL
    private var ledger: AgentImageLedger
    private var storageError: String?
    var storageReady: Bool { storageError == nil }
    private var running = false
    private var enabled = true
    private var revision = 0

    init(app: AppState, bridge: MCPBridge, imageService: AgentImageService) {
        self.app = app; self.bridge = bridge; self.imageService = imageService
        file = MCPStateStore.fileURL.deletingLastPathComponent().appendingPathComponent("agent_workflow_jobs.json")
        do { ledger = try AgentImageLedger.load(from: file) }
        catch { ledger = AgentImageLedger(); storageError = "Saved-workflow job storage cannot be read. Repair it before executing workflows." }
    }
    func stop() { enabled = false; revision += 1 }
    func start() { enabled = true }

    func list(_ params: [String: Any]) throws -> [String: Any] {
        guard params.isEmpty else { throw AgentImageError("list_workflows takes no arguments.") }
        return ["workflows": WorkflowLibrary.shared.sortedWorkflows.map { saved in
            ["workflow_id": saved.id.uuidString, "name": saved.name,
             "prompt_override_configured": saved.promptNodeID?.isEmpty == false && !saved.exposedInputs.contains(where: { $0.kind == .prompt }),
             "workflow_revision": saved.revision, "workflow_digest": saved.graphDigest,
             "input_schema": ["type": "object", "additionalProperties": false,
                 "properties": Dictionary(uniqueKeysWithValues: saved.exposedInputs.map { ($0.name, $0.publicSchema) }),
                 "required": saved.exposedInputs.filter { $0.required && $0.defaultValue == nil }.map(\.name)],
             "validation_required": true] as [String: Any]
        }, "approval": "individual_request", "scope": "user_saved_workflows_only",
        "input_policy": "Use only discovered input_schema names with workflow_revision/workflow_digest. Scoped image originals upload only after approval. Legacy prompt remains available on workflows without exposed prompt inputs. No paths, graphs, server URLs or node overrides.",
        "configured": !(app?.settings.comfyServerURL.isEmpty ?? true)]
    }

    private struct Prepared {
        let saved: SavedWorkflow
        let server: String
        let url: URL
        let graph: [String: Any]
        let promptKey: String?
        let prompt: String?
        let nodes: [String]
        let promptInspectionLimitations: [String]
        let images: [WorkflowPreparedImage]
        let effectiveValues: [String: WorkflowInputValue]
        let usedLegacyOverride: Bool
    }

    private func prepare(_ contract: AgentWorkflowContract) async throws -> Prepared {
        guard let app, let saved = WorkflowLibrary.shared.workflows.first(where: { $0.id == contract.workflowID }) else {
            throw AgentImageError("Saved workflow is unavailable. Use list_workflows or save one in the app.")
        }
        let result: WorkflowGraphPreparation.Result
        do { result = try await WorkflowGraphPreparation.prepare(saved: saved, serverURL: app.settings.comfyServerURL, contract: contract) }
        catch WorkflowGraphPreparation.Failure.contentFiltered(let reasons) { throw MCPError.filtered(reasons) }
        catch let error as WorkflowGraphPreparation.Failure { throw MCPError(code: .modelUnavailable, message: error.localizedDescription) }
        let images = try result.imageReferences.keys.sorted().map { name in
            try imageService.workflowInput(name: name, reference: result.imageReferences[name]!)
        }
        guard images.reduce(0, { $0 + $1.pngData.count }) <= 20_000_000 else { throw AgentImageError("Workflow reference PNGs must total at most 20 MB.") }
        return Prepared(saved: saved, server: result.server, url: result.url, graph: result.graph, promptKey: result.promptKey,
            prompt: result.prompt, nodes: result.nodes, promptInspectionLimitations: result.promptInspectionLimitations, images: images, effectiveValues: result.effectiveValues, usedLegacyOverride: result.usedLegacyOverride)
    }

    func validate(_ params: [String: Any]) async throws -> [String: Any] {
        let prepared = try await prepare(AgentWorkflowContract(params, submitting: false))
        return summary(prepared).merging(["valid": true, "generation_submitted": false, "network_access": "GET node definitions only"]) { _, b in b }
    }
    private func summary(_ prepared: Prepared) -> [String: Any] {
        ["workflow_id": prepared.saved.id.uuidString, "name": prepared.saved.name, "node_count": prepared.graph.count,
         "node_types": prepared.nodes, "prompt_override_supported": prepared.promptKey != nil && !prepared.saved.exposedInputs.contains(where: { $0.kind == .prompt }),
         "prompt_inspection_limitations": prepared.promptInspectionLimitations,
         "input_images": prepared.images.map { ["name": $0.name, "asset_id": $0.assetID.uuidString, "sha256": $0.sourceDigest] },
         "workflow_revision": prepared.saved.revision, "workflow_digest": prepared.saved.graphDigest,
         "prompt_override_applied": prepared.usedLegacyOverride, "approval": "individual_request", "price_status": "unknown",
         "outputs": "Up to 12 selected originals are retrieved, at most 50 MB per file and 200 MB total. Failed downloads recover independently. Other settings use saved workflow values."]
    }
    func submit(_ params: [String: Any]) throws -> [String: Any] {
        if let storageError { throw AgentImageError(storageError) }
        guard enabled else { throw AgentImageError("Agent access is disabled.") }
        let contract = try AgentWorkflowContract(params, submitting: true)
        let requestID = contract.requestID!
        if let existing = try ledger.existing(requestID: requestID, arguments: params) { return result(existing) }
        guard !running else { throw AgentImageError("A saved workflow request is already active. Poll it before starting another.") }
        // Check local identity before allocating a job. Network validation runs before approval/POST.
        guard WorkflowLibrary.shared.workflows.contains(where: { $0.id == contract.workflowID }) else { throw AgentImageError("Unknown saved workflow_id.") }
        let job = try ledger.register(requestID: requestID, arguments: params, at: file)
        running = true
        Task { await run(job, contract: contract) }
        return result(job)
    }
    func manifest(for id: UUID) -> AgentAssetManifest? {
        guard enabled, !AgentAssetAccess.revoked(id) else { return nil }
        return ledger.jobs.values.flatMap { $0.workflow?.resultAssets ?? [] }.first { $0.assetID == id }?.manifest
    }
    func observation(_ id: String) throws -> AgentJobSummary? {
        guard enabled else { throw AgentImageError("Agent access is disabled.") }
        if let storageError { throw AgentImageError(storageError) }
        return ledger.jobs[id].map { summary($0) }
    }
    func discovery() throws -> [AgentJobSummary] {
        guard enabled else { throw AgentImageError("Agent access is disabled.") }
        if let storageError { throw AgentImageError(storageError) }
        return ledger.jobs.values.map { summary($0) }
    }
    private func summary(_ job: AgentImageJob) -> AgentJobSummary {
        AgentJobSummary(id: job.id, requestID: job.requestID, kind: "saved_comfy_workflow", createdAt: job.createdAt,
            status: job.status, billing: job.billing,
            pendingApproval: AgentApprovalCenter.shared.pending.contains { $0.id == job.id },
            recoveryAvailable: job.workflow?.promptID != nil, label: job.requestLabel)
    }
    func status(_ id: String) -> [String: Any]? {
        guard let job = ledger.jobs.values.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { return nil }
        return result(job)
    }
    private func result(_ job: AgentImageJob) -> [String: Any] {
        var output: [String: Any] = ["job_id": job.id, "request_id": job.requestID, "kind": "saved_comfy_workflow",
            "status": job.status, "billing_status": job.billing, "resubmit_safe": false,
            "recovery_available": job.workflow?.promptID != nil,
            "asset_ids": job.assetIDs.filter { !AgentAssetAccess.revoked($0) }.map(\.uuidString)]
        output.merge(summary(job).json(now: Date())) { _, new in new }
        if let records = job.workflow?.resultAssets {
            output["outputs"] = records.filter { !AgentAssetAccess.revoked($0.assetID) }.map { record in
                var value: [String: Any] = ["asset_id": record.assetID.uuidString, "downloaded": record.localPath != nil && record.errorMessage == nil && job.assetIDs.contains(record.assetID),
                    "dimensions_status": record.width != nil && record.height != nil ? "known" : "unavailable"]
                if let manifest = record.manifest { value["manifest"] = manifest.json }
                if let type = record.mediaType { value["media_type"] = type }
                if let width = record.width, let height = record.height { value["dimensions"] = [width, height] }
                if let error = record.errorMessage { value["error"] = error }
                return value
            }
        }
        if let id = job.workflow?.promptID { output["server_prompt_id"] = id }
        if let message = job.message { output["message"] = message }
        if let code = job.errorCode { output["error_code"] = code }
        if let reasons = job.filterReasons { output["filter_source"] = "genstation_local"; output["filter_reasons"] = reasons.map(\.json) }
        return output
    }
    private func run(_ initial: AgentImageJob, contract: AgentWorkflowContract) async {
        defer { running = false }
        var job = initial
        let accessRevision = revision
        do {
            let prepared = try await prepare(contract)
            guard enabled, revision == accessRevision else { throw AgentImageError("Agent access was disabled before approval.") }
            let graphText = String(data: try JSONSerialization.data(withJSONObject: prepared.graph, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8) ?? ""
            let imageSummary = prepared.images.map { "\($0.name): asset:\($0.assetID.uuidString) (\($0.pngData.count) PNG bytes)" }.joined(separator: "\n")
            let approved = await AgentImageService.approve(jobID: job.id, requestID: job.requestID, requestLabel: job.requestLabel, createdAt: job.createdAt, prompt: (prepared.prompt ?? "Use saved workflow inputs") + "\n\nReference uploads after approval:\n" + (imageSummary.isEmpty ? "None" : imageSummary) + "\n\nPrepared workflow:\n" + graphText,
                model: "Saved ComfyUI workflow: \(prepared.saved.name)\nServer: \(prepared.url.host ?? "configured server")\nNodes: \(prepared.nodes.joined(separator: ", "))",
                notice: "Runs the saved workflow on your configured ComfyUI server. Saved nodes may read server files, contact services or incur charges. Other inputs and settings remain saved values. Up to 12 selected originals are retrieved within the saved limits. Cost is unknown. Review the prepared workflow below. Stopping locally does not cancel server execution.")
            guard approved, enabled, revision == accessRevision else {
                job.status = "denied"; job.message = "Denied or agent access disabled. No workflow submitted."
                try ledger.update(job, at: file); return
            }
            guard let app, ComfyUIEndpoints.normalizedServerURL(app.settings.comfyServerURL) == prepared.server,
                  WorkflowLibrary.shared.workflows.first(where: { $0.id == prepared.saved.id }) == prepared.saved else {
                throw AgentImageError("Saved workflow or server changed during approval. No workflow submitted; validate again.")
            }
            let rechecked = try await prepare(contract)
            guard rechecked.saved == prepared.saved, rechecked.server == prepared.server,
                  try WorkflowRecoverySnapshot.digest(rechecked.graph) == WorkflowRecoverySnapshot.digest(prepared.graph),
                  rechecked.images.map(\.snapshot) == prepared.images.map(\.snapshot) else {
                throw AgentImageError("Workflow, server schema or reference changed during approval. Validate and approve again; nothing was uploaded.")
            }
            try verifyCurrent(prepared, accessRevision: accessRevision)
            job.status = "uploading"; job.billing = "not_submitted"
            job.workflow = WorkflowRecoverySnapshot(workflowID: prepared.saved.id, workflowRevision: prepared.saved.revision,
                graphDigest: try WorkflowRecoverySnapshot.digest(prepared.graph), serverURL: prepared.server,
                selectedOutputNodeID: prepared.saved.outputNodeID, workflowName: prepared.saved.name,
                displayPrompt: prepared.prompt ?? prepared.saved.name)
            job.workflow?.promptFingerprint = WorkflowPromptSafety.inspect(prepared.graph, selectedPromptNodeID: prepared.saved.promptNodeID).positivePromptFingerprint
            job.workflow?.inputAssets = prepared.images.map(\.snapshot)
            job.workflow?.effectiveInputs = prepared.effectiveValues
            try ledger.update(job, at: file)
            var executionGraph = prepared.graph
            let transport = try ComfyUITransport(serverURL: prepared.server)
            for (index, image) in prepared.images.enumerated() {
                try verifyCurrent(prepared, accessRevision: accessRevision)
                let uploaded = try await transport.uploadPNG(image.pngData)
                job.workflow?.inputAssets?[index].uploadedFileID = uploaded.serverFileID
                try ledger.update(job, at: file)
                guard let definition = prepared.saved.exposedInputs.first(where: { $0.name == image.name }),
                      var node = executionGraph[definition.nodeID] as? [String: Any],
                      var inputs = node["inputs"] as? [String: Any] else { throw AgentImageError("Image binding changed.") }
                inputs[definition.inputKey] = uploaded.serverFileID
                node["inputs"] = inputs; executionGraph[definition.nodeID] = node
            }
            try verifyCurrent(prepared, accessRevision: accessRevision)
            job.workflow?.submittedGraphDigest = try WorkflowRecoverySnapshot.digest(executionGraph)
            job.workflow?.selectedOutputNodeIDs = prepared.saved.outputNodeIDs
            let promptID = try await transport.submit(apiWorkflow: executionGraph, clientID: UUID().uuidString,
                persistIntent: {
                    try self.verifyCurrent(prepared, accessRevision: accessRevision)
                    job.status = "submitting"; job.billing = "unknown"
                    try self.ledger.update(job, at: self.file)
                }, persistPromptID: { id in
                    job.workflow?.promptID = id; job.status = "queued"
                    try self.ledger.update(job, at: self.file)
                })
            let descriptors = try await ComfyUIRunner.waitForOutputs(promptID: promptID, serverURL: prepared.url,
                timeout: TimeInterval(app.settings.comfyGenerationTimeout), outputNodeID: prepared.saved.outputNodeID,
                outputNodeIDs: prepared.saved.outputNodeIDs, shouldContinue: { self.enabled && self.revision == accessRevision })
            try job.workflow?.recordOutputs(descriptors)
            try ledger.update(job, at: file)
            guard enabled, revision == accessRevision else { throw AgentImageError("Agent access was disabled. Existing results can be recovered later.") }
            try await retrieveOutputs(job: &job, expectedRevision: accessRevision)

        } catch {
            let uploadOnly = job.status == "uploading"
            job.status = job.workflow?.promptID != nil ? "recoverable" : (job.workflow != nil && !uploadOnly ? "submission_unknown" : "failed")
            if uploadOnly { job.billing = "not_submitted" }
            if error is ComfyUISubmissionRejected { job.status = "failed"; job.billing = "not_submitted" }
            if let blocked = error as? WorkflowPromptSafety.Blocked {
                job.filterReasons = blocked.report.filterReasons
                job.status = "failed"; job.billing = "not_submitted"; job.errorCode = MCPErrorCode.contentFiltered.rawValue
            }
            if let error = error as? MCPError { job.errorCode = error.code.rawValue; job.filterReasons = error.filterReasons }
            job.message = ProviderFailure.redact((error as? MCPError)?.message ?? (error as? LocalizedError)?.errorDescription ?? "Workflow failed. Check server connection and saved node configuration.")
            do { try ledger.update(job, at: file) }
            catch { storageError = "Workflow job storage failed. Check the library and server before any new request." }
        }
    }

    private func verifyCurrent(_ prepared: Prepared, accessRevision: Int) throws {
        guard enabled, revision == accessRevision, let app,
              ComfyUIEndpoints.normalizedServerURL(app.settings.comfyServerURL) == prepared.server,
              WorkflowLibrary.shared.workflows.first(where: { $0.id == prepared.saved.id }) == prepared.saved else {
            throw AgentImageError("Workflow, server or agent access changed. No new generation was submitted.")
        }
        for image in prepared.images {
            let current = try imageService.workflowInput(name: image.name, reference: "asset:" + image.assetID.uuidString)
            guard current.sourceDigest == image.sourceDigest else { throw AgentImageError("Reference changed after approval. No generation was submitted.") }
        }
    }

    func recoverRequest(_ params: [String: Any]) throws -> [String: Any] {
        guard Set(params.keys) == ["job_id"], let id = params["job_id"] as? String,
              let initial = ledger.jobs[id], let snapshot = initial.workflow, snapshot.promptID != nil else {
            throw AgentImageError("Recovery requires an existing workflow job with a recorded ComfyUI prompt ID.")
        }
        guard enabled, !AgentAssetAccess.revoked(snapshot.assetID) else { throw AgentImageError("Agent or asset access is disabled.") }
        guard !running else { throw AgentImageError("Another workflow operation is active. Poll it before recovery.") }
        if let storageError { throw AgentImageError(storageError) }
        var queued = initial
        queued.status = "recovering"
        try ledger.update(queued, at: file)
        running = true
        let recoveryRevision = revision
        Task {
            defer { running = false }
            var job = queued
            do {
                guard enabled, revision == recoveryRevision, !AgentAssetAccess.revoked(snapshot.assetID) else { throw AgentImageError("Agent or asset access is disabled.") }
                if snapshot.selectedOutputNodeIDs != nil || snapshot.resultAssets != nil {
                    if snapshot.resultAssets == nil {
                        guard let url = URL(string: snapshot.serverURL), let promptID = snapshot.promptID else { throw AgentImageError("Recorded server job is unavailable.") }
                        let descriptors = try await ComfyUIRunner.waitForOutputs(promptID: promptID, serverURL: url,
                            timeout: TimeInterval(app?.settings.comfyGenerationTimeout ?? 300), outputNodeID: snapshot.selectedOutputNodeID,
                            outputNodeIDs: snapshot.selectedOutputNodeIDs ?? [], shouldContinue: { self.enabled && self.revision == recoveryRevision })
                        try job.workflow?.recordOutputs(descriptors)
                        try ledger.update(job, at: file)
                    }
                    try await retrieveOutputs(job: &job, expectedRevision: recoveryRevision)
                    return
                }
                if let path = snapshot.localPath, AppStorageContext.permitsOriginal(URL(fileURLWithPath: path)),
                   FileManager.default.fileExists(atPath: path) {
                    try linkHistory(job: &job)
                } else {
                    let transport = try ComfyUITransport(serverURL: snapshot.serverURL)
                    guard let serverURL = URL(string: transport.serverURL), let promptID = snapshot.promptID else { throw AgentImageError("Recovery server or prompt ID is invalid.") }
                    let output: ComfyUIRunResult
                    if let descriptor = snapshot.outputs.first {
                        output = ComfyUIRunResult(data: try await transport.download(descriptor), descriptor: descriptor, promptID: promptID)
                    } else {
                        output = try await ComfyUIRunner.recover(promptID: promptID, serverURL: serverURL,
                            timeout: TimeInterval(app?.settings.comfyGenerationTimeout ?? 300), outputNodeID: snapshot.selectedOutputNodeID,
                            onOutputs: { outputs in
                                job.workflow?.outputs = outputs; job.status = "downloading"
                                try self.ledger.update(job, at: self.file)
                            }, shouldContinue: { self.enabled && self.revision == recoveryRevision && !AgentAssetAccess.revoked(snapshot.assetID) })
                    }
                    guard enabled, revision == recoveryRevision, !AgentAssetAccess.revoked(snapshot.assetID) else { throw AgentImageError("Access was disabled during recovery.") }
                    try save(output, job: &job)
                }
            } catch {
                job.status = "recoverable"
                job.message = ProviderFailure.redact(error.localizedDescription)
                do { try ledger.update(job, at: file) }
                catch { storageError = "Workflow recovery storage failed. Repair storage before continuing." }
            }
        }
        return result(queued)
    }

    private func persist(_ job: AgentImageJob) throws {
        do { try ledger.update(job, at: file) }
        catch { storageError = "Workflow storage failed. Repair it before continuing."; throw error }
    }

    private func retrieveOutputs(job: inout AgentImageJob, expectedRevision: Int) async throws {
        guard let app, let snapshot = job.workflow, let results = snapshot.resultAssets else { throw AgentImageError("Recorded outputs are unavailable.") }
        let transport = try ComfyUITransport(serverURL: snapshot.serverURL)
        let currentAccessRevision = expectedRevision
        for index in results.indices {
            guard enabled, revision == currentAccessRevision else { throw AgentImageError("Agent access changed during output recovery.") }
            var record = job.workflow!.resultAssets![index]
            do {
                guard !AgentAssetAccess.revoked(record.assetID) else { throw AgentImageError("Output access was revoked.") }
                if record.localPath == nil, case .item(let existing)? = app.historyState.findEntry(by: record.assetID) {
                    record.localPath = existing.imagePath
                }
                let pathExists = record.localPath.map { AppStorageContext.permitsOriginal(URL(fileURLWithPath: $0)) && FileManager.default.fileExists(atPath: $0) } ?? false
                if !pathExists {
                    job.status = "downloading"; try persist(job)
                    let data = try await transport.download(record.descriptor)
                    guard enabled, revision == currentAccessRevision, !AgentAssetAccess.revoked(record.assetID) else { throw AgentImageError("Access changed during output download.") }
                    let otherBytes = job.workflow!.resultAssets!.filter { $0.id != record.id }.reduce(0) { $0 + ($1.byteCount ?? 0) }
                    guard otherBytes + data.count <= 200_000_000 else { throw AgentImageError("Selected outputs exceed the 200 MB total limit.") }
                    let metadata = try WorkflowOutputMetadata.inspect(data, filename: record.descriptor.filename)
                    let saved = try WorkflowOriginalStore.save(data, assetID: record.assetID, filename: record.descriptor.filename, app: app)
                    record.localPath = saved.path; record.usedFallback = saved.usedFallback
                    record.mediaType = metadata.mediaType; record.width = metadata.width; record.height = metadata.height; record.byteCount = data.count
                }
                record.errorMessage = nil
                job.workflow?.resultAssets?[index] = record
                if index == 0 { job.workflow?.localPath = record.localPath; job.workflow?.usedFallback = record.usedFallback; job.workflow?.isVideo = record.mediaType?.hasPrefix("video/") == true }
                job.status = "saving"; try persist(job)
                guard let path = record.localPath else { throw AgentImageError("Saved output path is missing.") }
                if record.width == nil, record.mediaType?.hasPrefix("video/") == true,
                   let dimensions = await WorkflowOutputMetadata.videoDimensions(at: path) {
                    record.width = dimensions.0; record.height = dimensions.1
                    job.workflow?.resultAssets?[index] = record; try persist(job)
                }
                guard enabled, revision == currentAccessRevision, !AgentAssetAccess.revoked(record.assetID) else { throw AgentImageError("Access changed while inspecting the saved original.") }
                if app.historyState.findEntry(by: record.assetID) == nil {
                    var item = HistoryItem(id: record.assetID, prompt: snapshot.displayPrompt,
                        responseText: "Saved ComfyUI workflow via MCP.", imagePath: path, date: job.createdAt,
                        mode: .comfyUI, task: CreateTask(isVideo: record.mediaType?.hasPrefix("video/") == true),
                        workflowName: snapshot.workflowName, batchId: snapshot.assetID, indexInBatch: index,
                        totalInBatch: results.count, jobId: snapshot.promptID, status: .completed, agentGenerated: true)
                    item.parentAssetIDs = snapshot.inputAssets.map { Array(Set($0.map(\.assetID))).sorted { $0.uuidString < $1.uuidString } }
                    item.workflowInputs = snapshot.effectiveInputs
                    item.parentItemId = item.parentAssetIDs?.first
                    item.sourceWorkflowID = snapshot.workflowID; item.sourceWorkflowRevision = snapshot.workflowRevision
                    app.historyState.history.append(.item(item))
                } else { app.historyState.updateItem(id: record.assetID) { $0.imagePath = path; $0.status = .completed } }
                let attributes = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, (attributes.fileSize ?? Int.max) <= 50_000_000 else { throw AgentImageError("Canonical workflow original is not a regular file within the saved output limit.") }
                let canonical = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                let manifest = AgentAssetManifest(assetID: record.assetID, data: canonical, mediaType: record.mediaType ?? "application/octet-stream",
                    width: record.width, height: record.height, model: nil, prompt: snapshot.displayPrompt,
                    promptFingerprint: snapshot.promptFingerprint, fingerprintScope: snapshot.promptFingerprint == nil ? "workflow_display_prompt" : "inspected_positive_literals")
                if let previous = record.manifest, previous.sha256 != manifest.sha256 { throw AgentImageError("Saved original checksum changed; recovery will not replace or promote it.") }
                record.manifest = manifest
                job.workflow?.resultAssets?[index] = record
                try app.historyState.saveHistoryNow()
                AgentAssetAccess.set(record.assetID, shared: true)
                if !job.assetIDs.contains(record.assetID) { job.assetIDs.append(record.assetID) }
                try persist(job)
            } catch {
                if storageError != nil { throw error }
                record.errorMessage = ProviderFailure.redact(error.localizedDescription)
                job.workflow?.resultAssets?[index] = record
                try persist(job)
            }
        }
        let completed = job.workflow!.resultAssets!.filter { $0.errorMessage == nil && job.assetIDs.contains($0.assetID) }.count
        job.status = completed == results.count ? "done" : "recoverable"
        job.message = "\(completed) of \(results.count) originals saved. " + (completed == results.count ? "" : "Recover retrieves missing outputs without another generation.")
        if job.workflow!.resultAssets!.contains(where: { $0.usedFallback == true }) { job.message! += " Fallback storage was used for unavailable output folders." }
        try persist(job)
    }

    private func save(_ output: ComfyUIRunResult, job: inout AgentImageJob) throws {
        guard let snapshot = job.workflow,
              let saved = bridge.saveWorkflowOutput(output.data, snapshot.displayPrompt, output.isVideo, (output.filename as NSString).pathExtension) else {
            throw AgentImageError("Workflow output could not be saved. Recover this job; do not resubmit generation.")
        }
        job.workflow?.localPath = saved.path; job.workflow?.isVideo = output.isVideo
        job.workflow?.usedFallback = saved.usedFallback
        job.status = "saving"
        try ledger.update(job, at: file)
        try linkHistory(job: &job)
    }

    private func linkHistory(job: inout AgentImageJob) throws {
        guard let app, let snapshot = job.workflow, let path = snapshot.localPath else { throw AgentImageError("Saved workflow output is unavailable.") }
        if app.historyState.findEntry(by: snapshot.assetID) == nil {
            var item = HistoryItem(id: snapshot.assetID, prompt: snapshot.displayPrompt, responseText: "Saved ComfyUI workflow via MCP.",
                imagePath: path, date: job.createdAt, mode: .comfyUI, task: CreateTask(isVideo: snapshot.isVideo),
                workflowName: snapshot.workflowName, jobId: snapshot.promptID, status: .completed, agentGenerated: true)
            item.parentAssetIDs = snapshot.inputAssets.map { Array(Set($0.map(\.assetID))).sorted { $0.uuidString < $1.uuidString } }
            item.workflowInputs = snapshot.effectiveInputs
            item.parentItemId = item.parentAssetIDs?.first
            item.sourceWorkflowID = snapshot.workflowID; item.sourceWorkflowRevision = snapshot.workflowRevision
            app.historyState.history.append(.item(item))
        }
        try app.historyState.saveHistoryNow()
        if !snapshot.isVideo { AgentAssetAccess.set(snapshot.assetID, shared: true); job.assetIDs = [snapshot.assetID] }
        job.status = "done"; job.message = "Original saved to the library."
        if snapshot.usedFallback == true {
            job.message = "Original saved to the library using fallback storage because the configured output folder was unavailable."
        }
        try ledger.update(job, at: file)
    }
}
#endif
