#if os(macOS)
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import GenStationCore

/// Permission is granted from the library UI, never inferred from imported history metadata.
enum AgentAssetAccess {
    static let key = "mcpSharedImageIDs"
    static let revokedKey = "mcpRevokedImageIDs"
    static func shared(_ id: UUID) -> Bool { (AppStorageContext.defaults.stringArray(forKey: key) ?? []).contains(id.uuidString) }
    static func revoked(_ id: UUID) -> Bool { (AppStorageContext.defaults.stringArray(forKey: revokedKey) ?? []).contains(id.uuidString) }
    static func set(_ id: UUID, shared: Bool) {
        var ids = Set(AppStorageContext.defaults.stringArray(forKey: key) ?? [])
        var revoked = Set(AppStorageContext.defaults.stringArray(forKey: revokedKey) ?? [])
        if shared { ids.insert(id.uuidString); revoked.remove(id.uuidString) }
        else { ids.remove(id.uuidString); revoked.insert(id.uuidString) }
        AppStorageContext.defaults.set(Array(ids), forKey: key)
        AppStorageContext.defaults.set(Array(revoked), forKey: revokedKey)
    }
}

@MainActor
final class AgentImageService {
    private weak var app: AppState?
    private let bridge: MCPBridge
    private let file: URL
    private var ledger: AgentImageLedger
    private var storageError: String?
    private var queue: [String] = []
    private let budget = AgentBudgetCenter.shared
    private var enabled = true
    private var accessRevision = 0

    init(app: AppState, bridge: MCPBridge) {
        self.app = app; self.bridge = bridge
        file = MCPStateStore.fileURL.deletingLastPathComponent().appendingPathComponent("agent_image_jobs.json")
        do { ledger = try AgentImageLedger.load(from: file) }
        catch { ledger = AgentImageLedger(); storageError = "Agent image job storage cannot be read. Restore or repair it before submitting requests." }
        // Recover response evidence persisted before an interrupted budget settlement.
        for job in ledger.jobs.values where job.budgetGrantID != nil && job.billing != "not_submitted" {
            do {
                try budget.authority.verifyRecordedJob(jobID: job.id, grantID: job.budgetGrantID!, fingerprint: job.fingerprint)
                if let evidence = job.chargeEvidence { try budget.authority.settle(jobID: job.id, evidence: evidence) }
            } catch { storageError = "Budget settlement could not be restored. Automatic submission is disabled." }
        }
        budget.refresh()
    }

    func stop() { enabled = false; accessRevision += 1; try? budget.authority.disable(); budget.refresh() }
    func start() { enabled = true }

    func reconcileInterruptedHistory() {
        for job in ledger.jobs.values where job.status == "interrupted" { _ = status(job.id) }
    }

    func diagnostics() -> [String: Any] {
        ["workflow_version": "2.1", "local_only": true, "enabled": enabled,
         "storage_ready": storageError == nil,
         "providers": ["aimlapi": !(app?.settings.aimlapiKey.isEmpty ?? true), "gemini": !(app?.settings.apiKey.isEmpty ?? true), "grok": !(app?.settings.grokApiKey.isEmpty ?? true)],
         "credential_status": "configured_only_not_verified", "approval": budget.authority.activeGrantID == nil ? "individual_request" : "spending_threshold", "spending_approval": budget.authority.snapshot, "price_status": "unknown",
         "input_images": "data:image/...;base64,... or asset:<asset_id> from list_assets; no paths or remote URLs"]
    }

    func allowed(_ id: UUID) -> Bool {
        !AgentAssetAccess.revoked(id) && (AgentAssetAccess.shared(id) || ledger.jobs.values.contains { $0.assetIDs.contains(id) })
    }

    func accessibleAsset(_ id: UUID) throws -> HistoryItem {
        guard allowed(id), case .item(let item)? = app?.historyState.findEntry(by: id), item.imagePath != nil else {
            throw AgentImageError("Asset is missing or not shared with agents. Share its original in the library.")
        }
        return item
    }
    private func asset(_ id: UUID) throws -> HistoryItem {
        let item = try accessibleAsset(id)
        guard item.task != .video, item.videoUrl == nil else { throw AgentImageError("This input requires an image original, not video.") }
        return item
    }

    func listAssets() -> [String: Any] {
        let ids = Set(ledger.jobs.values.flatMap(\.assetIDs)).union((AppStorageContext.defaults.stringArray(forKey: AgentAssetAccess.key) ?? []).compactMap(UUID.init(uuidString:)))
        let items = ids.compactMap { try? accessibleAsset($0) }.sorted { $0.date > $1.date }.prefix(100)
        return ["assets": items.map { ["asset_id": $0.id.uuidString, "model": $0.modelUsed ?? "", "created_at": ISO8601DateFormatter().string(from: $0.date), "parent_folder_id": parentFolder($0.id), "media_kind": $0.task == .video ? "video" : "image"] }, "limit": 100]
    }

    private func parentFolder(_ id: UUID) -> Any {
        guard let app, let parent = app.historyState.findParentFolderId(for: id, in: app.historyState.history) else { return NSNull() }
        return parent.uuidString
    }

    func getAsset(_ params: [String: Any], expectedManifest: AgentAssetManifest? = nil) throws -> [String: Any] {
        guard let text = params["asset_id"] as? String, let id = UUID(uuidString: text) else { throw AgentImageError("asset_id is required.") }
        let shared = try accessibleAsset(id)
        if shared.task == .video || shared.videoUrl != nil {
            let directory = app?.settings.outputDirectory
            let access = directory?.startAccessingSecurityScopedResource() ?? false
            defer { if access { directory?.stopAccessingSecurityScopedResource() } }
            guard let path = shared.imagePath, AppStorageContext.permitsOriginal(URL(fileURLWithPath: path)),
                  FileManager.default.fileExists(atPath: path),
                  let type = ["mp4": "video/mp4", "m4v": "video/x-m4v", "mov": "video/quicktime", "webm": "video/webm"][(path as NSString).pathExtension.lowercased()] else {
                throw AgentImageError("Supported video original is unavailable.")
            }
            let bytes = try readOriginal(shared, maximumBytes: 200_000_000)
            let manifest = AgentAssetManifest(assetID: id, data: bytes, mediaType: type, width: nil, height: nil, model: shared.modelUsed, prompt: shared.prompt)
            if let expectedManifest, expectedManifest.sha256 != manifest.sha256 { throw AgentImageError("Original checksum changed from its completed job manifest.") }
            return ["asset_id": id.uuidString, "reference": "asset:" + id.uuidString, "file_path": path, "parent_folder_id": parentFolder(id), "manifest": (expectedManifest ?? manifest).json,
                    "media_type": type, "preview_available": false, "input_compatibility": "Video originals cannot be used for image-only workflow inputs."]
        }
        let item = try asset(id)
        let data = try readOriginal(item, maximumBytes: 50_000_000)
        var result: [String: Any] = ["asset_id": id.uuidString, "file_path": item.imagePath!, "reference": "asset:\(id.uuidString)", "parent_folder_id": parentFolder(id)]
        if let source = CGImageSourceCreateWithData(data as CFData, nil), let identifier = CGImageSourceGetType(source) as String? {
            result["media_type"] = UTType(identifier)?.preferredMIMEType ?? "application/octet-stream"
        }
        let stored = expectedManifest ?? ledger.jobs.values.flatMap { $0.manifests ?? [] }.first { $0.assetID == id }
        let manifest = try Self.manifest(item: item, data: data, parametersJSON: stored?.parametersJSON, seed: stored?.seed)
        if let stored, stored.sha256 != manifest.sha256 { throw AgentImageError("Original checksum changed. The current file does not match the completed job manifest.") }
        result["manifest"] = (stored ?? manifest).json
        if let image = PlatformImage(platformData: data)?.downscaled(toMaxPixels: 512).pngData() { result["preview_png_base64"] = image.base64EncodedString() }
        return result
    }

    static func manifest(item: HistoryItem, data: Data, parametersJSON: String? = nil, seed: String? = nil) throws -> AgentAssetManifest {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { throw AgentImageError("Original image metadata is unavailable.") }
        return AgentAssetManifest(assetID: item.id, data: data, mediaType: UTType(identifier)?.preferredMIMEType ?? "application/octet-stream",
            width: properties[kCGImagePropertyPixelWidth as String] as? Int, height: properties[kCGImagePropertyPixelHeight as String] as? Int,
            model: item.modelUsed, prompt: item.prompt, parametersJSON: parametersJSON, seed: seed,
            fingerprintScope: item.mode == .comfyUI ? "workflow_display_prompt" : (parametersJSON == nil ? "history_prompt" : "effective_prompt"))
    }

    private func readOriginal(_ item: HistoryItem, maximumBytes: Int = 20_000_000) throws -> Data {
        guard let path = item.imagePath, let app else { throw AgentImageError("Original image is unavailable.") }
        let directory = app.settings.outputDirectory
        let access = directory?.startAccessingSecurityScopedResource() ?? false
        defer { if access { directory?.stopAccessingSecurityScopedResource() } }
        let url = URL(fileURLWithPath: path)
        guard AppStorageContext.permitsOriginal(url) else { throw AgentImageError("Original belongs to a different workspace.") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= maximumBytes else { throw AgentImageError("Original must be a regular file within the permitted size limit.") }
        return try Data(contentsOf: url)
    }

    func workflowInput(name: String, reference: String) throws -> WorkflowPreparedImage {
        guard reference.hasPrefix("asset:"), let id = UUID(uuidString: String(reference.dropFirst(6))) else {
            throw AgentImageError("Workflow image input requires a shared asset reference.")
        }
        return try WorkflowPreparedImage(name: name, assetID: id, original: readOriginal(asset(id)))
    }

    private func prepare(_ params: [String: Any]) throws -> (AgentImageContract, [String], [UUID]) {
        let allowedKeys: Set<String> = ["provider", "model", "prompt", "params", "input_images", "request_label", "request_id"]
        guard Set(params.keys).isSubset(of: allowedKeys),
              let provider = params["provider"] as? String,
              let model = params["model"] as? String, let prompt = params["prompt"] as? String,
              params["params"] == nil || params["params"] is [String: Any],
              params["input_images"] == nil || params["input_images"] is [String] else {
            throw AgentImageError("Use provider, model, prompt, optional params and input_images. Credentials and arbitrary fields are not accepted.")
        }
        _ = try AgentJobDiscovery.label(params)
        let specs = params["input_images"] as? [String] ?? []
        let contract = try AgentImageContract(provider: provider, model: model, prompt: prompt, params: params["params"] as? [String: Any] ?? [:], inputCount: specs.count)
        try MCPError.requireSafePrompt(prompt)
        var references: [String] = [], sourceIDs: [UUID] = []
        var totalBytes = 0
        for spec in specs {
            let data: Data
            if spec.hasPrefix("asset:"), let id = UUID(uuidString: String(spec.dropFirst(6))) {
                data = try readOriginal(asset(id)); sourceIDs.append(id)
            } else {
                guard spec.utf8.count <= 28_000_000, spec.hasPrefix("data:image/"), let comma = spec.firstIndex(of: ","), spec[..<comma].hasSuffix(";base64"), let decoded = Data(base64Encoded: String(spec[spec.index(after: comma)...])) else { throw AgentImageError("input_images must contain image data URIs or shared asset references. Paths and remote URLs are not accepted.") }
                data = decoded
            }
            totalBytes += data.count
            guard totalBytes <= 20_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 64_000_000,
                  let image = PlatformImage(platformData: data),
                  let converted = processImageForUpload(image: image, originalData: data, format: "jpeg", isBase64: true) else { throw AgentImageError("Input images must decode safely, total at most 20 MB, and each contain at most 64 megapixels.") }
            references.append("data:\(converted.mimeType);base64,\(converted.data.base64EncodedString())")
        }
        return (contract, references, sourceIDs)
    }

    func validate(_ params: [String: Any]) throws -> [String: Any] {
        let (contract, images, _) = try prepare(params)
        _ = try contract.request(apiKey: "validation-only", imageDataURIs: images)
        return ["valid": true, "provider": contract.provider.rawValue, "model": contract.model, "input_count": images.count,
                "credential_configured": !key(contract.provider).isEmpty, "price_status": "unknown", "approval": budget.authority.covers(.init(provider: contract.provider, model: contract.model)) ? "spending_threshold" : "individual_request", "spending_approval": budget.authority.snapshot, "network_requests": 0]
    }

    func submit(_ params: [String: Any]) throws -> [String: Any] {
        if let storageError { throw AgentImageError(storageError) }
        guard enabled, let app else { throw AgentImageError("Agent access is disabled.") }
        guard let requestID = params["request_id"] as? String else { throw AgentImageError("request_id is required. Reuse the same ID and arguments when retrying; use a new ID only for a new paid request.") }
        if let existing = try ledger.existing(requestID: requestID, arguments: params) { return status(existing.id) ?? result(existing) }

        let (contract, images, sourceIDs) = try prepare(params)
        let scope = AgentSpendingThreshold.Scope(provider: contract.provider, model: contract.model)
        let grantID = budget.authority.covers(scope) ? budget.authority.activeGrantID : nil
        guard queue.isEmpty || grantID != nil else { throw AgentImageError("An agent image request is already active. Poll its job before submitting another.") }
        guard queue.count < 100 else { throw AgentImageError("The image queue is full. Poll existing jobs before submitting more.") }
        guard !key(contract.provider).isEmpty else { throw AgentImageError("Configure the \(contract.provider.displayName) key in Settings first.") }
        let job = try ledger.register(requestID: requestID, arguments: params, at: file)
        let item = HistoryItem(prompt: contract.prompt, responseText: "Agent request awaiting your approval. No generation submitted.", date: Date(), mode: contract.provider, task: .image, modelUsed: contract.model, status: .queued, parentItemId: sourceIDs.first, agentGenerated: true)
        var prepared = job; prepared.budgetGrantID = grantID; if grantID != nil { prepared.status = "budget_queued" }; prepared.assetIDs = [item.id]; prepared.requiresManifest = true
        try ledger.update(prepared, at: file)
        app.historyState.history.append(.item(item)); try app.historyState.saveHistoryNow()
        queue.append(job.id)
        let revision = accessRevision
        Task { await run(prepared, contract: contract, images: images, sourceIDs: sourceIDs, revision: revision) }
        return result(prepared)
    }

    func observation(_ id: String) throws -> AgentJobSummary? {
        guard enabled else { throw AgentImageError("Agent access is disabled.") }
        if let storageError { throw AgentImageError(storageError) }
        return ledger.jobs[id].map { summary(resolved($0)) }
    }
    func discovery() throws -> [AgentJobSummary] {
        guard enabled else { throw AgentImageError("Agent access is disabled.") }
        if let storageError { throw AgentImageError(storageError) }
        return ledger.jobs.values.map { summary(resolved($0)) }
    }
    private func summary(_ job: AgentImageJob) -> AgentJobSummary {
        AgentJobSummary(id: job.id, requestID: job.requestID, kind: "image", createdAt: job.createdAt,
            status: job.status, billing: job.billing,
            pendingApproval: AgentApprovalCenter.shared.pending.contains { $0.id == job.id },
            recoveryAvailable: false, label: job.requestLabel)
    }
    func status(_ id: String) -> [String: Any]? {
        guard let job = ledger.jobs.values.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { return nil }
        return result(resolved(job))
    }
    private func resolved(_ original: AgentImageJob) -> AgentImageJob {
        var job = original
        if job.status == "interrupted", let itemID = job.assetIDs.first,
           case .item(let item)? = app?.historyState.findEntry(by: itemID) {
            if item.status == .completed, item.imagePath != nil, job.requiresManifest != true || job.manifests != nil { job.status = "done" }
            else if item.status?.isInProgress == true {
                app?.historyState.updateItem(id: itemID) { $0.status = .failed; $0.responseText = job.message ?? "Interrupted agent request. Do not resubmit automatically." }
            }
        }
        return job
    }
    private func result(_ job: AgentImageJob) -> [String: Any] {
        var value: [String: Any] = ["job_id": job.id, "request_id": job.requestID, "status": job.status, "billing_status": job.billing,
                                  "asset_ids": job.assetIDs.filter(allowed).map(\.uuidString), "resubmit_safe": false]
        value.merge(summary(job).json(now: Date())) { _, new in new }
        value["approval_mode"] = job.budgetGrantID == nil ? "individual_request" : "spending_threshold"
        if let grantID = job.budgetGrantID { value["budget_grant_id"] = grantID; value["spending_approval"] = budget.authority.snapshot }
        if let manifests = job.manifests { value["asset_manifests"] = manifests.filter { allowed($0.assetID) }.map(\.json) }
        if let evidence = job.chargeEvidence { value["charge_evidence"] = evidence.json }
        if let issue = job.billingEvidenceIssue { value["billing_evidence_issue"] = issue }
        if let cost = job.costUSD { value["cost_usd"] = cost }
        if let message = job.message { value["message"] = message }
        if let code = job.errorCode { value["error_code"] = code }
        if let reasons = job.filterReasons { value["filter_source"] = "genstation_local"; value["filter_reasons"] = reasons.map(\.json) }
        return value
    }
    private func key(_ provider: Provider) -> String {
        switch provider { case .aimlapi: return app?.settings.aimlapiKey ?? ""; case .gemini: return app?.settings.apiKey ?? ""; case .grok: return app?.settings.grokApiKey ?? ""; case .comfyUI: return "" }
    }

    static func approve(jobID: String, requestID: String? = nil, requestLabel: String? = nil, createdAt: Date? = nil, prompt: String, model: String, notice: String? = nil) async -> Bool {
        await AgentApprovalCenter.shared.request(jobID: jobID, requestID: requestID, requestLabel: requestLabel, createdAt: createdAt, prompt: prompt, model: model, notice: notice)
    }

    private func run(_ original: AgentImageJob, contract: AgentImageContract, images: [String], sourceIDs: [UUID], revision: Int) async {
        defer { queue.removeAll { $0 == original.id }; budget.removePaused(original.id); budget.refresh() }
        var job = original
        var budgetIntent = false
        var budgetReserved = false
        var budgetSettled = false
        guard let app, let itemID = job.assetIDs.first else { return }
        do {
            while queue.first != job.id {
                guard enabled, revision == accessRevision else { throw MCPError(code: .deniedByUser, message: "Agent access revoked before submission.") }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            let request = try contract.request(apiKey: key(contract.provider), imageDataURIs: images)
            let details = String(data: (try? JSONSerialization.data(withJSONObject: contract.parameters, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? "Model defaults"
            let (data, response) = try await AgentImageSubmission.perform(request: request, authorize: {
                if let grantID = job.budgetGrantID {
                    while true {
                        guard self.enabled, revision == self.accessRevision else { throw MCPError(code: .deniedByUser, message: "Agent access revoked before submission.") }
                        if let decision = self.budget.takeDecision(job.id) {
                            guard decision else { throw MCPError(code: .deniedByUser, message: "Paused request denied by user.") }
                            // Deliberate approval once is separate from the threshold grant.
                            job.budgetGrantID = nil; try self.ledger.update(job, at: self.file)
                            break
                        }
                        guard let reason = self.budget.authority.pauseReason(grantID: grantID) else { break }
                        if job.status != reason {
                            job.status = reason; try self.ledger.update(job, at: self.file)
                            self.budget.pause(job, prompt: contract.prompt, model: contract.model, reason: reason)
                        }
                        try await Task.sleep(nanoseconds: 200_000_000)
                    }
                    self.budget.removePaused(job.id)
                    if job.budgetGrantID != nil {
                        try self.budget.authority.reserve(jobID: job.id, requestID: job.requestID, fingerprint: job.fingerprint,
                            scope: .init(provider: contract.provider, model: contract.model), grantID: grantID)
                        budgetReserved = true; self.budget.refresh()
                    }
                } else {
                    guard await Self.approve(jobID: job.id, requestID: job.requestID, requestLabel: job.requestLabel, createdAt: job.createdAt, prompt: contract.prompt, model: "\(contract.provider.displayName) • \(contract.model)\nInput images: \(images.count)\n\(details)") else {
                        throw MCPError(code: .deniedByUser, message: "Request denied. No generation submitted.")
                    }
                }
                guard self.enabled, revision == self.accessRevision, sourceIDs.allSatisfy(self.allowed) else {
                    throw MCPError(code: .deniedByUser, message: "Agent/asset access revoked. No generation submitted.")
                }
            }, persistIntent: {
                job.status = "submitting"; job.billing = "unknown"
                try self.ledger.update(job, at: self.file)
                if let grantID = job.budgetGrantID {
                    try self.budget.authority.markIntent(jobID: job.id, grantID: grantID)
                    budgetIntent = true; self.budget.refresh()
                }
                app.historyState.updateItem(id: itemID) { $0.status = .generating; $0.responseText = "Agent generation submitted; charge not yet known." }
            }, transport: { try await URLSession.shared.data(for: $0) })
            // Billing evidence survives HTTP rejection, decode failure and failed downloads.
            let observation = ProviderChargeEvidence.observe(provider: contract.provider, data: data,
                httpStatus: (response as? HTTPURLResponse)?.statusCode ?? 0)
            job.chargeEvidence = observation.evidence; job.billingEvidenceIssue = observation.unavailableReason
            if let evidence = observation.evidence { job.costUSD = evidence.amount.displayUSD; job.billing = "reported" }
            else if budgetIntent { job.billing = "billing_unresolved" }
            try self.ledger.update(job, at: self.file)
            if budgetIntent {
                try budget.authority.settle(jobID: job.id, evidence: observation.evidence)
                budgetSettled = true; budget.refresh()
            }
            if let cost = job.costUSD {
                app.ui.sessionSpendUSD += cost
                app.historyState.updateItem(id: itemID) { $0.costUSD = cost }
                try app.historyState.saveHistoryNow()
            }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let message = contract.provider == .aimlapi ? AIMLEndpoints.friendlyError(status: status, body: data) : ProviderFailure.message(provider: contract.provider, status: status, body: data, phase: .submission)
                if status == 402 || AIMLEndpoints.isInsufficientCredits(message) { throw MCPError(code: .insufficientCredits, message: message) }
                throw AgentImageError(message)
             }
            job.status = "saving"
            try ledger.update(job, at: file)
            let imageData: Data
            if contract.provider == .gemini {
                let decoded = try JSONDecoder().decode(GeminiClient.NewGenerateContentResponse.self, from: data)
                guard let inline = decoded.candidates?.flatMap({ $0.content?.parts ?? [] }).first(where: { $0.thought != true && $0.inlineData != nil })?.inlineData,
                      let bytes = Data(base64Encoded: inline.data) else { throw AgentImageError("Provider returned no image. It may have declined the prompt.") }
                imageData = bytes
            } else {
                let decoded = try JSONDecoder().decode(OpenAICompatible.ImageResponse.self, from: data)
                guard let output = decoded.data.first else { throw AgentImageError("Provider returned no image.") }
                if let b64 = output.b64_json, let bytes = Data(base64Encoded: b64) { imageData = bytes }
                else if let source = output.url, let url = URL(string: source), url.scheme == "https" {
                    // Keep the provider's asset before GET so the library can recover a failed download.
                    app.historyState.updateItem(id: itemID) { $0.sourceAssetURL = source; $0.costUSD = job.costUSD }
                    app.historyState.saveHistory()
                    let (bytes, download) = try await URLSession.shared.data(from: url)
                    guard let http = download as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw AgentImageError("Generated image download failed. Recover the download from the library; do not generate again.") }
                    imageData = bytes
                } else { throw AgentImageError("Provider returned no readable image.") }
            }
            guard PlatformImage(platformData: imageData) != nil else { throw AgentImageError("Provider output is not a decodable image.") }
            let recoveryURL = file.deletingLastPathComponent().appendingPathComponent("agent-original-\(itemID.uuidString).image")
            try imageData.write(to: recoveryURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)
            app.historyState.updateItem(id: itemID) { $0.imagePath = recoveryURL.path; $0.costUSD = job.costUSD }
            app.historyState.saveHistory()
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil), let identifier = CGImageSourceGetType(source) as String?,
                  let ext = UTType(identifier)?.preferredFilenameExtension else { throw AgentImageError("Provider original format is unavailable. Recovery bytes were retained.") }
            let saved = try WorkflowOriginalStore.save(imageData, assetID: itemID, filename: "original." + ext, app: app)
            app.historyState.updateItem(id: itemID) { $0.imagePath = saved.path; $0.status = .completed; $0.costUSD = job.costUSD; $0.responseText = "Image generated via MCP." }
            app.historyState.saveHistory()
            guard case .item(let savedItem)? = app.historyState.findEntry(by: itemID) else { throw AgentImageError("Saved image identity is missing.") }
            let parametersJSON = String(data: try JSONSerialization.data(withJSONObject: contract.parameters, options: [.sortedKeys]), encoding: .utf8)
            job.manifests = [try Self.manifest(item: savedItem, data: imageData, parametersJSON: parametersJSON, seed: (contract.parameters["seed"] as? NSNumber).flatMap { $0.doubleValue >= 0 ? $0.stringValue : nil })]
            try app.historyState.saveHistoryNow()
            try? FileManager.default.removeItem(at: recoveryURL)
            job.status = "done"
            if saved.usedFallback { job.message = "Saved outside the configured output folder; move the original to a permanent location." }
            try ledger.update(job, at: file)
        } catch {
            if budgetReserved {
                do {
                    if budgetIntent, !budgetSettled { try budget.authority.settle(jobID: job.id, evidence: nil) }
                    else if !budgetIntent { try budget.authority.releaseUnsubmitted(jobID: job.id); job.billing = "not_submitted" }
                } catch { storageError = "Budget persistence failed. Automatic submission is disabled." }
                budget.refresh()
            }
            job.status = job.billing == "not_submitted" ? "failed" : "interrupted"
            if let error = error as? MCPError {
                job.errorCode = error.code.rawValue
                job.filterReasons = error.filterReasons
                if error.code == .deniedByUser { job.status = "denied" }
            }
            job.message = ProviderFailure.redact((error as? MCPError)?.message ?? error.localizedDescription)
            do { try ledger.update(job, at: file) }
            catch { storageError = "Agent job persistence failed. Repair storage before submitting another request." }
            app.historyState.updateItem(id: itemID) { item in
                if item.status != .completed { item.status = .failed }
                item.responseText = job.message ?? "Agent request interrupted. Do not resubmit automatically."
                item.costUSD = job.costUSD
            }
            app.historyState.saveHistory()
        }
    }
}
#endif
