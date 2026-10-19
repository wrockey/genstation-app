import Foundation
import GenStationCore

struct WorkflowNamedRequest {
    let contract: AgentWorkflowContract
    let prepared: WorkflowGraphPreparation.Result
    let images: [WorkflowPreparedImage]

    @MainActor static func prepare(saved: SavedWorkflow, values: [String: WorkflowInputValue], legacyPrompt: String?, app: AppState) async throws -> Self {
        var arguments: [String: Any] = ["workflow_id": saved.id.uuidString, "workflow_revision": saved.revision,
            "workflow_digest": saved.graphDigest, "inputs": values.mapValues(\.json)]
        if let legacyPrompt, !legacyPrompt.isEmpty { arguments["prompt"] = legacyPrompt }
        let contract = try AgentWorkflowContract(arguments, submitting: false)
        let graph = try await WorkflowGraphPreparation.prepare(saved: saved, serverURL: app.settings.comfyServerURL, contract: contract)
        let images = try graph.imageReferences.keys.sorted().map { name in
            try readImage(name: name, reference: graph.imageReferences[name]!, app: app)
        }
        guard images.reduce(0, { $0 + $1.pngData.count }) <= 20_000_000 else { throw AgentImageError("Prepared workflow references exceed 20 MB total.") }
        return Self(contract: contract, prepared: graph, images: images)
    }

    @MainActor static func readImage(name: String, reference: String, app: AppState) throws -> WorkflowPreparedImage {
        guard reference.hasPrefix("asset:"), let id = UUID(uuidString: String(reference.dropFirst(6))),
              case .item(let item)? = app.historyState.findEntry(by: id), item.task != .video, item.videoUrl == nil,
              let path = item.imagePath, AppStorageContext.permitsOriginal(URL(fileURLWithPath: path)) else {
            throw AgentImageError("Selected image original is missing or unsupported.")
        }
        let directory = app.settings.outputDirectory
        let scoped = directory?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { directory?.stopAccessingSecurityScopedResource() } }
        return try WorkflowPreparedImage(name: name, assetID: id, original: Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe))
    }

    @MainActor func verifyCurrent(app: AppState) throws {
        try Task.checkCancellation()
        guard WorkflowLibrary.shared.workflows.first(where: { $0.id == prepared.saved.id }) == prepared.saved,
              ComfyUIEndpoints.normalizedServerURL(app.settings.comfyServerURL) == prepared.server else {
            throw AgentImageError("Workflow or server changed after review. Validate and approve again.")
        }
        for image in images {
            let current = try Self.readImage(name: image.name, reference: "asset:" + image.assetID.uuidString, app: app)
            guard current.sourceDigest == image.sourceDigest else { throw AgentImageError("Reference original changed after review. Validate and approve again.") }
        }
    }
}
