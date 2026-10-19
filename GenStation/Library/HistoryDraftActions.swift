import SwiftUI
import GenStationCore

/// Both library surfaces prepare drafts through this single, synchronous transition.
/// Reading and copying the original completes before any shared form state changes.
@MainActor
enum HistoryDraftCoordinator {
    static func hasKey(_ provider: Provider, in app: AppState) -> Bool {
        switch provider {
        case .gemini: return !app.settings.apiKey.isEmpty
        case .grok: return !app.settings.grokApiKey.isEmpty
        case .aimlapi: return !app.settings.aimlapiKey.isEmpty
        case .comfyUI: return true
        }
    }

    static func prepareVideoRetry(_ item: HistoryItem, app: AppState) {
        guard app.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              app.ui.imageSlots.allSatisfy({ $0.path.isEmpty }) else {
            app.errorItem = AlertError(message: "Hosted frames may have expired. Save or clear your current prompt and remove input images, then choose Generate again to prepare an editable draft. No request was sent.", fullMessage: nil)
            return
        }
        let modelID = item.modelUsed ?? ""
        guard item.mode == .grok || ReleaseModelPolicy.allows(modelID, task: .video) else {
            app.errorItem = AlertError(message: ReleaseModelPolicy.unavailableMessage, fullMessage: nil)
            return
        }
        app.settings.provider = item.mode ?? .aimlapi
        app.settings.task = .video
        app.settings.customAIMLPayload = nil
        app.settings.customAIMLEndpoint = nil
        if item.mode == .grok {
            app.settings.grokVideoDuration = 5
            app.settings.grokVideoResolution = "480p"
            app.settings.grokVideoAspectRatio = "16:9"
            app.settings.grokVideoAudio = true
        } else if let model = Catalog.model(for: modelID) {
            app.settings.selectedAIMLModel = model.id
            app.settings.aimlAdvancedParams = ParamDecoder.defaults(ParamCatalog.descriptors(for: model))
        }
        app.ui.imageSlots = []
        app.ui.promptMode = .single
        app.prompt = item.prompt
        app.presentedModal = nil
        app.errorItem = AlertError(message: "Editable video draft prepared with model defaults. Hosted frames may have expired: reattach the original local frames and review the settings before generating. No request was sent.", fullMessage: nil)
    }

    static func prepare(_ item: HistoryItem, destination: HistoryDraftTransition.Destination, app: AppState) {
        let directory = app.settings.outputDirectory
        let accessed = directory?.startAccessingSecurityScopedResource() ?? false
        defer { if accessed { directory?.stopAccessingSecurityScopedResource() } }
        let source = item.imagePath.map { URL(fileURLWithPath: $0) }
        let image = source.flatMap { PlatformImage(contentsOfFile: $0.path) }
        if let issue = HistoryDraftTransition.issue(destination: destination, prompt: app.prompt,
            occupiedInputs: app.ui.imageSlots.filter { !$0.path.isEmpty }.count, sourceReadable: image != nil) {
            app.errorItem = AlertError(message: issue, fullMessage: nil)
            return
        }
        guard let image, let data = image.pngData() else {
            app.errorItem = AlertError(message: "The original image could not be converted. Your draft is unchanged.", fullMessage: nil)
            return
        }
        let url = AppStorageContext.current.temporaryDirectory.appendingPathComponent("draft-\(UUID().uuidString).png")
        do { try data.write(to: url, options: .atomic) }
        catch {
            app.errorItem = AlertError(message: "Could not save the draft input. Check available disk space.", fullMessage: nil)
            return
        }
        let sourceBody = item.customAIMLPayload?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let sourceAspect = sourceBody?["aspect_ratio"] as? String
        let settings = app.settings
        settings.provider = destination.provider
        settings.task = destination.task
        settings.customAIMLPayload = nil
        settings.customAIMLEndpoint = nil
        settings.aimlAdvancedParams = ModelParameters()
        switch destination.provider {
        case .aimlapi:
            settings.selectedAIMLModel = destination.id
            if let model = Catalog.model(for: destination.id) {
                let descriptors = ParamCatalog.descriptors(for: model)
                settings.aimlAdvancedParams = ParamDecoder.defaults(descriptors)
                if let sourceAspect, let aspect = descriptors.first(where: { $0.field == .aspectRatio }),
                   case .picker(let options, _) = aspect.control, options.contains(.string(sourceAspect)) {
                    settings.aimlAdvancedParams.aspectRatio = sourceAspect
                }
            }
        case .gemini:
            settings.selectedGeminiModel = destination.id
            settings.geminiAdvancedParams = ModelParameters(geminiResolution: "1K", aspectRatio: "1:1")
        case .grok:
            if destination.task == .image { settings.selectedGrokModel = destination.id }
            settings.grokAspectRatio = "1:1"
            settings.grokResolution = "2k"
            settings.grokVideoDuration = 5
            settings.grokVideoResolution = "480p"
            settings.grokVideoAspectRatio = "16:9"
            settings.grokVideoAudio = true
        case .comfyUI: break
        }
        app.ui.imageSlots = [UIState.ImageSlot(thumbnail: image.downscaled(toMaxPixels: 512), fullResolutionURL: url)]
        app.ui.promptMode = .single
        app.ui.draftSourcePrompt = item.prompt
        app.prompt = destination.task == .image ? item.prompt : ""
        app.presentedModal = nil
        if !hasKey(destination.provider, in: app) {
            app.errorItem = AlertError(message: "Draft prepared. Add the \(destination.provider.displayName) key in Settings before generating.", fullMessage: nil)
        }
    }
}

struct HistoryDraftActions: View {
    let item: HistoryItem
    @EnvironmentObject var appState: AppState
    var body: some View {
        HistoryCopyImageButton(item: item)
            #if os(macOS)
            if item.imagePath != nil {
                Button("Share original with local agents") { AgentAssetAccess.set(item.id, shared: true) }
                Button("Revoke agent access to original") { AgentAssetAccess.set(item.id, shared: false) }
            }
            #endif
        if item.task != .video && item.videoUrl == nil && item.imagePath?.lowercased().hasSuffix(".mp4") != true {

            Button("Run saved workflow…") { appState.presentedModal = .namedWorkflow(workflowID: nil, assetID: item.id) }
            destinationMenu("Revise image…", task: .image)
            destinationMenu("Animate image…", task: .video)
        }
        if let path = item.imagePath, item.fileExists(appState: appState) {
            ShareLink("Share original media…", item: URL(fileURLWithPath: path))
        }
    }
    private func destinationMenu(_ title: String, task: CreateTask) -> some View {
        Menu(title) {
            ForEach(HistoryDraftTransition.destinations(task: task)) { destination in
                Button("\(destination.provider.displayName) • \(destination.name)\(HistoryDraftCoordinator.hasKey(destination.provider, in: appState) ? "" : " — key needed")") {
                    HistoryDraftCoordinator.prepare(item, destination: destination, app: appState)
                }
            }
        }
    }
}

/// Reads the original, not the display thumbnail or its file URL.
struct HistoryCopyImageButton: View {
    let item: HistoryItem
    @EnvironmentObject var appState: AppState
    @State private var copyError: String?

    var body: some View {
        if item.task != .video && item.videoUrl == nil && item.imagePath?.lowercased().hasSuffix(".mp4") != true {
            Button {
                copyOriginal()
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
            .disabled(!item.fileExists(appState: appState))
            .alert("Could not copy image", isPresented: Binding(
                get: { copyError != nil }, set: { if !$0 { copyError = nil } }
            )) {
                Button("OK", role: .cancel) { copyError = nil }
            } message: {
                Text(copyError ?? "")
            }
        }
    }

    @MainActor
    private func copyOriginal() {
        let directory = appState.settings.outputDirectory
        let accessed = directory?.startAccessingSecurityScopedResource() ?? false
        defer { if accessed { directory?.stopAccessingSecurityScopedResource() } }
        guard let path = item.imagePath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let image = PlatformImage(data: data) else {
            copyError = "The saved original could not be read. Check the file and output folder access."
            return
        }
        PlatformPasteboard.clearContents()
        PlatformPasteboard.writeImage(image)
    }
}
