//GenStationApp.swift
//
import SwiftUI
import Combine
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import PencilKit
import AVFoundation
#endif
import GenStationCore
struct NodeInfo: Identifiable, Equatable {
    let id: String
    let label: String
    let promptText: String?
    let classType: String?

    init(id: String, label: String, promptText: String?, classType: String? = nil) {
        self.id = id
        self.label = label
        self.promptText = promptText
        self.classType = classType
    }
}

// MARK: - Additional Inputs for ComfyUI

/// Image data for an additional image input (not Codable - runtime only)
struct AdditionalInputImage: Equatable {
    var thumbnail: PlatformImage?
    var fullResolutionURL: URL?
    var originalData: Data?

    static func == (lhs: AdditionalInputImage, rhs: AdditionalInputImage) -> Bool {
        lhs.fullResolutionURL == rhs.fullResolutionURL
    }
}
enum ImageSubmissionMethod: String, Codable, CaseIterable, Hashable {
    case imgBB = "ImgBB Links (Public URLs)"
    case base64 = "Base64 Payload (Private)"
    case binary = "Binary Payload (Private)"
}

struct GeminiModel: Identifiable, Codable, Equatable {
    let name: String
    let displayName: String
    let description: String?
    
    // These fields may or may not exist depending on model age
    let supportedGenerationMethods: [String]?
    
    var shortName: String {
        name.replacingOccurrences(of: "models/", with: "")
    }
    
    var id: String { name }
    
    // Safe accessor
    var canGenerateContent: Bool {
        guard let methods = supportedGenerationMethods else {
            // New preview models often omit this field but ALL can generateContent
            return true
        }
        return methods.contains("generateContent")
    }
    
    // CodingKeys to make decoding resilient
    enum CodingKeys: String, CodingKey {
        case name, displayName, description, supportedGenerationMethods
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        supportedGenerationMethods = try container.decodeIfPresent([String].self, forKey: .supportedGenerationMethods)
    }
}



class SettingsState: ObservableObject {
    @Published var apiKey: String = KeychainHelper.loadAPIKey() ?? ""
    @Published var outputDirectory: URL? = nil {
        didSet {
            if AppStorageContext.current.isDemo,
               outputDirectory != AppStorageContext.current.outputDirectory {
                outputDirectory = AppStorageContext.current.outputDirectory
            }
        }
    }

    /// Convenience computed property for output path string
    var outputPath: String {
        get { outputDirectory?.path ?? "" }
        set {
            if newValue.isEmpty {
                outputDirectory = nil
            } else {
                outputDirectory = URL(fileURLWithPath: newValue)
            }
        }
    }

    /// Which backend the form is currently pointed at. Still drives the provider tab row;
    /// Stage 5 replaces that row with a task-first sidebar and this becomes a property of
    /// the selected model rather than a navigation choice.
    @Published var provider: Provider = .gemini {
        didSet { saveSelection() }
    }
    @AppStorage("comfyServerURL", store: AppStorageContext.defaults) var comfyServerURL: String = "http://localhost:8188"
    @Published var comfyJSONURL: URL? = nil
    @Published var comfyJSONPath: String = ""
    @Published var grokApiKey: String = KeychainHelper.loadGrokAPIKey() ?? ""
    // Default to the image generation and editing model verified in September 2026.
    @Published var selectedGrokModel: String = "grok-imagine-image-2.0" {
        didSet { saveSelection() }
    }
    // Only applied for the grok-imagine-* models; the legacy grok-2-image ignores them.
    @AppStorage("grokAspectRatio", store: AppStorageContext.defaults) var grokAspectRatio: String = "1:1"
    @AppStorage("grokResolution", store: AppStorageContext.defaults) var grokResolution: String = "2k"
    @AppStorage("grokVideoDuration", store: AppStorageContext.defaults) var grokVideoDuration: Int = 5
    @AppStorage("grokVideoAspectRatio", store: AppStorageContext.defaults) var grokVideoAspectRatio: String = "16:9"
    @AppStorage("grokVideoResolution", store: AppStorageContext.defaults) var grokVideoResolution: String = "480p"
    @AppStorage("grokVideoAudio", store: AppStorageContext.defaults) var grokVideoAudio: Bool = true
    var usesVideoQueue: Bool { isVideoMode && (provider == .aimlapi || provider == .grok) }
    var selectedVideoModel: String { provider == .grok ? GrokVideoClient.model : selectedAIMLModel }

    // Favorite + recent AI/ML models (persisted) — for the searchable model picker.
    @Published var favoriteAIMLModels: [String] = AppStorageContext.defaults.stringArray(forKey: "favoriteAIMLModels") ?? [] {
        didSet { AppStorageContext.defaults.set(favoriteAIMLModels, forKey: "favoriteAIMLModels") }
    }
    @Published var recentAIMLModels: [String] = AppStorageContext.defaults.stringArray(forKey: "recentAIMLModels") ?? [] {
        didSet { AppStorageContext.defaults.set(recentAIMLModels, forKey: "recentAIMLModels") }
    }
    func toggleFavoriteAIMLModel(_ id: String) {
        if let i = favoriteAIMLModels.firstIndex(of: id) { favoriteAIMLModels.remove(at: i) }
        else { favoriteAIMLModels.insert(id, at: 0) }
    }
    func recordRecentAIMLModel(_ id: String) {
        var r = recentAIMLModels.filter { $0 != id }
        r.insert(id, at: 0)
        recentAIMLModels = Array(r.prefix(8))
    }

    /// Set once the alias-keyed favourites/recents have been rewritten to canonical ids. The
    /// transform is idempotent, so losing this flag costs a redundant pass, not correctness.
    private static let aliasMigrationKey = "aliasCanonicalizationV1"

    /// One-time canonicalize + dedupe of the two alias-keyed id lists (design § 4.3). Called from
    /// `init()` after `restoreSelection()`, so the alias index is already built.
    func canonicalizePersistedModelLists() {
        guard !AppStorageContext.defaults.bool(forKey: Self.aliasMigrationKey) else { return }
        favoriteAIMLModels = AliasMigration.canonicalizedUnique(favoriteAIMLModels)
        recentAIMLModels = Array(AliasMigration.canonicalizedUnique(recentAIMLModels).prefix(8))
        AppStorageContext.defaults.set(true, forKey: Self.aliasMigrationKey)
    }
    @Published var aimlapiKey: String = KeychainHelper.loadAIMLAPIKey() ?? ""
    @Published var imgbbApiKey: String = KeychainHelper.loadImgBBAPIKey() ?? ""

    @Published var selectedAIMLModel: String = "" {
        didSet {
            defer { saveSelection() }
            guard provider == .aimlapi else { return }
            // Clear custom JSON when model changes - return to UI-controlled mode
            customAIMLPayload = nil
            customAIMLEndpoint = nil
        }
    }
    @Published var selectedImageSize: String = "square_hd"
    @Published var selectedResolutionString: String = "2048x2048"
    @Published var selectedImageHeight: Int = 2048
    @Published var selectedImageWidth: Int = 2048
    @Published var aimlAdvancedParams: ModelParameters = ModelParameters() {
        didSet {
            guard provider == .aimlapi else { return }
            // Clear custom JSON when params change - return to UI-controlled mode
            customAIMLPayload = nil
            customAIMLEndpoint = nil
        }
    }
    @Published var comfyBatchSize: Int = 1
    @AppStorage("comfyGenerationTimeout", store: AppStorageContext.defaults) var comfyGenerationTimeout: Int = 300 // seconds (5 minutes default)
    @AppStorage("comfyShowAllNodes", store: AppStorageContext.defaults) var comfyShowAllNodes: Bool = false // Show all nodes vs auto-detected only
    @AppStorage("comfySelectedImageNodeIDs", store: AppStorageContext.defaults) var comfySelectedImageNodeIDsJSON: String = "[]" // Persisted as JSON array
    /// What the form is currently making. The stored source of truth for the task axis;
    /// `isVideoMode` below is a compatibility read for the ~24 call sites that predate it.
    @Published var task: CreateTask = .image {
        didSet {
            defer { saveSelection() }
            guard provider == .aimlapi else { return }
            // Clear custom JSON when the task changes - return to UI-controlled mode.
            // Unguarded, and correctly so: `task` has exactly one write site in the app, the Video
            // Mode toggle's `set:` closure, so every assignment here *is* the user's explicit action —
            // unlike `selectedAIMLModel`, which SelectionHealer can also reassign automatically. A
            // payload built for one task also has little chance of being valid for the other's
            // params/endpoint, so clearing it here is intentional, not a gap.
            customAIMLPayload = nil
            customAIMLEndpoint = nil
        }
    }

    /// Bridge for the pre-`CreateTask` call sites. Not `@Published` — a computed property
    /// has no projected value, so nothing can bind `$isVideoMode`; bind to `task` instead.
    var isVideoMode: Bool {
        get { task == .video }
        set { task = newValue ? .video : .image }
    }
    @Published var customAIMLPayload: String? = nil
    @Published var customAIMLEndpoint: String? = nil
    @AppStorage("imageSubmissionMethod", store: AppStorageContext.defaults) var imageSubmissionMethod: ImageSubmissionMethod = .imgBB
    @AppStorage("base64ConvertToJPG", store: AppStorageContext.defaults) var base64ConvertToJPG: Bool = true
    @AppStorage("base64Scale50Percent", store: AppStorageContext.defaults) var base64Scale50Percent: Bool = false
    @Published var selectedGeminiModel: String = "gemini-3-pro-image-preview" {
        didSet { saveSelection() }
    }
    @Published var availableGeminiModels: [GeminiModel] = []
    @Published var isFetchingGeminiModels: Bool = false
    @Published var geminiAdvancedParams: ModelParameters = ModelParameters(
        geminiResolution: "1K",
        aspectRatio: "1:1"
    )

    // MARK: - Gemini Model Cache
    private static let geminiModelsCacheKey = "cachedGeminiModels"
    private static let geminiModelsCacheTimestampKey = "cachedGeminiModelsTimestamp"
    private static let geminiCacheExpiryHours: Double = 24

    /// The order the Gemini re-pick reaches for when the current selection is unusable. Was
    /// duplicated in `loadCachedGeminiModels()` and `fetchAvailableGeminiModels(forceRefresh:)` with
    /// two different ladders; this is the union, newest first. Absorbed here rather than into
    /// `Catalog` because Stage 3 leaves the Gemini merge defined but unwired (design § 3.3).
    private static let geminiPreferenceOrder = [
        "gemini-3-pro-image-preview",
        "gemini-3-pro-image",
        "gemini-3.1-flash-image",
        "gemini-2.5-flash-image",
    ]

    /// Load cached Gemini models from UserDefaults
    func loadCachedGeminiModels() {
        guard let data = AppStorageContext.defaults.data(forKey: Self.geminiModelsCacheKey),
              let cached = try? JSONDecoder().decode([GeminiModel].self, from: data) else {
            return
        }
        availableGeminiModels = cached.filter { GeminiClient.supportedImageModels.contains($0.shortName) }
        Log.debug("Gemini: Loaded \(cached.count) cached models")

        // Auto-select best model if none selected. `hasCustomPayload: false` because the custom
        // JSON editor is AI/ML-only — there is no Gemini payload to protect.
        if let healed = SelectionHealer.heal(
            selected: selectedGeminiModel,
            offered: cached.map(\.shortName),
            preferring: Self.geminiPreferenceOrder,
            hasCustomPayload: false
        ) {
            selectedGeminiModel = healed
        }
    }

    /// Save Gemini models to UserDefaults cache
    func cacheGeminiModels(_ models: [GeminiModel]) {
        availableGeminiModels = models
        if let data = try? JSONEncoder().encode(models) {
            AppStorageContext.defaults.set(data, forKey: Self.geminiModelsCacheKey)
            AppStorageContext.defaults.set(Date().timeIntervalSince1970, forKey: Self.geminiModelsCacheTimestampKey)
            Log.debug("Gemini: Cached \(models.count) models")
        }
    }

    /// Check if the Gemini model cache is stale (older than 24 hours)
    var isGeminiModelCacheStale: Bool {
        guard let timestamp = AppStorageContext.defaults.object(forKey: Self.geminiModelsCacheTimestampKey) as? Double else {
            return true  // No timestamp = never cached
        }
        let cacheDate = Date(timeIntervalSince1970: timestamp)
        let hoursSinceCache = Date().timeIntervalSince(cacheDate) / 3600
        return hoursSinceCache > Self.geminiCacheExpiryHours
    }

    /// Clear the Gemini model cache (for manual refresh)
    func clearGeminiModelCache() {
        availableGeminiModels = []
        AppStorageContext.defaults.removeObject(forKey: Self.geminiModelsCacheKey)
        AppStorageContext.defaults.removeObject(forKey: Self.geminiModelsCacheTimestampKey)
        Log.debug("Gemini: Cache cleared")
    }

    /// Advanced mode: list every image/video model the API serves, not only the ones GenStation has
    /// a parameter preset for. Migrated from the key `useSupportedModelsOnly`, whose name meant the
    /// opposite of both its label and its behaviour — see `SettingsMigration`.
    @AppStorage(SettingsMigration.showAllAIMLModelsKey, store: AppStorageContext.defaults) var showAllAIMLModels: Bool = false
    @AppStorage("hasCompletedMandatoryOnboarding", store: AppStorageContext.defaults)  var hasCompletedMandatory = false
    @AppStorage("hasSeenAPIKeySetup", store: AppStorageContext.defaults) var hasSeenAPIKeySetup = false
    @AppStorage("hasSeenPrettyOnboarding", store: AppStorageContext.defaults)  var hasSeenPrettyOnboarding = false
    @AppStorage("hasSeenOutputFolderSetup", store: AppStorageContext.defaults) var hasSeenOutputFolderSetup = false
    @AppStorage("comfyUIWarningAccepted", store: AppStorageContext.defaults) var comfyUIWarningAccepted: Bool = false

    // Auto-present generated images (single generation only, not batch)
    @AppStorage("autoPresentGeneratedImages", store: AppStorageContext.defaults) var autoPresentGeneratedImages: Bool = true
    @AppStorage("saveOutputAsJPEG", store: AppStorageContext.defaults) var saveOutputAsJPEG: Bool = true

    // User notifications for video job completion/failure/expiry (JobNotifier reads the same key)
    @AppStorage(JobNotifier.enabledKey, store: AppStorageContext.defaults) var jobNotificationsEnabled: Bool = true

#if os(macOS)
    // MARK: Agent Access (MCP server, WS-7) — MCPService reads the same keys.
    @AppStorage(MCPService.enabledDefaultsKey, store: AppStorageContext.defaults) var mcpServerEnabled: Bool = true
    @AppStorage(MCPService.confirmFirstDefaultsKey, store: AppStorageContext.defaults) var mcpConfirmFirst: Bool = true
    /// Standing per-session dollar budget, required whenever confirm-first is off.
    @AppStorage(MCPService.standingBudgetDefaultsKey, store: AppStorageContext.defaults) var mcpStandingBudgetUSD: Double = 0
#endif

    weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    internal func updateCustomPayloadAndEndpoint() {
        guard !selectedAIMLModel.isEmpty, let model = Catalog.model(for: selectedAIMLModel) else {
            // No catalog row to build a payload update from (empty selection, or a served-but-
            // unregistered advanced-mode id such as "alibaba/qwen-image-3") — nothing to do.
            //
            // This used to write a `{"model": ..., "prompt": "[prompt]"}` stub into
            // `customAIMLPayload` here whenever it was nil. That is a payload the user never
            // authored, but `SelectionHealer.heal` (Catalog/SelectionHealer.swift) can't tell the
            // difference from a hand-edited one — it treats any non-nil `customAIMLPayload` as
            // authored and refuses to heal the selection ever again, stranding an empty or
            // unregistered selection permanently (C2). Nothing needs the stub: the JSON editor
            // (`AdvancedAIMLSettingsView.updatePayloadAndEndpoint()`) already falls back to its own
            // `computeDefaultPayload()` — built from `Catalog.resolve`, which never returns nil,
            // not even for an empty id — whenever `customAIMLPayload` is nil, so display is
            // unaffected by not persisting one here.
            Log.debug("Skipping update due to invalid or empty model ID")
            return
        }
        // Update customAIMLPayload only if it was previously set (user-modified)
        if customAIMLPayload != nil {
            var bodyDict: [String: Any]
            if let customPayload = customAIMLPayload,
               let data = customPayload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Update existing payload
                bodyDict = json
                bodyDict["model"] = selectedAIMLModel
            } else {
                // Fallback to default payload
                bodyDict = [
                    "model": selectedAIMLModel,
                    "prompt": appState?.prompt.isEmpty ?? true ? "[prompt]" : appState?.prompt ?? "[prompt]"
                ]
            }
            // Always update image placeholders
            if model.isI2I && !(appState?.ui.imageSlots.isEmpty ?? true) {
                if model.acceptsMultiImages {
                    bodyDict[model.imageInputParam] = appState?.ui.imageSlots.enumerated().map { "[image_slot_\($0.offset + 1)]" } ?? ["[image_slot_1]"]
                } else {
                    bodyDict[model.imageInputParam] = "[image_slot_1]"
                }
            } else {
                bodyDict.removeValue(forKey: model.imageInputParam)
            }
            // Serialize payload
            if let newData = try? JSONSerialization.data(withJSONObject: bodyDict, options: [.prettyPrinted, .sortedKeys]),
               let newPayload = String(data: newData, encoding: .utf8) {
                customAIMLPayload = newPayload
            } else {
                customAIMLPayload = """
                        {
                            "model": "\(selectedAIMLModel)",
                            "prompt": "[prompt]"
                        }
                        """
            }
        }
        // Update customAIMLEndpoint only if it was previously set
        if customAIMLEndpoint != nil {
            // Only recompute an endpoint the user has already overridden. This guard's job is to
            // bail out for a model id that has no provider component at all, preserving today's
            // customAIMLEndpoint = nil behavior.
            guard selectedAIMLModel.contains("/") else {
                customAIMLEndpoint = nil
                return
            }
            if isVideoMode {
                // The registry's per-model generationEndpoint is what a non-overridden generation
                // posts to (ContentView+Generation.swift:1484), so it is what this override must
                // reset to. videoEndpoint(modelID:) synthesizes a path from the id's first
                // component and reproduces the registry for only 38 of 129 video ids — using it
                // here silently redirected the other 91 (e.g. luma/ray-2 to
                // .../v2/generate/video/luma/generation instead of .../v2/video/generations).
                // Same precedence the payload editor's computeDefaultEndpoint() already uses.
                customAIMLEndpoint = Catalog.model(for: selectedAIMLModel)?.generationEndpoint
                    ?? AIMLEndpoints.videoEndpoint(modelID: selectedAIMLModel).absoluteString
            } else {
                // Mask-capable gpt-image models (gpt-image-1, gpt-image-2) edit via /v1/images/edits when
                // an input image is present; everything else (incl. gpt-image-1.5/-mini) uses /generations.
                let supportsMask = Catalog.model(for: selectedAIMLModel)?.supportsMask ?? false
                customAIMLEndpoint = AIMLEndpoints.imageEndpoint(
                    supportsMask: supportsMask,
                    hasInputImages: !(appState?.ui.imageSlots.isEmpty ?? true)
                ).absoluteString
            }
        }
    }
    /// UserDefaults key holding the JSON `SelectionState` blob.
    private static let selectionStateKey = "selectionState"

    /// True while `withSelectionWritesSuppressed` is running its `body`, so the `didSet` observers
    /// don't write the values straight back out again. Set and cleared only there — see its doc
    /// comment for why `restoreSelection()` no longer owns any part of this flag.
    private var isRestoringSelection = false

    init() {
        // Restore the persisted selection FIRST, and hold the write-back suppressed across the
        // healing that follows. `loadCachedGeminiModels()` re-picks, and `restoreSelection()`'s
        // `defer` is function-scoped, so by the time it ran the flag was already false and that
        // re-pick wrote straight back to "selectionState" during launch.
        withSelectionWritesSuppressed {
            restoreSelection()
            // The persisted favourites/recents were written before the collapse, so they may
            // hold alias spellings. Runs after restoreSelection() so the alias index is built.
            canonicalizePersistedModelLists()
            loadCachedGeminiModels()
        }
        // One deliberate save of whatever launch settled on, rather than one per observer.
        saveSelection()
    }

    /// Runs `body` with `saveSelection()` suppressed, restoring the previous state afterwards.
    /// This is now the **only** place `isRestoringSelection` is set — `restoreSelection()` used to
    /// carry its own `defer`-based handling, but that `defer` is function-scoped: it fired the
    /// moment `restoreSelection()` returned, part-way through this method's `body`, which turned
    /// the flag back off before `loadCachedGeminiModels()` ran and let its Gemini re-pick write
    /// straight back to `"selectionState"` mid-launch — the exact bug this method exists to close.
    /// Nested calls are safe: an inner call restores the flag to whatever the outer call had set,
    /// not unconditionally to `false`.
    private func withSelectionWritesSuppressed(_ body: () -> Void) {
        let previous = isRestoringSelection
        isRestoringSelection = true
        body()
        isRestoringSelection = previous
    }

    /// Binds this state to its owner and starts the subscriptions that need it.
    ///
    /// **The subscription cannot live in `init()`.** `AppState.init` runs
    /// `self.settings = SettingsState()` and only then wires the two together, so `appState` is
    /// unavoidably nil while `SettingsState.init` is executing: an `appState?.ui.$imageSlots.sink`
    /// written there short-circuits on the optional chain and no subscription is ever created. That
    /// is exactly what shipped, which is why `updateCustomPayloadAndEndpoint()` — its only caller —
    /// had never run. Assignment and subscription are one call here so the two cannot drift apart
    /// again.
    func attach(to appState: AppState) {
        self.appState = appState

        // Subscribe to imageSlots changes
        appState.ui.$imageSlots.sink { [weak self] _ in
            Task {
                guard let self = self, self.provider == .aimlapi else { return }
                self.updateCustomPayloadAndEndpoint()
            }
        }.store(in: &cancellables)
    }

    /// Assigning here trips the `didSet` of every property below, each of which calls
    /// `saveSelection()`. The caller (`init()`, via `withSelectionWritesSuppressed`) is responsible
    /// for holding `isRestoringSelection` true across this call — it is not set here.
    ///
    /// It used to be set here, with a `defer` to clear it. That was wrong: a `defer` is
    /// function-scoped, so it cleared the flag the moment *this* method returned, not when the
    /// caller's whole restore-then-heal sequence was done — reopening `saveSelection()`'s guard
    /// while `init()`'s `loadCachedGeminiModels()` still had a re-pick to make.
    private func restoreSelection() {
        guard let restored = SelectionState.decode(
            AppStorageContext.defaults.data(forKey: Self.selectionStateKey)
        ) else { return }

        provider = restored.provider
        task = restored.task
        if let gemini = restored.model(for: .gemini) { selectedGeminiModel = gemini }
        if let grok = restored.model(for: .grok) {
            selectedGrokModel = Catalog.model(for: grok)?.provider == .grok ? grok : "grok-imagine-image-2.0"
        }
        // The blob was written before the collapse, so the AI/ML id may be an alias spelling. An id
        // the catalog does not know is kept as-is: advanced mode persists raw API ids that have no
        // catalog row, and rewriting one to nothing would silently reset the user's selection.
        if let aiml = restored.model(for: .aimlapi) {
            selectedAIMLModel = Catalog.canonicalID(for: aiml) ?? aiml
        }
    }

    /// Records the current selection. Called from the `didSet` of every field it covers.
    private func saveSelection() {
        guard !isRestoringSelection else { return }
        var state = SelectionState(provider: provider, task: task)
        state = state
            .settingModel(selectedGeminiModel, for: .gemini)
            .settingModel(selectedGrokModel, for: .grok)
            .settingModel(selectedAIMLModel, for: .aimlapi)
        guard let data = try? state.encoded() else { return }
        AppStorageContext.defaults.set(data, forKey: Self.selectionStateKey)
        Log.debug("SelectionState: saved (gemini=\(selectedGeminiModel), aiml=\(selectedAIMLModel))")
    }

    func fetchAvailableGeminiModels(forceRefresh: Bool = false) async {
        guard !apiKey.isEmpty else { return }
        guard !isFetchingGeminiModels else { return }

        // If we have cached models and cache is fresh, skip network fetch
        if !forceRefresh && !availableGeminiModels.isEmpty && !isGeminiModelCacheStale {
            Log.debug("Gemini: Using cached models (not stale)")
            return
        }

        // Clear cache if forcing refresh
        if forceRefresh {
            await MainActor.run { clearGeminiModelCache() }
        }

        await MainActor.run { isFetchingGeminiModels = true }
        defer { Task { @MainActor in isFetchingGeminiModels = false } }

        let url = GeminiClient.modelsURL(apiKey: apiKey, pageSize: 1000)

        do {
            let (data, httpResponse) = try await URLSession.shared.data(from: url)
            guard let http = httpResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw NSError(domain: "Gemini", code: (httpResponse as? HTTPURLResponse)?.statusCode ?? -1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not load Gemini models. Check the API key and try refreshing."])
            }
            struct Response: Decodable {
                let models: [GeminiModel]
            }
            let response = try JSONDecoder().decode(Response.self, from: data)

            let onlyImageModels = response.models
                .filter { $0.canGenerateContent }
                .filter { GeminiClient.supportedImageModels.contains($0.shortName) }

            // Deduplicate by displayName, prefer the newest/canonical version
            let uniqueModels = Dictionary(grouping: onlyImageModels, by: \.displayName)
                .compactMap { _, group -> GeminiModel? in
                    // Prefer the exact known image IDs first (stable before preview)
                    let priorityOrder = [
                        "gemini-3-pro-image",
                        "gemini-3-pro-image-preview",
                        "gemini-3.1-flash-image",
                        "gemini-2.5-flash-image"
                    ]
                    for priority in priorityOrder {
                        if let match = group.first(where: { $0.shortName == priority }) {
                            return match
                        }
                    }
                    // Fallback: shortest name = newest
                    return group.min(by: { $0.shortName.count < $1.shortName.count })
                }
                .sorted { $0.displayName < $1.displayName }

            await MainActor.run {
                cacheGeminiModels(uniqueModels)  // Save to UserDefaults cache

                // Behaviour change, deliberate: this used to be unconditional, so a successful
                // /models fetch overwrote a model the user had chosen on purpose. The healer only
                // re-picks when the current selection is not in the list that came back.
                if let healed = SelectionHealer.heal(
                    selected: selectedGeminiModel,
                    offered: uniqueModels.map(\.shortName),
                    preferring: Self.geminiPreferenceOrder,
                    hasCustomPayload: false
                ) {
                    selectedGeminiModel = healed
                }
            }
        } catch {
            Log.debug("Gemini model list fetch failed: \(error)")
            // Fail silently – UI will show fallback
        }
    }
}
/// Represents the connection status of the ComfyUI server
enum ComfyServerStatus: Equatable {
    case unknown
    case checking
    case connected(nodeCount: Int)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

class GenerationState: ObservableObject {
    @Published var comfyServerStatus: ComfyServerStatus = .unknown
    @Published var comfyWorkflow: [String: Any]? = nil
    @Published var savedWorkflowID: UUID?
    @Published var comfyPromptNodeID: String = ""
    @Published var comfyPromptKey: String = "text"
    @Published var comfyImageNodeID: String = ""
    @Published var comfyImageKey: String = "image"
    @Published var comfyOutputNodeID: String = ""
    @Published var promptNodes: [NodeInfo] = []
    @Published var outputNodes: [NodeInfo] = []
    @Published var imageNodes: [NodeInfo] = []
    @Published var allNodes: [NodeInfo] = []  // All nodes for "Show all nodes" mode
    @Published var workflowError: String? = nil
    @Published var showNonAPIFormatWarning = false
    @Published var selectedImageNodeIDs: Set<String> = []

    /// Monotonic counter guarding against a slow workflow import overwriting a newer one.
    /// Bumped whenever an import starts; an in-flight import applies its result only if the
    /// token it captured is still current. Read/written on the main actor only. (latest-wins)
    var workflowImportToken: Int = 0

    // Additional inputs for ComfyUI (beyond auto-detected prompt/image nodes)
    @Published var additionalInputs: [AdditionalInput] = []

    /// Image data for additional image inputs, keyed by AdditionalInput.id
    @Published var additionalInputImages: [UUID: AdditionalInputImage] = [:]

    // MARK: - Fetched ComfyUI Options
    /// Sampler options fetched from ComfyUI /object_info endpoint
    @Published var fetchedSamplers: [String]? = nil
    /// Scheduler options fetched from ComfyUI /object_info endpoint
    @Published var fetchedSchedulers: [String]? = nil
    /// Checkpoint/model options fetched from ComfyUI /object_info endpoint
    @Published var fetchedCheckpoints: [String]? = nil
    /// VAE options fetched from ComfyUI /object_info endpoint
    @Published var fetchedVAEs: [String]? = nil
    /// LoRA options fetched from ComfyUI /object_info endpoint
    @Published var fetchedLoRAs: [String]? = nil

    // MARK: - Compatible Node Filters

    /// Nodes suitable for text inputs (prompts, strings, etc.)
    var textCompatibleNodes: [NodeInfo] {
        let textNodeTypes = Set([
            "CLIPTextEncode", "CLIPTextEncodeSDXL", "CLIPTextEncodeSD3",
            "Text", "String", "PromptComposer", "ShowText",
            "StringFunction", "TextConcatenate", "TextBox"
        ])

        return allNodes.filter { node in
            guard let classType = node.classType else { return false }
            let lower = classType.lowercased()
            return textNodeTypes.contains(classType) ||
                   lower.contains("text") ||
                   lower.contains("prompt") ||
                   lower.contains("string") ||
                   (lower.contains("clip") && lower.contains("encode"))
        }
    }

    /// Nodes suitable for image inputs (ControlNet, IPAdapter, masks, etc.)
    var imageCompatibleNodes: [NodeInfo] {
        let imageNodeTypes = Set([
            "LoadImage", "LoadImageMask", "LoadImageFromURL",
            "IPAdapter", "IPAdapterAdvanced", "IPAdapterFaceID",
            "ControlNetApply", "ControlNetApplyAdvanced",
            "ImageReceiver", "ImageUpload", "LoadImageBase64",
            "InpaintImageBatch", "ImageCompositeMasked",
            "PrepImageForClipVision", "CLIPVisionEncode"
        ])

        return allNodes.filter { node in
            guard let classType = node.classType else { return false }
            let lower = classType.lowercased()
            return imageNodeTypes.contains(classType) ||
                   Self.imageLoadNodeTypes.contains(classType) ||
                   lower.contains("loadimage") ||
                   lower.contains("imageload") ||
                   lower.contains("ipadapter") ||
                   (lower.contains("controlnet") && lower.contains("load")) ||
                   (lower.contains("mask") && lower.contains("image"))
        }
    }

    /// Returns filtered nodes based on input type
    func compatibleNodes(for inputType: AdditionalInputType) -> [NodeInfo] {
        switch inputType {
        case .text: return textCompatibleNodes
        case .image: return imageCompatibleNodes
        }
    }

  
    func loadWorkflowFromFile(comfyJSONURL: URL?) {
        selectedImageNodeIDs = []
        additionalInputs = []
        guard let url = comfyJSONURL else {
            resetNodes(withError: "No URL provided.")
            return
        }
  
        var targetURL = url
        if let bookmarkData = AppStorageContext.defaults.data(forKey: "comfyJSONBookmark") {
            var isStale = false
            do {
                #if os(macOS)
                let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
                #else
                let resolveOptions: URL.BookmarkResolutionOptions = []
                #endif
                targetURL = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, bookmarkDataIsStale: &isStale)
  
                if isStale {
                    #if os(macOS)
                    let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                    #else
                    let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
                    #endif
                    if let newBookmark = try? targetURL.bookmarkData(options: bookmarkOptions) {
                        AppStorageContext.defaults.set(newBookmark, forKey: "comfyJSONBookmark")
                    }
                }
            } catch {
                resetNodes(withError: "Bookmark resolution error: \(error.localizedDescription)")
                return
            }
        }
  
        var coordError: NSError?
        var innerError: Error?
        var json: [String: Any]?
  
        NSFileCoordinator().coordinate(readingItemAt: targetURL, options: [], error: &coordError) { coordinatedURL in
            if coordinatedURL.startAccessingSecurityScopedResource() {
                defer { coordinatedURL.stopAccessingSecurityScopedResource() }
  
                do {
                    let ext = coordinatedURL.pathExtension.lowercased()
                    if ext == "json" {
                        let data = try Data(contentsOf: coordinatedURL)
                        json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    } else if ext == "png" {
                        if let workflowStr = self.extractWorkflowFromPNG(url: coordinatedURL) {
                            if let data = workflowStr.data(using: .utf8) {
                                json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                            } else {
                                innerError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert workflow string to data."])
                            }
                        } else {
                            innerError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No embedded ComfyUI workflow found in the PNG."])
                        }
                    } else {
                        innerError = NSError(domain: "FileTypeError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type. Please select a JSON or PNG file."])
                    }
                } catch {
                    innerError = error
                }
            } else {
                innerError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
            }
        }
  
        if let coordError = coordError {
            resetNodes(withError: "Coordination error: \(coordError.localizedDescription)")
            return
        }
        if let innerError = innerError {
            resetNodes(withError: "Failed to load or parse workflow: \(innerError.localizedDescription)")
            return
        }
        guard let json = json else {
            resetNodes(withError: "Failed to load or parse workflow.")
            return
        }
  
        processJSON(json: json)
    }

    func extractWorkflowFromPNG(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        var offset: Int = 8
        let totalLength = data.count
        var promptStr: String? = nil   // API format (preferred)
        var workflowStr: String? = nil // UI format (fallback)

        // Parse PNG chunks looking for both "prompt" and "workflow"
        while offset + 11 < totalLength {
            let lengthRange = offset..<(offset + 4)
            let lengthData = data.subdata(in: lengthRange)
            let lengthBytes = [UInt8](lengthData)
            let length = (UInt32(lengthBytes[0]) << 24) | (UInt32(lengthBytes[1]) << 16) |
                (UInt32(lengthBytes[2]) << 8) | UInt32(lengthBytes[3])

            let fullChunkSize = 12 + Int(length)
            let fullChunkEnd = offset + fullChunkSize
            guard fullChunkEnd <= totalLength else { break }

            let typeStart = offset + 4
            let typeRange = typeStart..<(typeStart + 4)
            let typeData = data.subdata(in: typeRange)
            let typeBytes = [UInt8](typeData)
            let chunkType = String(bytes: typeBytes, encoding: .ascii) ?? ""

            if chunkType == "tEXt" {
                let textStart = typeStart + 4
                let textRange = textStart ..< (textStart + Int(length))
                let textData = data.subdata(in: textRange)
                if let textStr = String(data: textData, encoding: .utf8),
                   let nullIndex = textStr.firstIndex(of: "\0") {
                    let keyword = String(textStr[..<nullIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                    let valueStart = textStr.index(after: nullIndex)
                    let value = String(textStr[valueStart...]).trimmingCharacters(in: .whitespaces)

                    if keyword == "prompt" {
                        promptStr = value
                    } else if keyword == "workflow" && workflowStr == nil {
                        workflowStr = value
                    }

                    // If we found the prompt (API format), we can stop early
                    if promptStr != nil {
                        break
                    }
                }
            }

            offset = fullChunkEnd
        }

        // Prefer "prompt" (API format) over "workflow" (UI format)
        if let prompt = promptStr {
            return prompt
        }

        if let workflow = workflowStr {
            return workflow
        }

        // Fallback: try CGImageSource metadata
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let rawProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil),
              let props = rawProps as? [String: Any],
              let pngDict = props["{PNG}"] as? [String: Any] else { return nil }

        // Prefer prompt over workflow in metadata too
        return pngDict["prompt"] as? String ?? pngDict["Prompt"] as? String ?? pngDict["workflow"] as? String ?? pngDict["Workflow"] as? String
    }

    /// Public method to process workflow JSON and detect nodes
    /// Use this when you already have the JSON loaded (e.g., after format conversion)
    func processWorkflowForNodes(json: [String: Any]) {
        selectedImageNodeIDs = []
        additionalInputs = []
        showNonAPIFormatWarning = false
        processJSON(json: json)

        // Auto-select all detected image nodes
        if !imageNodes.isEmpty {
            for node in imageNodes {
                selectedImageNodeIDs.insert(node.id)
            }
        }
    }

    // Node types that can load images (expanded detection)
    private static let imageLoadNodeTypes: Set<String> = [
        "LoadImage", "LoadImageMask", "LoadImageFromURL",
        "IPAdapterLoader", "IPAdapterModelLoader", "IPAdapterAdvanced", "IPAdapter",
        "ControlNetLoader", "ControlNetApply", "ControlNetApplyAdvanced",
        "ImageReceiver", "ImageUpload", "LoadImageBase64",
        "VHS_LoadImages", "VHS_LoadVideo",  // Video Helper Suite
        "LoadImageAsMask", "InpaintImageBatch"
    ]

    // Node types that output images or videos
    private static let mediaOutputNodeTypes: Set<String> = [
        // Image output nodes
        "SaveImage", "PreviewImage", "SaveAnimatedWEBP", "SaveAnimatedPNG",
        "ImageSave", "SaveImageWebsocket",
        // Video output nodes
        "VHS_VideoCombine",  // Video Helper Suite - outputs to "gifs" key
        "SaveVideo", "VideoSave", "VHS_SaveVideo",
        "SaveAnimatedGIF", "GIFSave",
        "SaveWEBM", "WEBMSave"
    ]

    // Node types that specifically output video/animation (for special handling)
    static let videoOutputNodeTypes: Set<String> = [
        "VHS_VideoCombine", "SaveVideo", "VideoSave", "VHS_SaveVideo",
        "SaveAnimatedWEBP", "SaveAnimatedPNG", "SaveAnimatedGIF", "GIFSave",
        "SaveWEBM", "WEBMSave"
    ]

    private func processJSON(json: [String: Any]) {
        var promptNodes: [NodeInfo] = []
        var outputNodes: [NodeInfo] = []
        var imageNodes: [NodeInfo] = []
        var allNodes: [NodeInfo] = []

        // Prompt nodes traced to a sampler's positive/negative conditioning input
        // (API format only; UI format falls back to title hints below).
        var positivePromptIDs: Set<String> = []
        var negativeOnlyPromptIDs: Set<String> = []

        // Helper to check if a node type matches image loading patterns
        func isImageLoadNode(_ classType: String) -> Bool {
            if Self.imageLoadNodeTypes.contains(classType) { return true }
            let lower = classType.lowercased()
            return lower.contains("loadimage") || lower.contains("imageload") ||
                   lower.contains("ipadapter") || lower.contains("controlnet") && lower.contains("load")
        }

        // Helper to check if a node type matches output patterns (images or videos)
        func isOutputNode(_ classType: String) -> Bool {
            if Self.mediaOutputNodeTypes.contains(classType) { return true }
            let lower = classType.lowercased()
            // Image output patterns
            if lower.contains("saveimage") || lower.contains("previewimage") { return true }
            // Video/animation output patterns
            if lower.contains("savevideo") || lower.contains("videosave") { return true }
            if lower.contains("videocombine") || lower.contains("combinevideo") { return true }
            if lower.contains("savegif") || lower.contains("gifsave") { return true }
            if lower.contains("savewebm") || lower.contains("webmsave") { return true }
            if lower.contains("saveanimated") { return true }
            return false
        }

        func isPromptNode(_ classType: String) -> Bool {
            let lower = classType.lowercased()
            // Exclude loader nodes - they load models, not encode text prompts
            if lower.contains("loader") { return false }
            // Match text encoding nodes
            if lower.contains("clip") && lower.contains("encode") { return true }
            // Match generic text nodes but not loaders
            if lower.contains("text") && !lower.contains("load") { return true }
            // Match string/primitive nodes (PrimitiveStringMultiline, StringMultiline, etc.)
            if lower.contains("string") && !lower.contains("load") { return true }
            return false
        }

        if let nodesArray = json["nodes"] as? [[String: Any]] {
            // UI format (from standard ComfyUI save)
            for node in nodesArray {
                guard let nodeID = node["id"] as? Int, let classType = node["type"] as? String else { continue }
                let nodeIDStr = String(nodeID)
                let uiTitle = node["title"] as? String
                let baseLabel = uiTitle ?? classType
                let nodeLabel = "Node \(nodeIDStr): \(baseLabel)"

                // Add to allNodes
                allNodes.append(NodeInfo(id: nodeIDStr, label: nodeLabel, promptText: nil, classType: classType))

                if isPromptNode(classType) {
                    var collectedTexts: [String] = []
                    if let widgetsValues = node["widgets_values"] as? [Any] {
                        for value in widgetsValues {
                            if let text = value as? String, !text.isEmpty {
                                collectedTexts.append(text)
                            }
                        }
                    }
                    let promptText = collectedTexts.joined(separator: "\n---\n")
                    let label = promptText.isEmpty ? nodeLabel : "Node \(nodeIDStr): \(baseLabel) — \(promptText.prefix(50))\(promptText.count > 50 ? "..." : "")"
                    // Always add classType-matched nodes even without text (user types prompt)
                    promptNodes.append(NodeInfo(id: nodeIDStr, label: label, promptText: promptText.isEmpty ? nil : promptText, classType: classType))
                } else if isOutputNode(classType) {
                    outputNodes.append(NodeInfo(id: nodeIDStr, label: nodeLabel, promptText: nil, classType: classType))
                } else if isImageLoadNode(classType) {
                    imageNodes.append(NodeInfo(id: nodeIDStr, label: nodeLabel, promptText: nil, classType: classType))
                } else if let uiTitle = uiTitle, uiTitle.lowercased().contains("prompt") {
                    // Title-based fallback: node titled "prompt" but not matched by classType
                    var collectedTexts: [String] = []
                    if let widgetsValues = node["widgets_values"] as? [Any] {
                        for value in widgetsValues {
                            if let text = value as? String, !text.isEmpty {
                                collectedTexts.append(text)
                            }
                        }
                    }
                    if !collectedTexts.isEmpty {
                        let promptText = collectedTexts.joined(separator: "\n---\n")
                        let label = "Node \(nodeIDStr): \(baseLabel) — \(promptText.prefix(50))\(promptText.count > 50 ? "..." : "")"
                        promptNodes.append(NodeInfo(id: nodeIDStr, label: label, promptText: promptText, classType: classType))
                    }
                }

                // UI format carries no sampler-input trace here; use the title as a
                // negativity hint so a "Negative Prompt" node is never auto-selected.
                if let uiTitle = uiTitle, uiTitle.lowercased().contains("negativ") {
                    negativeOnlyPromptIDs.insert(nodeIDStr)
                }
            }
        } else {
            // API format
            // Helper to check if a key is a text-related input key
            func isTextKey(_ key: String) -> Bool {
                let lowerKey = key.lowercased()
                return lowerKey.contains("prompt") || lowerKey.contains("text") ||
                       lowerKey.contains("positiv") || lowerKey.contains("negativ") ||
                       lowerKey.contains("value")
            }

            // Helper to extract text from inputs, following links one level
            func extractTexts(from inputs: [String: Any], in json: [String: Any]) -> [String] {
                var collectedTexts: [String] = []
                for (key, value) in inputs {
                    guard isTextKey(key) else { continue }
                    if let text = value as? String, !text.isEmpty {
                        collectedTexts.append(text)
                    } else if let link = value as? [Any], link.count == 2 {
                        // Follow ComfyUI link [nodeID, outputIndex] one level
                        let sourceID: String
                        if let id = link[0] as? String { sourceID = id }
                        else if let id = link[0] as? Int { sourceID = String(id) }
                        else { continue }
                        if let sourceNode = json[sourceID] as? [String: Any],
                           let sourceInputs = sourceNode["inputs"] as? [String: Any] {
                            for (srcKey, srcValue) in sourceInputs {
                                guard isTextKey(srcKey) else { continue }
                                if let text = srcValue as? String, !text.isEmpty {
                                    collectedTexts.append(text)
                                }
                            }
                        }
                    }
                }
                return collectedTexts
            }

            for (nodeID, node) in json {
                guard let nodeDict = node as? [String: Any], let classType = nodeDict["class_type"] as? String else { continue }
                let metaTitle = (nodeDict["_meta"] as? [String: Any])?["title"] as? String
                let baseLabel = metaTitle ?? classType
                let nodeLabel = "Node \(nodeID): \(baseLabel)"

                // Add to allNodes
                allNodes.append(NodeInfo(id: nodeID, label: nodeLabel, promptText: nil, classType: classType))

                if isPromptNode(classType) {
                    let inputs = nodeDict["inputs"] as? [String: Any] ?? [:]
                    let collectedTexts = extractTexts(from: inputs, in: json)
                    let promptText = collectedTexts.joined(separator: "\n---\n")
                    let label = promptText.isEmpty ? nodeLabel : "Node \(nodeID): \(baseLabel) — \(promptText.prefix(50))\(promptText.count > 50 ? "..." : "")"
                    // Always add classType-matched nodes even without text (user types prompt)
                    promptNodes.append(NodeInfo(id: nodeID, label: label, promptText: promptText.isEmpty ? nil : promptText, classType: classType))
                } else if isOutputNode(classType) {
                    outputNodes.append(NodeInfo(id: nodeID, label: nodeLabel, promptText: nil, classType: classType))
                } else if isImageLoadNode(classType) {
                    imageNodes.append(NodeInfo(id: nodeID, label: nodeLabel, promptText: nil, classType: classType))
                } else if let metaTitle = metaTitle, metaTitle.lowercased().contains("prompt") {
                    // Title-based fallback: node titled "prompt" but not matched by classType
                    let inputs = nodeDict["inputs"] as? [String: Any] ?? [:]
                    let collectedTexts = extractTexts(from: inputs, in: json)
                    if !collectedTexts.isEmpty {
                        let promptText = collectedTexts.joined(separator: "\n---\n")
                        let label = "Node \(nodeID): \(baseLabel) — \(promptText.prefix(50))\(promptText.count > 50 ? "..." : "")"
                        promptNodes.append(NodeInfo(id: nodeID, label: label, promptText: promptText, classType: classType))
                    }
                }
            }

            // Trace which prompt nodes feed positive vs negative conditioning so the
            // default selection never lands on the negative CLIPTextEncode.
            let roles = ComfyUIFormatConverter.classifyConditioningRoles(
                apiWorkflow: json, isPromptNode: isPromptNode
            )
            positivePromptIDs = roles.positive
            negativeOnlyPromptIDs = roles.negative.subtracting(roles.positive)
        }

        // Sort all node lists by ID (numeric sort if possible)
        let sortById: (NodeInfo, NodeInfo) -> Bool = { a, b in
            if let aInt = Int(a.id), let bInt = Int(b.id) {
                return aInt < bInt
            }
            return a.id < b.id
        }

        self.allNodes = allNodes.sorted(by: sortById)
        self.promptNodes = promptNodes.sorted(by: sortById)
        self.outputNodes = outputNodes.sorted(by: sortById)
        self.imageNodes = imageNodes.sorted(by: sortById)

        // Only show error if we have no nodes at all
        if allNodes.isEmpty {
            workflowError = "Invalid workflow format or no nodes found. Please load a valid ComfyUI JSON (API or standard format)."
            selectedImageNodeIDs = []
            return
        }

        // Smart default: prefer a prompt node traced to a sampler's `positive` input,
        // then label hints, then any with text, then first. Nodes that only feed
        // `negative` conditioning (or are titled "negative") are never auto-selected —
        // the user can still pick them manually. Selection runs on the sorted list so
        // dictionary iteration order can't randomize the default (previous bug).
        let sortedPromptNodes = self.promptNodes
        let candidates = sortedPromptNodes.filter { !negativeOnlyPromptIDs.contains($0.id) }
        let defaultPromptNode = sortedPromptNodes.first(where: { positivePromptIDs.contains($0.id) && !negativeOnlyPromptIDs.contains($0.id) })
            ?? candidates.first(where: {
                let lower = $0.label.lowercased()
                return lower.contains("positiv") || (lower.contains("prompt") && !lower.contains("negativ"))
            })
            ?? candidates.first(where: { $0.promptText != nil })
            ?? candidates.first
            // Last resort: if every prompt node is negative-classified, still pick one so
            // prompt injection isn't silently a no-op (the user can re-target manually).
            ?? sortedPromptNodes.first
        comfyPromptNodeID = defaultPromptNode?.id ?? ""
        // Defaults come from the sorted node lists (self.*), not the unsorted locals, so
        // dictionary iteration order can't randomize which output/image node is selected.
        comfyOutputNodeID = self.outputNodes.first?.id ?? ""
        comfyImageNodeID = self.imageNodes.first?.id ?? ""
        workflowError = nil
    }
  
    private func resetNodes(withError error: String) {
        promptNodes = []
        outputNodes = []
        imageNodes = []
        allNodes = []
        workflowError = error
    }
   
}
class HistoryState: ObservableObject {
    weak var appState: AppState?
    private var suppressHistorySave = false
    @Published var history: [HistoryEntry] = [] {
        didSet { if !suppressHistorySave { saveHistory() } }
    }
    @Published var expandedFolderIDs: Set<UUID> = [] {
            didSet {
                saveExpandedState()
            }
        }
    @Published var multiSelection: Set<UUID> = []

    /// Observed per-model cost, rebuilt from the **in-memory** history. Nothing here reads
    /// `history_v2.json`: that file is read once, at launch, by `loadHistoryFromFile()`. A rendered
    /// row does one dictionary subscript; this is the only place the walk happens.
    @Published private(set) var observedCostByModel: [String: ObservedCost] = [:]

    /// False until `history` has been populated from a source we trust — a successful decode,
    /// a confirmed-absent file, a migration, or an explicit Clear History. `saveHistory()`
    /// refuses to write while it is false, which is what keeps an empty in-memory `history`
    /// from overwriting an intact `history_v2.json` after a failed load, and also covers the
    /// launch window before the detached decode `Task` finishes.
    private var historyIsLoaded = false
    var isReadyForAgentOrganization: Bool { historyIsLoaded }

    private var cancellables = Set<AnyCancellable>()
    
    private var historyURL: URL {
            AppStorageContext.current.historyURL
        }
    
    func isEffectivelySelected(for itemID: UUID) -> Bool {
        if multiSelection.contains(itemID) { return true }
        var currentParent = findParentFolderId(for: itemID, in: history)
        while let parentID = currentParent {
            if multiSelection.contains(parentID) { return true }
            currentParent = findParentFolderId(for: parentID, in: history)
        }
        return false
    }
    

    init() {
        loadHistoryFromFile()
        migrateAndSaveIfNeeded()
        // Auto-save expanded state
                $expandedFolderIDs
                    .sink { [weak self] _ in
                        self?.saveExpandedState()
                    }
                    .store(in: &cancellables)
        // Rebuild the observed-cost index at most a few times a second rather than on every
        // history mutation. `@Published` delivers the current value to a new subscriber, so the
        // load above — or the detached decode, whichever finishes last — is picked up here without
        // an explicit first call. This never writes `history`, so it cannot feed its own didSet.
        $history
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] entries in
                self?.observedCostByModel = ObservedCostIndex.build(from: entries)
            }
            .store(in: &cancellables)
    }
    private func loadExpandedState() {
            if let data = AppStorageContext.defaults.data(forKey: "HistoryExpandedFolderIDs"),
               let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
                expandedFolderIDs = decoded
            }
        }

        private func saveExpandedState() {
            if let data = try? JSONEncoder().encode(expandedFolderIDs) {
                AppStorageContext.defaults.set(data, forKey: "HistoryExpandedFolderIDs")
            }
        }
    func expandAllFolders() {
            var allFolderIDs = Set<UUID>()
            func collect(from entries: [HistoryEntry]) {
                for entry in entries {
                    if case .folder(let folder) = entry {
                        allFolderIDs.insert(folder.id)
                        collect(from: folder.children)
                    }
                }
            }
            collect(from: history)
            expandedFolderIDs = allFolderIDs
        }

        func collapseAllFolders() {
            expandedFolderIDs = []
        }
    
    /// Failures that mean "this file cannot be trusted", so the total-record-loss case can
    /// take exactly the same protective path as a file that is not JSON at all.
    private enum HistoryLoadFailure: LocalizedError {
        case everyRecordUnreadable(Int)

        var errorDescription: String? {
            switch self {
            case .everyRecordUnreadable(let count):
                return "All \(count) record(s) in the history file were unreadable."
            }
        }
    }

    /// Copies `history_v2.json` to `history_v2.json.bak` beside it if no backup already
    /// exists there. Returns the backup's path, or nil if the copy failed.
    ///
    /// Called only when records were dropped and the survivors are about to be assigned —
    /// which triggers a save. Without this copy the dropped records are overwritten by the
    /// survivors and are gone from disk permanently.
    ///
    /// Never overwrite an existing backup. Both loaders (`loadHistoryFromFile()` and
    /// `loadHistory()`) run on every launch, and the second can read the history file mid
    /// rewrite by the first's save — observing a partial drop that isn't real and calling
    /// this function again. If that call replaced an existing `.bak`, it would swap the copy
    /// holding the originally dropped records for one that no longer has them, destroying
    /// the only surviving copy. The tradeoff: a genuinely new partial drop months later will
    /// find a stale `.bak` and not overwrite it. That's the right way round — never destroy
    /// a backup automatically.
    private func backUpHistoryFileBeforePartialLoad() -> String? {
        let source = historyURL
        let backup = source.appendingPathExtension("bak")
        guard !FileManager.default.fileExists(atPath: backup.path) else {
            return backup.path
        }
        do {
            try FileManager.default.copyItem(at: source, to: backup)
            return backup.path
        } catch {
            Log.error("History: could not back up the history file before a partial load: \(error)")
            return nil
        }
    }

    /// The user-facing half of a partial load. Silence here is what made record-level loss
    /// invisible in release builds: OSLog debug is not persisted, so the only trace of a
    /// dropped record vanished with the process.
    private func partialLoadAlert(droppedRecordCount: Int, backupPath: String?) -> AlertError {
        let whereItWent: String
        if let backupPath {
            whereItWent = """
            The file as it was found on disk has been copied to:

            \(backupPath)

            That copy still contains the unreadable records. The main history file is about \
            to be rewritten with only the records that loaded, so keep the copy if you want \
            them recovered.
            """
        } else {
            whereItWent = """
            GenStation could not make a backup copy of the file, so those records will be \
            lost the next time history is saved. Quit without saving over the file if you \
            want to preserve them:

            \(historyURL.path)
            """
        }
        return AlertError(
            message: "\(droppedRecordCount) history record(s) could not be read.",
            fullMessage: """
            The rest of your history loaded normally.

            \(whereItWent)
            """
        )
    }

    private func loadHistoryFromFile() {
        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            historyIsLoaded = true  // Nothing on disk to protect — saving is safe.
            history = []
            return
        }

        Task {
            do {
                let data = try Data(contentsOf: historyURL)
                let result = try HistoryFile.decode(data)
                // Nothing survived. Accepting that as "an empty history" would assign []
                // and let the next save write it over the file — the same total loss the
                // catch below exists to prevent, arriving through a different door.
                if result.entries.isEmpty && result.droppedRecordCount > 0 {
                    throw HistoryLoadFailure.everyRecordUnreadable(result.droppedRecordCount)
                }
                if result.droppedRecordCount > 0 {
                    Log.error("History: skipped \(result.droppedRecordCount) unreadable record(s)")
                }
                // Copy first: the assignment below triggers a save that writes the survivors
                // over the file, at which point the dropped records are unrecoverable.
                let backupPath = result.droppedRecordCount > 0
                    ? self.backUpHistoryFileBeforePartialLoad()
                    : nil
                await MainActor.run {
                    self.historyIsLoaded = true
                    self.history = result.entries
                    if result.droppedRecordCount > 0 {
                        self.appState?.errorItem = self.partialLoadAlert(
                            droppedRecordCount: result.droppedRecordCount,
                            backupPath: backupPath
                        )
                    }
                }
            } catch {
                // Deliberately does NOT assign `history = []`. That assignment trips
                // `didSet { saveHistory() }` and overwrites history_v2.json with an empty
                // array — one unreadable file used to destroy the user's entire history.
                // `historyIsLoaded` also stays false, so the first later mutation cannot
                // write a one-element array over the intact file either.
                Log.error("Failed to load history from file (file left untouched): \(error)")
                // Protecting the file means silently discarding this session's history, so
                // say it once through the existing alert channel rather than letting the
                // user find out later.
                await MainActor.run {
                    self.appState?.errorItem = AlertError(
                        message: "Your generation history could not be read.",
                        fullMessage: """
                        The file has been left untouched on disk, so nothing already saved has \
                        been lost:

                        \(self.historyURL.path)

                        New history from this session will not be saved while this persists. \
                        Quit without saving over the file, and back it up before retrying.

                        Details: \(error.localizedDescription)
                        """
                    )
                }
            }
        }
    }

    private func migrateAndSaveIfNeeded() {
        // Only run if we didn't load anything from file
        guard history.isEmpty else { return }

        guard let oldData = AppStorageContext.defaults.data(forKey: "history") else { return }

        let decoder = JSONDecoder()

        // Try to decode the new format first — leniently, so a partially bad legacy blob
        // still migrates every record it can instead of falling through to the old format.
        if let newFormat = try? HistoryFile.decode(oldData), !newFormat.entries.isEmpty {
            historyIsLoaded = true
            history = newFormat.entries
        }
        // Then try the old format
        else if let oldFormat = try? decoder.decode([HistoryItem].self, from: oldData) {
            historyIsLoaded = true
            history = oldFormat.map { .item($0) }
        }
        // If we loaded anything, save it to the new file-based storage
        else {
            // No valid data found — nothing to migrate
            return
        }

        // Only reach here if we successfully loaded something
        saveHistory()
        AppStorageContext.defaults.removeObject(forKey: "history")
        Log.debug("Successfully migrated \(history.count) history entries to file!")
    }


    
    // Helper to find parent folder ID (unchanged)
        func findParentFolderId(for itemId: UUID, in entries: [HistoryEntry]) -> UUID? {
            for entry in entries {
                if case .folder(let folder) = entry {
                    if folder.children.contains(where: { $0.id == itemId }) {
                        return folder.id
                    }
                    if let nestedParent = findParentFolderId(for: itemId, in: folder.children) {
                        return nestedParent
                    }
                }
            }
            return nil
        }
    
    func findEntry(by id: UUID) -> HistoryEntry? {
        var found: HistoryEntry?
        func search(in entries: [HistoryEntry]) {
            for entry in entries {
                if entry.id == id { found = entry; return }
                if case .folder(let f) = entry { search(in: f.children) }
            }
        }
        search(in: history)
        return found
    }
    
    var anySelectedIsFolder: Bool {
        // for use elsewhere if needed
        false
    }
  
    // Helper to generate a unique folder name using precomputed names
        private func uniqueFolderName(baseName: String, existingNames: [String]) -> String {
            var candidateName = baseName
            var counter = 1
  
            while existingNames.contains(candidateName) {
                candidateName = "\(baseName) (\(counter))"
                counter += 1
            }
            return candidateName
        }
    

  
    struct FolderOption: Identifiable {
        let id: UUID
        let name: String
  
        func containsAny(ids: Set<UUID>, in entries: [HistoryEntry]) -> Bool {
            func checkSubtree(for folderId: UUID, in subEntries: [HistoryEntry]) -> Bool {
                for entry in subEntries {
                    if ids.contains(entry.id) {
                        return true
                    }
                    if case .folder(let folder) = entry {
                        if checkSubtree(for: folderId, in: folder.children) {
                            return true
                        }
                    }
                }
                return false
            }
  
            for entry in entries {
                if case .folder(let folder) = entry, folder.id == self.id {
                    return checkSubtree(for: self.id, in: folder.children)
                } else if case .folder(let folder) = entry {
                    if containsAny(ids: ids, in: folder.children) {
                        return true
                    }
                }
            }
            return false
        }
    }
  
    func allFolders() -> [FolderOption] {
        var folders: [FolderOption] = []
        func collectFolders(from entries: [HistoryEntry]) {
            for entry in entries {
                if case .folder(let folder) = entry {
                    folders.append(FolderOption(id: folder.id, name: folder.name))
                    collectFolders(from: folder.children)
                }
            }
        }
        collectFolders(from: history)
        return folders.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
  
    func moveToFolder(entriesWithIds ids: [UUID], toFolderId: UUID?, undoManager: UndoManager?) -> Bool {
        let oldHistory = history
        var snapshot = history
        var movedEntries: [HistoryEntry] = []
        var skippedCount: Int = 0

        // Helper: collect all leaf items from selected entries (including inside selected folders)
        func collectLeafItems(from ids: Set<UUID>) -> [HistoryEntry] {
            var items: [HistoryEntry] = []
            for id in ids {
                if let entry = findEntry(by: id) {
                    switch entry {
                    case .item:
                        items.append(entry)
                    case .folder(let folder):
                        // Recursively collect all items inside this folder
                        items.append(contentsOf: folder.children.flatMap { $0.allItems.map { HistoryEntry.item($0) } })
                    }
                }
            }
            return items
        }

        // Only collect actual HistoryItem entries — folders are ignored completely
        let leafItems = collectLeafItems(from: Set(ids))

        for entry in leafItems {
            guard case .item = entry else { continue }

            if let entryId = entry.asItem?.id {
                // Prevent moving an item into its current parent (no-op)
                let currentParentId = findParentFolderId(for: entryId, in: snapshot)
                if currentParentId == toFolderId {
                    skippedCount += 1
                    continue
                }

                // Remove from current location
                if let removed = findAndRemoveEntry(id: entryId, in: &snapshot) {
                    movedEntries.append(removed)
                }
            }
        }

        guard !movedEntries.isEmpty else {
            Log.debug("No valid items to move (folders were ignored)")
            return false
        }

        let insertIndex = toFolderId == nil ? snapshot.count : 0
        if insert(entries: movedEntries, inFolderId: toFolderId, at: insertIndex, into: &snapshot) {
            history = snapshot
            saveHistory()

            let movedCount = movedEntries.count
            if skippedCount > 0 {
                Log.debug("Moved \(movedCount) items (skipped \(skippedCount) already in target)")
            }

            if let undoManager {
                undoManager.registerUndo(withTarget: self) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                undoManager.setActionName(movedCount == 1 ? "Move Item" : "Move Items")
            }
            return true
        }

        return false
    }
  
    func findAndRemoveEntry(id: UUID, in entries: inout [HistoryEntry]) -> HistoryEntry? {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            return entries.remove(at: index)
        }
        for i in entries.indices {
            if case .folder(var folder) = entries[i] {
                if let removed = findAndRemoveEntry(id: id, in: &folder.children) {
                    entries[i] = .folder(folder)
                    return removed
                }
            }
        }
        return nil
    }
  
    func insert(entries toInsert: [HistoryEntry], inFolderId: UUID?, at index: Int, into snapshot: inout [HistoryEntry]) -> Bool {
        if let inFolderId = inFolderId {
            for i in snapshot.indices {
                if case .folder(var folder) = snapshot[i], folder.id == inFolderId {
                    folder.children.insert(contentsOf: toInsert, at: min(index, folder.children.count))
                    snapshot[i] = .folder(folder)
                    return true
                } else if case .folder(var folder) = snapshot[i] {
                    if insert(entries: toInsert, inFolderId: inFolderId, at: index, into: &folder.children) {
                        snapshot[i] = .folder(folder)
                        return true
                    }
                }
            }
            Log.debug("Target folder ID \(inFolderId) not found in snapshot")
            return false
        } else {
            snapshot.insert(contentsOf: toInsert, at: min(index, snapshot.count))
            return true
        }
    }
  
    func move(inFolderId: UUID?, from: IndexSet, to: Int, undoManager: UndoManager?) {
        let oldHistory = history
        var snapshot = history
        var changed = false
        if let inFolderId = inFolderId {
            func moveIn(entries: inout [HistoryEntry]) -> Bool {
                if let folderIndex = entries.firstIndex(where: { $0.id == inFolderId }),
                  case .folder(var folder) = entries[folderIndex] {
                    folder.children.move(fromOffsets: from, toOffset: to)
                    entries[folderIndex] = .folder(folder)
                    return true
                }
                for i in entries.indices {
                    if case .folder(var folder) = entries[i] {
                        if moveIn(entries: &folder.children) {
                            entries[i] = .folder(folder)
                            return true
                        }
                    }
                }
                return false
            }
            changed = moveIn(entries: &snapshot)
        } else {
            snapshot.move(fromOffsets: from, toOffset: to)
            changed = true
        }
        if changed {
            history = snapshot
            saveHistory()
            if let undoManager {
                undoManager.registerUndo(withTarget: self) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                undoManager.setActionName("Move Items")
            }
        }
    }
  
    func moveToTop(entriesWithIds ids: [UUID], inFolderId: UUID?, undoManager: UndoManager?) {
        let oldHistory = history
        var snapshot = history
        var changed = false
        if let inFolderId = inFolderId {
            func moveIn(entries: inout [HistoryEntry]) -> Bool {
                if let folderIndex = entries.firstIndex(where: { $0.id == inFolderId }),
                  case .folder(var folder) = entries[folderIndex] {
                    let selectedEntries = ids.compactMap { id in
                        folder.children.firstIndex(where: { $0.id == id }).map { folder.children.remove(at: $0) }
                    }
                    folder.children.insert(contentsOf: selectedEntries.reversed(), at: 0)
                    entries[folderIndex] = .folder(folder)
                    return true
                }
                for i in entries.indices {
                    if case .folder(var folder) = entries[i] {
                        if moveIn(entries: &folder.children) {
                            entries[i] = .folder(folder)
                            return true
                        }
                    }
                }
                return false
            }
            changed = moveIn(entries: &snapshot)
        } else {
            let selectedEntries = ids.compactMap { id in
                snapshot.firstIndex(where: { $0.id == id }).map { snapshot.remove(at: $0) }
            }
            snapshot.insert(contentsOf: selectedEntries.reversed(), at: 0)
            changed = true
        }
        if changed {
            history = snapshot
            saveHistory()
            if let undoManager {
                undoManager.registerUndo(withTarget: self) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                undoManager.setActionName("Move to Top")
            }
        }
    }
  
    func moveToBottom(entriesWithIds ids: [UUID], inFolderId: UUID?, undoManager: UndoManager?) {
        let oldHistory = history
        var snapshot = history
        var changed = false
        if let inFolderId = inFolderId {
            func moveIn(entries: inout [HistoryEntry]) -> Bool {
                if let folderIndex = entries.firstIndex(where: { $0.id == inFolderId }),
                  case .folder(var folder) = entries[folderIndex] {
                    let selectedEntries = ids.compactMap { id in
                        folder.children.firstIndex(where: { $0.id == id }).map { folder.children.remove(at: $0) }
                    }
                    folder.children.append(contentsOf: selectedEntries)
                    entries[folderIndex] = .folder(folder)
                    return true
                }
                for i in entries.indices {
                    if case .folder(var folder) = entries[i] {
                        if moveIn(entries: &folder.children) {
                            entries[i] = .folder(folder)
                            return true
                        }
                    }
                }
                return false
            }
            changed = moveIn(entries: &snapshot)
        } else {
            let selectedEntries = ids.compactMap { id in
                snapshot.firstIndex(where: { $0.id == id }).map { snapshot.remove(at: $0) }
            }
            snapshot.append(contentsOf: selectedEntries)
            changed = true
        }
        if changed {
            history = snapshot
            saveHistory()
            if let undoManager {
                undoManager.registerUndo(withTarget: self) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                undoManager.setActionName("Move to Bottom")
            }
        }
    }
  
    func loadHistory() {
            guard FileManager.default.fileExists(atPath: historyURL.path) else {
                // Try legacy path fallback
                // `!loaded.entries.isEmpty` is load-bearing, not defensive: HistoryFile.decode
                // is lossy, so a legacy old-format `[HistoryItem]` blob decodes *successfully*
                // with zero entries. Without the clause this branch would write an empty file
                // and then delete the UserDefaults blob it was migrating from. Same guard as
                // migrateAndSaveIfNeeded().
                if let oldData = AppStorageContext.defaults.data(forKey: "history"),
                   let loaded = try? HistoryFile.decode(oldData),
                   !loaded.entries.isEmpty {
                    // Must be set before the save: this branch removes the legacy
                    // UserDefaults key afterwards, so a skipped save would lose the blob.
                    historyIsLoaded = true
                    history = loaded.entries
                    saveHistory() // auto-migrate
                    AppStorageContext.defaults.removeObject(forKey: "history")
                    return
                }
                historyIsLoaded = true  // Nothing on disk to protect — saving is safe.
                history = []
                return
            }

            Task {
                do {
                    let data = try Data(contentsOf: historyURL)
                    let result = try HistoryFile.decode(data)
                    // Nothing survived — treat it as a file-level failure, or the empty
                    // array is assigned and saved over the file. See loadHistoryFromFile().
                    if result.entries.isEmpty && result.droppedRecordCount > 0 {
                        throw HistoryLoadFailure.everyRecordUnreadable(result.droppedRecordCount)
                    }
                    if result.droppedRecordCount > 0 {
                        Log.error("History: skipped \(result.droppedRecordCount) unreadable record(s)")
                    }
                    // Copy first — see loadHistoryFromFile().
                    let backupPath = result.droppedRecordCount > 0
                        ? self.backUpHistoryFileBeforePartialLoad()
                        : nil
                    await MainActor.run {
                        self.historyIsLoaded = true
                        self.history = result.entries
                        if result.droppedRecordCount > 0 {
                            self.appState?.errorItem = self.partialLoadAlert(
                                droppedRecordCount: result.droppedRecordCount,
                                backupPath: backupPath
                            )
                        }
                    }
                } catch {
                    // Deliberately does NOT assign `history = []` — see loadHistoryFromFile().
                    // That assignment trips `didSet { saveHistory() }` and would overwrite
                    // history_v2.json with an empty array.
                    Log.error("Failed to load history from file (file left untouched): \(error)")
                }
            }
        }

    private let saveQueue = DispatchQueue(label: "art.genstation.history-save", qos: .background)

    func saveHistory() {
        // The single choke point: every mutation path funnels through here (directly or via
        // `history`'s didSet), so guarding here — not at call sites — is what makes the
        // protection complete.
        guard historyIsLoaded else {
            Log.debug("Skipping history save — the history file was never successfully loaded")
            return
        }
        let historySnapshot = history
        saveQueue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try HistoryFile.encode(historySnapshot)
                try data.write(to: self.historyURL, options: .atomic)
            } catch {
                Log.debug("Failed to save history: \(error)")
            }
        }
    }

    /// Agent folder mutations commit the complete validated snapshot before UI publication.
    /// Prior queued writes are flushed first; failed persistence leaves memory untouched.
    @MainActor func commitAgentOrganization(_ snapshot: [HistoryEntry], undoManager: UndoManager? = nil) throws {
        guard historyIsLoaded else { throw AgentImageError("History is not ready. No organization changes were made.") }
        guard snapshot != history else { return }
        let previous = history
        try saveQueue.sync { try AgentHistoryFolders.persist(snapshot, to: historyURL) }
        suppressHistorySave = true
        history = snapshot
        suppressHistorySave = false
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated {
                    // Do not replace newly generated/imported History with an old snapshot.
                    guard target.history == snapshot else { return }
                    do { try target.commitAgentOrganization(previous, undoManager: undoManager) }
                    catch { Log.debug("History organization undo could not be persisted: \(error)") }
                }
            }
            undoManager.setActionName("Organize Agent Results")
        }
    }

    /// Durable completion barrier for workflows: flush prior queued snapshots,
    /// then surface any write failure before marking the job completed.
    func saveHistoryNow() throws {
        guard historyIsLoaded else { throw AgentImageError("History is not ready to save. The workflow result remains recoverable.") }
        let snapshot = history
        try saveQueue.sync {
            try HistoryFile.encode(snapshot).write(to: historyURL, options: .atomic)
        }
    }


  
  
    
    
    func addFolder(undoManager: UndoManager?) {
        let oldHistory = history
        let existingNames = history.compactMap { if case .folder(let folder) = $0 { return folder.name } else { return nil } }
        let uniqueName = uniqueFolderName(baseName: "New Folder", existingNames: existingNames)
        history.append(.folder(Folder(name: uniqueName)))
        saveHistory()
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                let historyBeforeUndo = target.history
                target.history = oldHistory
                target.objectWillChange.send()
                target.saveHistory()
                undoManager.registerUndo(withTarget: target) { redoTarget in
                    redoTarget.history = historyBeforeUndo
                    redoTarget.objectWillChange.send()
                    redoTarget.saveHistory()
                }
            }
            undoManager.setActionName("Add Folder")
        }
    }
  
    func delete(at offsets: IndexSet, undoManager: UndoManager?) {
        let oldHistory = history
        history.remove(atOffsets: offsets)
        saveHistory()
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                let historyBeforeUndo = target.history
                target.history = oldHistory
                target.objectWillChange.send()
                target.saveHistory()
                undoManager.registerUndo(withTarget: target) { redoTarget in
                    redoTarget.history = historyBeforeUndo
                    redoTarget.objectWillChange.send()
                    redoTarget.saveHistory()
                }
            }
            undoManager.setActionName("Delete Items")
        }
    }
  
    func clearHistory(undoManager: UndoManager?) {
            // Explicit user intent, and the file is deleted below anyway — but the flag has to
            // be true or the undo-restore's save would be silently skipped.
            historyIsLoaded = true
            let old = history
            history = []
            try? FileManager.default.removeItem(at: historyURL)

            if let undoManager = undoManager {
                undoManager.registerUndo(withTarget: self) { target in
                    target.history = old
                    target.saveHistory()
                }
                undoManager.setActionName("Clear History")
            }
        }
    
    func updateFolderName(with id: UUID, newName: String, undoManager: UndoManager?) {
        let oldHistory = history
        var mutableHistory = history
        
        Log.debug("Attempting rename for id \(id.uuidString) to \(newName)")
        
        func update(in entries: inout [HistoryEntry]) -> Bool {
            Log.debug("Searching in parent with \(entries.count) entries, ids: \(entries.map { $0.id.uuidString }.joined(separator: ", "))")
            
            if let index = entries.firstIndex(where: { $0.id == id }),
               case .folder(var folder) = entries[index] {
                Log.debug("Found at index \(index), old name \(folder.name)")
                
                let siblingsNames = entries.compactMap { entry -> String? in
                    if case .folder(let f) = entry, f.id != id {
                        return f.name
                    }
                    return nil
                }
                let uniqueName = newName.isEmpty ? "New Folder" : uniqueFolderName(baseName: newName, existingNames: siblingsNames)
                folder.name = uniqueName
                entries[index] = .folder(folder)
                return true
            }
            
            for i in entries.indices {
                if case .folder(var folder) = entries[i] {
                    Log.debug("Recursing into folder \(folder.id.uuidString)")
                    if update(in: &folder.children) {
                        entries[i] = .folder(folder)
                        return true
                    }
                }
            }
            return false
        }
        
        if update(in: &mutableHistory) {
            history = mutableHistory
            saveHistory()
            Log.debug("Rename successful")
            if let undoManager {
                undoManager.registerUndo(withTarget: self) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                undoManager.setActionName("Rename Folder")
            }
        } else {
            Log.debug("Rename failed: folder not found")
        }
    }
  
    func findEntries(with ids: Set<UUID>) -> [HistoryEntry] {
        var result: [HistoryEntry] = []
        func collect(from entries: [HistoryEntry]) {
            for entry in entries {
                if ids.contains(entry.id) {
                    result.append(entry)
                }
                if let children = entry.childrenForOutline {
                    collect(from: children)
                }
            }
        }
        collect(from: history)
        return result
    }
  
    private func findAndRemoveEntry(with id: UUID, in entries: inout [HistoryEntry]) -> HistoryEntry? {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            return entries.remove(at: index)
        }
        for i in entries.indices {
            if case .folder(var folder) = entries[i] {
                if let removed = findAndRemoveEntry(with: id, in: &folder.children) {
                    entries[i] = .folder(folder)
                    return removed
                }
            }
        }
        return nil
    }
  
    func addEntry(_ entry: HistoryEntry, toFolderWithId folderId: UUID) {
        var snapshot = history
        func add(to entries: inout [HistoryEntry]) -> Bool {
            for i in entries.indices {
                if case .folder(var folder) = entries[i], folder.id == folderId {
                    folder.children.append(entry)
                    entries[i] = .folder(folder)
                    return true
                } else if case .folder(var folder) = entries[i] {
                    if add(to: &folder.children) {
                        entries[i] = .folder(folder)
                        return true
                    }
                }
            }
            return false
        }
        if add(to: &snapshot) {
            history = snapshot
            saveHistory()
        }
    }
  
    func addEntry(_ entry: HistoryEntry, toFolderWithId folderId: UUID, into snapshot: inout [HistoryEntry]) {
        func add(to entries: inout [HistoryEntry]) -> Bool {
            for i in entries.indices {
                if case .folder(var folder) = entries[i], folder.id == folderId {
                    folder.children.append(entry)
                    entries[i] = .folder(folder)
                    return true
                } else if case .folder(var folder) = entries[i] {
                    if add(to: &folder.children) {
                        entries[i] = .folder(folder)
                        return true
                    }
                }
            }
            return false
        }
        if add(to: &snapshot) {
            history = snapshot
            saveHistory()
        }
    }
  
    func findAndRemoveEntry(matching predicate: (HistoryItem) -> Bool) -> Bool {
        func remove(from entries: inout [HistoryEntry]) -> Bool {
            if let index = entries.firstIndex(where: {
                if case .item(let item) = $0 {
                    return predicate(item)
                }
                return false
            }) {
                entries.remove(at: index)
                return true
            }
            for i in entries.indices {
                if case .folder(var folder) = entries[i] {
                    if remove(from: &folder.children) {
                        entries[i] = .folder(folder)
                        return true
                    }
                }
            }
            return false
        }
        var mutableHistory = history
        if remove(from: &mutableHistory) {
            history = mutableHistory
            saveHistory()
            return true
        }
        return false
    }
  
    func deleteEntries(_ entries: [HistoryEntry], deleteFiles: Bool, undoManager: UndoManager?) {
        let oldHistory = history
        var snapshot = history
  
        if deleteFiles {
            for entry in entries {
                deleteFilesRecursively(entry: entry)
            }
        }
  
        for entry in entries {
            _ = findAndRemoveEntry(id: entry.id, in: &snapshot)
        }
  
        history = snapshot
        saveHistory()
  
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                let historyBeforeUndo = target.history
                target.history = oldHistory
                target.objectWillChange.send()
                target.saveHistory()
                undoManager.registerUndo(withTarget: target) { redoTarget in
                    redoTarget.history = historyBeforeUndo
                    redoTarget.objectWillChange.send()
                    redoTarget.saveHistory()
                }
            }
            undoManager.setActionName("Delete Items")
        }
    }
    
    func allEntryIDs() -> Set<UUID> {
            var ids = Set<UUID>()
            func collect(from entry: HistoryEntry) {
                ids.insert(entry.id)
                if case .folder(let f) = entry {
                    f.children.forEach(collect)
                }
            }
            history.forEach(collect)
            return ids
        }
  
    private func deleteFilesRecursively(entry: HistoryEntry) {
        switch entry {
        case .item(let item):
            guard let path = item.imagePath else { return }
            let fileURL = URL(fileURLWithPath: path)
            let fileManager = FileManager.default
            if let dir = appState?.settings.outputDirectory {
                var coordError: NSError?
                NSFileCoordinator().coordinate(writingItemAt: dir, options: .forDeleting, error: &coordError) { coordinatedURL in
                    if coordinatedURL.startAccessingSecurityScopedResource() {
                        defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                        do {
                            try fileManager.removeItem(at: fileURL)
                        } catch {
                            Log.debug("Failed to delete file: \(error)")
                        }
                    }
                }
                if let coordError = coordError {
                    Log.debug("Coordination error during file delete: \(coordError.localizedDescription)")
                }
            } else {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    Log.debug("Failed to delete file: \(error)")
                }
            }
        case .folder(let folder):
            for child in folder.children {
                deleteFilesRecursively(entry: child)
            }
        }
    }
}
class UIState: ObservableObject {
    struct ImageSlot: Identifiable, Equatable {
        let id = UUID()
        var thumbnail: PlatformImage?
        var fullResolutionURL: URL?
        var originalData: Data?
        // Standalone inpainting mask (binary PNG, transparent = edit region) drawn in the markup editor.
        // Only consumed by mask-capable gpt-image models on /v1/images/edits.
        var maskURL: URL?
        var promptNodes: [NodeInfo] = []
        var selectedPromptIndex: Int = 0
        var path: String { fullResolutionURL?.path ?? "" }
        static func == (lhs: ImageSlot, rhs: ImageSlot) -> Bool {
            lhs.id == rhs.id
        }
    }
    // Input images (user drops here)
        @Published var draftSourcePrompt: String?
        @Published var imageSlots: [ImageSlot] = []
        
        // Output previews (small thumbnails only)
        @Published var outputThumbnails: [PlatformImage?] = []
        @Published var outputPaths: [String?] = []
        @Published var outputTexts: [String] = []
        @Published var currentOutputIndex: Int = 0
        
        // Legacy – kept only for old history items. Will be nil after first launch.
        @Published var outputImages: [PlatformImage?] = []

        // Session gallery - tracks history entry IDs generated in current session (clears on app restart)
        @Published var sessionGeneratedIDs: [UUID] = []
        @Published var sessionSpendUSD: Double = 0  // Running USD spent on AIML generations this session

        // Toast notifications for generation events
        @Published var generationToastMessage: String? = nil
        @Published var showGenerationToast: Bool = false

        // Auto-present trigger (set by generation code, observed by ContentView)
        @Published var shouldPresentGeneratedImage: Bool = false

        // Batch mode flag - suppresses auto-present during batch operations
        @Published var isBatchRunning: Bool = false
        @Published var batchCurrentIndex: Int = 0   // 0-based, currently generating
        @Published var batchTotalCount: Int = 0     // total items in this run
        @Published var outputFolderFallbackMessage: String? = nil

        // Jobs panel: terminal-state rows (completed/failed/cancelled/expired) the
        // user dismissed via "Remove" or "Clear Finished". Keyed by history item id
        // (or live job id for rows without a history item). Persisted so cleared
        // rows don't reappear on relaunch; the panel prunes ids that no longer
        // exist in history. The underlying history items are untouched.
        static let dismissedJobsPanelIDsKey = "jobsPanelDismissedJobIDs"
        @Published var dismissedJobsPanelIDs: Set<String> = Set(AppStorageContext.defaults.stringArray(forKey: UIState.dismissedJobsPanelIDsKey) ?? []) {
            didSet { AppStorageContext.defaults.set(Array(dismissedJobsPanelIDs), forKey: UIState.dismissedJobsPanelIDsKey) }
        }

        // Video generation stage text ("Waiting in queue...", "Rendering video...", etc.).
        // Percent-style progress was removed — it was fabricated (pollCount/60);
        // elapsed/typical/status now come from JobQueue's job records.
        @Published var videoGenerationStage: String = ""

        // Selected styles from Style Browser (shared for prompt enhancement)
        @Published var selectedStyles: Set<PromptStyle> = []

        // Custom styles created by user (persisted)
        @Published var customStyles: [PromptStyle] = [] {
            didSet { saveCustomStyles() }
        }

        // Favorite style IDs (persisted) - works for both built-in and custom styles
        @Published var favoriteStyleIDs: Set<String> = [] {
            didSet { saveFavorites() }
        }

        // Request to open Style Browser (observed by ContentView)
        @Published var requestOpenStyleBrowser: Bool = false

        // Request to open Enhance Prompt (observed by PromptSection)
        @Published var requestOpenEnhancePrompt: Bool = false

        // Request to open Video Helper (observed by PromptSection)
        @Published var requestOpenVideoHelper: Bool = false

        // Request to focus the History search field (observed by HistoryView)
        @Published var requestFocusHistorySearch: Bool = false

        // Request to import a history package from a URL (observed by HistoryView)
        @Published var requestImportPackageURL: URL? = nil

        // Prompt mode - single prompt or batch mode
        enum PromptMode: String, CaseIterable {
            case single = "Single"
            case batch = "Batch"
        }
        @Published var promptMode: PromptMode = .single

        // Batch editor visibility (for menu command state)
        @Published var isBatchEditorVisible: Bool = false

        // Batch generator draft (preserved when opening Style Browser)
        struct BatchGeneratorDraft {
            var description: String
            var promptCount: Int
        }
        @Published var batchGeneratorDraft: BatchGeneratorDraft? = nil

        /// When non-nil, the batch editor should open a new untitled buffer with these prompts
        /// instead of loading from the saved bookmark. Cleared after the editor consumes it.
        @Published var batchNewFilePrompts: [String]? = nil

    @Published var lastImageSlots: [ImageSlot] = []
        
        // MARK: - Public API
        func addImage(_ image: PlatformImage, originalData: Data? = nil) {
            let thumbnail = image.downscaled(toMaxPixels: 512)
            let slot = ImageSlot(thumbnail: thumbnail, originalData: originalData)
            imageSlots.append(slot)
            
            // Save full-res to temp folder immediately → free RAM
            if let url = saveToTempFolder(image: image, prefix: "input_") {
                imageSlots[imageSlots.count - 1].fullResolutionURL = url
            }
        }
        
        func clearAll() {
            imageSlots.removeAll()
            outputThumbnails = []
            outputPaths = []
            outputTexts = []
            outputImages = []
            currentOutputIndex = 0
            lastImageSlots = []
        }
        
        // Called from ContentView+Generation.swift after saving
        func generationDidFinish(paths: [String?], thumbnails: [PlatformImage?]) {
            DispatchQueue.main.async {
                self.outputPaths = paths
                self.outputThumbnails = thumbnails
                self.outputImages = [] // Critical: releases huge bitmaps
            }
        }
        
        // MARK: - Private Helpers
        private func saveToTempFolder(image: PlatformImage, prefix: String) -> URL? {
            let filename = "\(prefix)\(UUID().uuidString).png"
            let url = AppStorageContext.current.temporaryDirectory.appendingPathComponent(filename)
            guard let data = image.pngData() else { return nil }
            try? data.write(to: url)
            return url
        }

        // MARK: - Custom Styles Persistence

        private var customStylesURL: URL {
            AppStorageContext.current.stylesURL
        }

        func loadCustomStyles() {
            // Load custom styles from file
            if FileManager.default.fileExists(atPath: customStylesURL.path),
               let data = try? Data(contentsOf: customStylesURL),
               let styles = try? JSONDecoder().decode([PromptStyle].self, from: data) {
                customStyles = styles
            }

            // Load favorites from UserDefaults
            if let savedFavorites = AppStorageContext.defaults.stringArray(forKey: "favoriteStyleIDs") {
                favoriteStyleIDs = Set(savedFavorites)
            }
        }

        private func saveCustomStyles() {
            Task.detached(priority: .background) {
                do {
                    let data = try JSONEncoder()
                        .withPrettyPrintingAndSortedKeys()
                        .encode(self.customStyles)
                    try data.write(to: self.customStylesURL, options: .atomic)
                } catch {
                    Log.debug("Failed to save custom styles: \(error)")
                }
            }
        }

        private func saveFavorites() {
            AppStorageContext.defaults.set(Array(favoriteStyleIDs), forKey: "favoriteStyleIDs")
        }

        // MARK: - Custom Style Operations

        func addCustomStyle(_ style: PromptStyle) {
            customStyles.append(style)
        }

        func updateCustomStyle(_ style: PromptStyle) {
            if let index = customStyles.firstIndex(where: { $0.id == style.id }) {
                customStyles[index] = style
            }
        }

        func deleteCustomStyle(_ style: PromptStyle) {
            customStyles.removeAll { $0.id == style.id }
            favoriteStyleIDs.remove(style.id) // Also remove from favorites
        }

        func toggleFavorite(_ styleId: String) {
            if favoriteStyleIDs.contains(styleId) {
                favoriteStyleIDs.remove(styleId)
            } else {
                favoriteStyleIDs.insert(styleId)
            }
        }

        func isFavorite(_ styleId: String) -> Bool {
            favoriteStyleIDs.contains(styleId)
        }
    }
    
class AppState: ObservableObject {
    @Published var ui: UIState
    @Published var settings: SettingsState
    @Published var historyState: HistoryState
    /// Queue for remote async generation jobs (AIML video submit + poll).
    /// Configured with its ContentView bridge in performOnAppear.
    let jobQueue = JobQueue()
    let workflowJobs = WorkflowJobStore()
#if os(macOS)
    /// MCP server (WS-7): Unix-socket listener the bundled genstation-mcp helper
    /// proxies agent requests to. Started from performOnAppear when enabled.
    let mcpService = MCPService()
#endif
    @Published var errorItem: AlertError?
    @Published var allAIMLModels: [String] = []
    /// Union of API model `id`s and their `aliases`, used for curated-mode registry matching.
    @Published var aimlModelMatchSet: Set<String> = []
    /// Maps each API model `id` (lowercased) to its API-reported `aliases` (lowercased). Used to
    /// normalize a selected-but-unregistered id to the registry-canonical id it aliases, so its
    /// param view / chip / payload resolve instead of falling back to synthesis. Persisted alongside
    /// the flat model/match caches.
    @Published var aimlModelAliases: [String: [String]] = [:]
    @Published var configurationAvailableModels: [String] = [] // Shared model list from ConfigurationSection
    /// The per-model metadata `/models` publishes and the app used to throw away at decode
    /// (design § 4.4). It is what makes the picker's task filter the API's own classification —
    /// the endpoint family it serves the model on — instead of a substring guess about the id, and
    /// it carries the names, developers, release dates and recommended flags the browser renders.
    @Published var aimlServedModels: [ServedModel] = []

    // MARK: - AIMLAPI Model Cache
    private static let aimlModelsCacheKey = "cachedAIMLModels"
    private static let aimlModelsMatchSetCacheKey = "cachedAIMLModelsMatchSet"
    private static let aimlModelsAliasesCacheKey = "cachedAIMLModelsAliases"
    private static let aimlModelsCacheTimestampKey = "cachedAIMLModelsTimestamp"
    private static let aimlServedModelsCacheKey = "cachedAIMLServedModels"
    private static let cacheExpiryHours: Double = 24

    /// Load cached AIMLAPI models from UserDefaults
    func loadCachedAIMLModels() {
        if let cached = AppStorageContext.defaults.stringArray(forKey: Self.aimlModelsCacheKey) {
            allAIMLModels = cached
            Log.debug("AIMLAPI: Loaded \(cached.count) cached models")
        }
        if let cachedMatch = AppStorageContext.defaults.stringArray(forKey: Self.aimlModelsMatchSetCacheKey) {
            aimlModelMatchSet = Set(cachedMatch)
        }
        if let data = AppStorageContext.defaults.data(forKey: Self.aimlModelsAliasesCacheKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            aimlModelAliases = decoded
        }
        if let data = AppStorageContext.defaults.data(forKey: Self.aimlServedModelsCacheKey),
           let decoded = try? JSONDecoder().decode([ServedModel].self, from: data) {
            aimlServedModels = decoded
            Log.debug("AIMLAPI: Loaded \(decoded.count) cached served models")
        }
        // Heal any stale persisted selection now that the alias map is loaded (covers the
        // relaunch case before a fresh /models fetch completes).
        healSelectedAIMLModel()
    }

    /// Save AIMLAPI models to UserDefaults cache.
    /// - Parameters:
    ///   - matchSet: id+alias union for curated matching; falls back to `models` if empty.
    ///   - aliases: id→aliases map (lowercased) for selection normalization; preserved if empty.
    func cacheAIMLModels(_ models: [String], matchSet: [String] = [], aliases: [String: [String]] = [:]) {
        allAIMLModels = models
        let resolvedMatch = matchSet.isEmpty ? models : matchSet
        aimlModelMatchSet = Set(resolvedMatch)
        AppStorageContext.defaults.set(models, forKey: Self.aimlModelsCacheKey)
        AppStorageContext.defaults.set(resolvedMatch, forKey: Self.aimlModelsMatchSetCacheKey)
        if !aliases.isEmpty {
            aimlModelAliases = aliases
            if let data = try? JSONEncoder().encode(aliases) {
                AppStorageContext.defaults.set(data, forKey: Self.aimlModelsAliasesCacheKey)
            }
        }
        AppStorageContext.defaults.set(Date().timeIntervalSince1970, forKey: Self.aimlModelsCacheTimestampKey)
        Log.debug("AIMLAPI: Cached \(models.count) models (\(resolvedMatch.count) match entries, \(aimlModelAliases.count) alias entries)")
        // Fresh alias data may let us resolve a previously-stale selection.
        healSelectedAIMLModel()
    }

    /// Persists the per-model metadata alongside the flat id list. Separate from
    /// `cacheAIMLModels(_:matchSet:aliases:)` on purpose: that method's tail calls the healer, and
    /// it is owned by the healer consolidation.
    func cacheAIMLServedModels(_ served: [ServedModel]) {
        aimlServedModels = served
        if let data = try? JSONEncoder().encode(served) {
            AppStorageContext.defaults.set(data, forKey: Self.aimlServedModelsCacheKey)
        }
        Log.debug("AIMLAPI: Cached \(served.count) served generation models")
    }

    /// The one AI/ML healing entry point. Called from `loadCachedAIMLModels()` (launch) and from
    /// `cacheAIMLModels(_:matchSet:aliases:)` (after every successful /models fetch).
    ///
    /// At launch `configurationAvailableModels` is still empty, because `ConfigurationSection` has
    /// not run yet. That is safe by construction: with nothing offered, `SelectionHealer.heal` can
    /// only canonicalize an alias or return nil — it can never reassign.
    func healSelectedAIMLModel() {
        guard let healed = SelectionHealer.heal(
            selected: settings.selectedAIMLModel,
            offered: configurationAvailableModels,
            hasCustomPayload: settings.customAIMLPayload != nil
        ) else { return }
        Log.debug("AIMLAPI: Healed selection \(settings.selectedAIMLModel) -> \(healed)")
        settings.selectedAIMLModel = healed
    }

    /// Check if the AIMLAPI model cache is stale (older than 24 hours), **or predates Stage 3**.
    ///
    /// A cache written before this release holds model ids and nothing else. The picker classifies,
    /// names and orders from the per-model metadata, so an id-only cache would produce an empty
    /// picker on the first launch after updating. Reporting it stale routes it through the refresh
    /// path that already exists (`ConfigurationSection.fetchAvailableModels`), so the upgrade costs
    /// one `/models` call and no user action.
    ///
    /// The decision itself is `AIMLModelCacheStaleness.isStale` (`GenStationCore`) — this is only a
    /// thin call reading `UserDefaults`/`Date()` and passing them in. Moved out because this target
    /// has no test harness, so the decision could never be verified while it lived here.
    var isAIMLModelCacheStale: Bool {
        let timestamp = AppStorageContext.defaults.object(forKey: Self.aimlModelsCacheTimestampKey) as? Double
        return AIMLModelCacheStaleness.isStale(
            servedModelsEmpty: aimlServedModels.isEmpty,
            idsEmpty: allAIMLModels.isEmpty,
            cachedAt: timestamp.map { Date(timeIntervalSince1970: $0) },
            now: Date(),
            expiryHours: Self.cacheExpiryHours)
    }

    /// Clear the AIMLAPI model cache (for manual refresh)
    func clearAIMLModelCache() {
        allAIMLModels = []
        AppStorageContext.defaults.removeObject(forKey: Self.aimlModelsCacheKey)
        AppStorageContext.defaults.removeObject(forKey: Self.aimlModelsCacheTimestampKey)
        // Keep the alias map: it survives a refresh and stays valid across relaunches; a fresh
        // fetch will overwrite it via cacheAIMLModels(aliases:).
        Log.debug("AIMLAPI: Cache cleared")
    }
    @Published var prompt: String = "" // Added to support prompt access
    @Published var generation: GenerationState // Added to support generation properties
    @Published var batchFileSecurityScopedURL: URL? = nil
    @Published var batchFilePath: String = ""  // ← NEW: Shared path for display & updates
    @Published var batchFileURL: URL? = nil
    @Published var batchPrompts: [String] = []
    
    @Published var batchFileVersion: Int = 0
    
    var canAddImages: Bool {
        switch settings.provider {
        case .gemini:
            return true
        case .aimlapi:
            return currentAIMLModel.isI2I
        case .comfyUI:
            return true
        case .grok:
            return settings.isVideoMode || GrokClient.supportsEditing(model: settings.selectedGrokModel)
        }
    }
    var maxImageSlots: Int {
        switch settings.provider {
        case .gemini:
            return 4
        case .aimlapi:
            return currentAIMLModel.maxInputImages
        case .comfyUI:
            return generation.selectedImageNodeIDs.count
        case .grok:
            return settings.isVideoMode || GrokClient.supportsEditing(model: settings.selectedGrokModel) ? 1 : 0
        }
    }
    var preferImgBBForImages: Bool {
        !settings.imgbbApiKey.isEmpty && currentAIMLModel.acceptsPublicURL
    }
    /// Never nil. `resolve` is the deliberate choice: a selection the catalog does not know still
    /// has to drive image slots, submission method and the payload editor, exactly as the registry's
    /// unconditional synthesis did. For the launch default (`selectedAIMLModel == ""`) the
    /// synthesized row reports 0 input images, no required image, `acceptsPublicURL == true`,
    /// `acceptsBase64 == true` and `supportsMask == false` — which is what each of this property's
    /// callers used as its `??` fallback.
    var currentAIMLModel: CatalogModel {
        // `resolve` already goes through the alias index, so the extra normalization step the
        // registry needed is now a no-op wrapper around it.
        Catalog.resolve(settings.selectedAIMLModel)
    }

    
    @Published var presentedModal: PresentedModal? = nil  
    
    private var cancellables = Set<AnyCancellable>()
    @objc func setPrompt(_ newPrompt: String) {
        self.prompt = newPrompt
    }
    init() {
        // Before SettingsState, because @AppStorage("showAllAIMLModels", store: AppStorageContext.defaults) is read from it. The old
        // key meant the opposite of its own label -- `true` was advanced mode -- so renaming it
        // without carrying the value over would silently return every existing user to curated
        // mode. Idempotent, and a no-op on a fresh install.
        SettingsMigration.migrateShowAllAIMLModels(in: AppStorageContext.defaults)
        self.ui = UIState()
        self.settings = SettingsState()
        self.historyState = HistoryState()
        self.generation = GenerationState()
        settings.attach(to: self)
        historyState.appState = self
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }.store(in: &cancellables)
        generation.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }.store(in: &cancellables)
        historyState.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }.store(in: &cancellables)
        ui.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }.store(in: &cancellables)

        // Load cached AIMLAPI models on startup
        loadCachedAIMLModels()
    }

    // GenStationApp.swift – Full loadBatchPrompts function in AppState
    func loadBatchPrompts() {
        guard let bookmarkData = AppStorageContext.defaults.data(forKey: "batchFileBookmark") else {
            Log.debug("LOAD: No bookmark – clearing batch state")
            self.batchPrompts = []
            self.batchFilePath = ""
            self.batchFileURL = nil
            self.batchFileVersion += 1
            return
        }
        
        Log.debug("LOAD: Bookmark data found (length: \(bookmarkData.count) bytes)")
        
        var resolvedURL: URL?
        var isStale = false
        
        // Try security-scoped first on macOS
        #if os(macOS)
        do {
            resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
            Log.debug("LOAD: Security-scoped resolution succeeded")
        } catch {
            Log.debug("LOAD: Security-scoped resolution failed: \(error.localizedDescription)")
        }
        #endif
        
        // Fallback to no options
        if resolvedURL == nil {
            do {
                resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: [], bookmarkDataIsStale: &isStale)
                Log.debug("LOAD: Fallback resolution succeeded")
            } catch {
                Log.debug("LOAD: Fallback resolution failed: \(error.localizedDescription)")
                clearBatchBookmarkAndState()
                return
            }
        }
        
        guard let url = resolvedURL else {
            clearBatchBookmarkAndState()
            return
        }
        
        Log.debug("LOAD: Resolved URL: \(url.path)")
        
        // Refresh stale
        if isStale {
            Log.debug("LOAD: Bookmark stale – refreshing")
            
            #if os(macOS)
            var refreshOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
            #else
            var refreshOptions: URL.BookmarkCreationOptions = .minimalBookmark
            #endif
            
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            
            if let fresh = try? url.bookmarkData(options: refreshOptions) {
                AppStorageContext.defaults.set(fresh, forKey: "batchFileBookmark")
                Log.debug("LOAD: Stale bookmark refreshed (length: \(fresh.count) bytes)")
            } else {
                #if os(macOS)
                // Fallback to minimal if scoped fails (only on macOS)
                refreshOptions = .minimalBookmark
                if let minimalFresh = try? url.bookmarkData(options: refreshOptions) {
                    AppStorageContext.defaults.set(minimalFresh, forKey: "batchFileBookmark")
                    Log.debug("LOAD: Stale bookmark refreshed with minimal (no scope) as fallback")
                } else {
                    Log.debug("LOAD: Failed to refresh stale bookmark")
                }
                #else
                Log.debug("LOAD: Failed to refresh stale bookmark on iOS")
                #endif
            }
        }
        
        // Start security-scoped access before reading (required for sandboxed apps)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        if accessing {
            Log.debug("LOAD: Started security-scoped access")
        } else {
            Log.debug("LOAD: Security-scoped access not needed or failed to start")
        }

        // Load content
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            Log.debug("LOAD: Success (content length: \(content.count) chars)")
            self.batchPrompts = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.batchFileURL = url
            self.batchFilePath = url.path
            self.batchFileVersion += 1
            return
        } catch {
            let nsError = error as NSError
            Log.debug("LOAD: Read failed (code: \(nsError.code)): \(error.localizedDescription)")
        }

        // Final failure – clear
        Log.debug("LOAD: All attempts failed – clearing bookmark")
        clearBatchBookmarkAndState()
    }

    private func clearBatchBookmarkAndState() {
        AppStorageContext.defaults.removeObject(forKey: "batchFileBookmark")
        self.batchPrompts = []
        self.batchFilePath = ""
        self.batchFileURL = nil
        self.batchFileVersion += 1
    }

    
}

@main
@MainActor
enum GenStationEntry {
    static func main() {
        #if os(macOS)
        if CommandLine.arguments.contains("--genstation-mcp") {
            // Branch before constructing SwiftUI, AppState, Keychain or library stores.
            runMCPStdioServer()
            return
        }
        #endif
        GenStationApp.main()
    }
}

struct GenStationApp: App {
    init() {
// DEBUG: RESET FIRST-LAUNCH FLAGS — Uncomment to re-trigger onboarding, legal, and privacy sheets
//       AppStorageContext.defaults.removeObject(forKey: "hasCompletedMandatoryOnboarding")  // Terms of use
//       AppStorageContext.defaults.removeObject(forKey: "hasSeenAPIKeySetup")               // API key wizard
//       AppStorageContext.defaults.removeObject(forKey: "hasSeenPrettyOnboarding")          // Feature onboarding
//       AppStorageContext.defaults.removeObject(forKey: "comfyUIWarningAccepted")           // ComfyUI warning
//       AppStorageContext.defaults.removeObject(forKey: "hasSeenOutputFolderSetup")         // Output folder setup
//       AppStorageContext.defaults.removeObject(forKey: "dontShowGeminiPrivacy")            // Gemini privacy notice
//       AppStorageContext.defaults.removeObject(forKey: "dontShowGrokPrivacy")              // Grok privacy notice
//       AppStorageContext.defaults.removeObject(forKey: "dontShowAIMLAPIPrivacy")           // AI/ML API privacy notice
//       AppStorageContext.defaults.removeObject(forKey: "dontShowImgBBPrivacy")             // ImgBB privacy notice

        #if os(iOS)
        // Configure audio session for video playback through the speaker.
        // Default .soloAmbient category doesn't reliably route to the speaker.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
        }
    
    @StateObject private var appState = AppState()
    @State private var showSplash = true
    @State private var batchFilePath: String = ""
#if os(macOS)
    @State private var showClearHistoryConfirmation = false
    @State private var isGenerating = false
#endif
    
#if os(macOS)
@NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
#endif

    var body: some Scene {
        
        
#if os(macOS)
        WindowGroup(AppStorageContext.current.isDemo ? "GenStation Demo" : "GenStation") {
            ContentView()
                .accessibilityIdentifier("genstation.workspace")
                .environmentObject(appState)
                .frame(
                    minWidth: 825,
                    idealWidth: max(825, (NSScreen.main?.frame.width ?? 1920) / 3),
                    maxWidth: .infinity,
                    minHeight: 750,
                    idealHeight: 850,
                    maxHeight: .infinity
                )
                .alert("Clear History", isPresented: $showClearHistoryConfirmation) {
                    Button("Clear", role: .destructive) {
                        appState.historyState.clearHistory(undoManager: NSApp.keyWindow?.undoManager)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove all history entries but keep your files intact. Are you sure?")
                }
                .onAppear {
                    appDelegate.appState = appState  // ← CRITICAL: Set the reference here
                    // Disable toolbar customization context menu (Icon/Icon+Text options don't work)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.windows.forEach { window in
                            window.toolbar?.allowsUserCustomization = false
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GenerationStateChanged"))) { notification in
                    if let newState = notification.object as? Bool {
                        isGenerating = newState
                    }
                }
                .tint(appState.settings.provider.liquidAccent)
        }
        .commands {
            GenStationMenuCommands(
                appState: appState,
                showClearHistoryConfirmation: $showClearHistoryConfirmation,
                isGenerating: $isGenerating
            )
        }

        WindowGroup(id: "help-window", for: Provider.self) { $mode in  // ← Use $mode for Binding<Provider?>
            if let unwrappedMode = $mode.wrappedValue {  // ← Unwrap the optional value from the binding
                HelpView(mode: unwrappedMode)
                    .environmentObject(appState)
            } else {
                // Fallback (rare, but prevents crash if nil)
                Text("No mode provided")
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .defaultSize(width: 1000, height: 800)
        
        WindowGroup(for: UUID.self) { $slotId in
            if let slotId {
                MarkupWindowView(slotId: slotId)
                    .environmentObject(appState)
            }
        }
        
        WindowGroup(id: "history-viewer", for: UUID.self) { $historyId in
            if let historyId {
                FullHistoryItemView(initialId: historyId)
                    .environmentObject(appState)
                    .onAppear {
                        NSApplication.shared.windows.last?.title = "GenStation — History Viewer"
                    }
            }
        }
        .defaultSize(width: 1200, height: 800)
        
        WindowGroup(id: "response-window") {
            PopOutView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.automatic)

        WindowGroup(id: "history-panel-window") {
            HistoryPanelWindow()
                .environmentObject(appState)
        }
        .defaultSize(width: 450, height: 700)
        .windowStyle(.automatic)

#else
        WindowGroup {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeOut(duration: 0.5)) {
                                showSplash = false
                            }
                        }
                    }
            } else {
                ContentView()
                    .environmentObject(appState)
                // No more sheets here — everything is now handled inside ContentView.swift
            }
            
        }
#endif
        
        
    }
    
}

struct MarkupWindowView: View {
    let slotId: UUID
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if let index = appState.ui.imageSlots.firstIndex(where: { $0.id == slotId }) {
            let slot = appState.ui.imageSlots[index]
            
            // Load full-resolution image from disk (only when needed)
            if let fullURL = slot.fullResolutionURL,
               let fullImage = PlatformImage(contentsOfFile: fullURL.path) {
                
                let fileURL = URL(fileURLWithPath: slot.path)
                let lastComponent = fileURL.lastPathComponent
                let components = lastComponent.components(separatedBy: ".")
                let baseFileName = components.count > 1 ? components.dropLast().joined(separator: ".") : (lastComponent.isEmpty ? "image" : lastComponent)
                let fileExtension = components.count > 1 ? (components.last ?? "png") : "png"

                // Mask inpainting is macOS-only and limited to mask-capable gpt-image models.
                #if os(macOS)
                let maskSupported = appState.settings.provider == .aimlapi && appState.currentAIMLModel.supportsMask
                #else
                let maskSupported = false
                #endif

                MarkupView(
                    image: fullImage,
                    baseFileName: baseFileName,
                    fileExtension: fileExtension,
                    onSave: { updatedImage in
                        // Save updated image back to the same temp location
                        if let data = updatedImage.pngData(),
                           let url = slot.fullResolutionURL {
                            do {
                                try data.write(to: url)
                                // Update thumbnail too for instant preview
                                let newThumb = updatedImage.downscaled(toMaxPixels: 512)
                                appState.ui.imageSlots[index].thumbnail = newThumb
                            } catch {
                                Log.debug("Failed to save annotated image: \(error)")
                            }
                        } else {
                            Log.debug("Failed to generate PNG data for annotated image")
                        }
                    },
                    maskSupported: maskSupported,
                    onSaveMask: { maskImage in
                        guard let url = slot.fullResolutionURL else { return }
                        // Parallel mask file alongside the source image (e.g. image.mask.png).
                        let maskURL = url.deletingPathExtension().appendingPathExtension("mask.png")
                        if let maskImage, let data = maskImage.pngData() {
                            do {
                                try data.write(to: maskURL)
                                appState.ui.imageSlots[index].maskURL = maskURL
                                Log.debug("Saved inpainting mask to \(maskURL.lastPathComponent)")
                            } catch {
                                Log.debug("Failed to save inpainting mask: \(error)")
                            }
                        } else {
                            // Cleared mask: remove the file and detach it from the slot.
                            try? FileManager.default.removeItem(at: maskURL)
                            appState.ui.imageSlots[index].maskURL = nil
                        }
                    }
                )
                .navigationTitle("Annotate Image")
            } else {
                Text("Image not available")
                    .foregroundColor(.secondary)
            }
        } else {
            Text("Slot not found")
                .foregroundColor(.secondary)
        }
    }
}

private extension JSONEncoder {
    func withPrettyPrintingAndSortedKeys() -> JSONEncoder {
        self.outputFormatting = [.prettyPrinted, .sortedKeys]
        return self
    }
}

#if os(macOS)
class MacAppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?  // ← Will be set from main window .onAppear
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState = appState else {
            Log.debug("Quit: appState nil – allowing termination without prompt")
            return .terminateNow
        }
        
        let hasUnsaved = hasUnsavedBatchChanges(appState: appState)
        guard hasUnsaved else { return .terminateNow }
        
        let alert = NSAlert()
        alert.messageText = appState.batchFileURL != nil
            ? "Save changes to batch file before quitting?"
            : "Save batch prompts before quitting?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Save…")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        switch response {
        case .alertThirdButtonReturn: // Save
            let textToSave = appState.batchPrompts.joined(separator: "\n")
            if let url = appState.batchFileURL {
                return synchronousSave(to: url, text: textToSave, replacing: true, appState: appState) ? .terminateNow : .terminateCancel
            } else {
                let panel = NSSavePanel()
                panel.title = "Save Batch File"
                panel.nameFieldStringValue = "batch.txt"
                panel.allowedContentTypes = [.plainText]
                panel.canCreateDirectories = true
                
                guard panel.runModal() == .OK, let url = panel.url else {
                    return .terminateCancel
                }
                return synchronousSave(to: url, text: textToSave, replacing: false, appState: appState) ? .terminateNow : .terminateCancel
            }
        case .alertFirstButtonReturn: // Don’t Save
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
    
    // MARK: - Unchanged helper methods (copy from previous version)
    private func hasUnsavedBatchChanges(appState: AppState) -> Bool {
        if appState.batchFileURL == nil {
            return !appState.batchPrompts.isEmpty
        }
        
        guard let url = appState.batchFileURL else { return false }
        
        var savedPrompts: [String] = []
        var coordError: NSError?
        var readError: Error?
        
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            let accessing = coordinatedURL.startAccessingSecurityScopedResource()
            defer { if accessing { coordinatedURL.stopAccessingSecurityScopedResource() } }
            
            do {
                let content = try String(contentsOf: coordinatedURL, encoding: .utf8)
                savedPrompts = content.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } catch {
                readError = error
            }
        }
        
        if let readError = readError {
            Log.debug("Quit-time read failed: \(readError.localizedDescription)")
            return true  // Conservative: assume unsaved
        }
        
        return savedPrompts != appState.batchPrompts
    }
    
    private func synchronousSave(to url: URL, text: String, replacing: Bool, appState: AppState) -> Bool {
        var success = false
        var coordError: NSError?
        
        let options: NSFileCoordinator.WritingOptions = replacing ? .forReplacing : []
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordError) { coordinatedURL in
            let accessing = coordinatedURL.startAccessingSecurityScopedResource()
            defer { if accessing { coordinatedURL.stopAccessingSecurityScopedResource() } }
            
            do {
                try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                success = true
                
                // Refresh bookmark
                if let bookmark = try? coordinatedURL.bookmarkData(options: [.withSecurityScope]) {
                    AppStorageContext.defaults.set(bookmark, forKey: "batchFileBookmark")
                }
                
                DispatchQueue.main.async {
                    appState.batchFileURL = coordinatedURL
                    appState.batchFilePath = coordinatedURL.path
                    appState.batchFileVersion += 1
                }
            } catch {
                Log.debug("Quit-time save failed: \(error)")
            }
        }
        return success
    }
}
#endif
extension Provider {
    var liquidAccent: Color {
        switch self {
        case .gemini:   return Color(red: 0.2, green: 0.5, blue: 1.0)   // vibrant Gemini blue
        case .grok:     return Color(red: 0.6, green: 0.3, blue: 0.9)   // rich Grok purple
        case .comfyUI:  return Color(red: 0.1, green: 0.8, blue: 0.4)   // bright ComfyUI green
        case .aimlapi:  return Color(red: 1.0, green: 0.5, blue: 0.2)   // warm AIMLAPI orange
        }
    }
    
    var liquidTintOpacity: Double { 0.08 }        // subtle wash
    var liquidOverlayOpacity: Double { 0.12 }     // for cards
}
