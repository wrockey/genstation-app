//ConfigurationSection.swift
import SwiftUI
 
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import GenStationCore
 
struct ConfigurationSection: View {
    @Binding var showApiKey: Bool
    @Binding var isTestingApi: Bool
    @Binding var params: ModelParameters
    @Binding var errorItem: AlertError?
    @Binding var aimlBalance: Double?
    @Binding var balanceFetchTask: Task<Void, Never>?
    let onComfyJSONSelected: (Result<[URL], Error>) -> Void
 
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass
 
    @State private var showSuccessAlert: Bool = false
    @State private var hasInitializedLaunchParams: Bool = false
    @State private var successMessage: String = ""
    @State private var showCopiedMessage: Bool = false
    @State private var showServerSuccessAlert: Bool = false
    @State private var showServerErrorAlert: Bool = false
    @State private var serverErrorMessage: String = ""
    @State private var isTestingServer: Bool = false
    @State private var showGrokApiKey: Bool = false
    @State private var showAIMLApiKey: Bool = false
    @State private var showImgBBApiKey: Bool = false
    @State private var availableModels: [String] = []
    @State private var isFetchingModels: Bool = false
    @State private var showModelPicker: Bool = false
    @State private var showHelp: Bool = false
    @State private var detailedError: DetailedError? = nil
    @State private var showGeneralOptions: Bool = false
    @State private var showSaveWorkflowDialog: Bool = false
    @State private var saveWorkflowName: String = ""
    @State private var workflowToRename: SavedWorkflow? = nil
    @State private var workflowToMap: SavedWorkflow? = nil
    @State private var proposedWorkflowName: String = ""
    @StateObject private var workflowLibrary = WorkflowLibrary.shared
 
    private var isCompact: Bool {
        sizeClass == .compact
    }
 
    private var labelFont: Font {
        .system(.subheadline, design: .default, weight: .medium)
    }
 
    private var textFont: Font {
        .system(size: isCompact ? 13 : 15, weight: .medium, design: .monospaced)
    }
 
    private var pickerFont: Font {
        .system(size: isCompact ? 12 : 14)
    }
 
    private var labelWidth: CGFloat {
        isCompact ? 110 : 140
    }
 
    init(
        showApiKey: Binding<Bool>,
        isTestingApi: Binding<Bool>,
        params: Binding<ModelParameters>,
        errorItem: Binding<AlertError?>,
        aimlBalance: Binding<Double?>,
        balanceFetchTask: Binding<Task<Void, Never>?>,
        onComfyJSONSelected: @escaping (Result<[URL], Error>) -> Void
    ) {
        _showApiKey = showApiKey
        _isTestingApi = isTestingApi
        _params = params
        _errorItem = errorItem
        _aimlBalance = aimlBalance
        _balanceFetchTask = balanceFetchTask
        self.onComfyJSONSelected = onComfyJSONSelected
    }
 
    private var mainContent: some View {
        VStack(spacing: isCompact ? 8 : 12) {
            switch appState.settings.provider {
            case .gemini:
                geminiConfiguration
            case .comfyUI:
                comfyUIConfiguration
            case .grok:
                grokConfiguration
            case .aimlapi:
                aimlConfiguration
            }
        }
    }

    /// Grouped inset card wrapper for configuration rows
    private func configCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.vertical, isCompact ? 10 : 12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Thin divider for separating rows inside a card
    private var cardDivider: some View {
        Divider()
            .padding(.vertical, isCompact ? 6 : 8)
    }

    private var configuredView: some View {
        mainContent
        .onChange(of: appState.settings.provider) { newMode in
            handleModeChange(newMode)
        }
        .onChange(of: appState.settings.selectedAIMLModel) { _ in
            handleSelectedModelChange()
        }
        .onChange(of: appState.settings.task) { _ in
            Task { filterModelsLocally() }
        }
        .onChange(of: appState.settings.showAllAIMLModels) { _ in
            Task { filterModelsLocally() }
        }
        .onChange(of: appState.generation.imageNodes) { _ in
            handleImageNodesChange()
        }
        .onChange(of: appState.generation.selectedImageNodeIDs) { _ in
            handleSelectedImageNodeIDsChange()
        }
    }
    
    private func handleModeChange(_ newMode: Provider) {
        Task {
            await Task.yield()
            if newMode == .gemini &&
                       !appState.settings.apiKey.isEmpty &&
                       appState.settings.availableGeminiModels.isEmpty &&
                       !appState.settings.isFetchingGeminiModels {
                        await appState.settings.fetchAvailableGeminiModels()
                    }
            
            if newMode == .aimlapi && !appState.settings.aimlapiKey.isEmpty {
                fetchAvailableModels()
                balanceFetchTask?.cancel()
                balanceFetchTask = Task {
                    do {
                        let balanceData = try await fetchBalance(apiKey: appState.settings.aimlapiKey)
                        if let balanceNum = balanceData["balance"] as? Double {
                            await MainActor.run { aimlBalance = balanceNum }
                        }
                    } catch {
                        Log.debug("Error fetching balance: \(error.localizedDescription)")
                        await MainActor.run {
                            aimlBalance = nil
//                            errorItem = AlertError(message: "Failed to fetch balance: \(error.localizedDescription)", fullMessage: nil)
                        }
                    }
                }
            } else {
                aimlBalance = nil
            }
            
            handleImageSlotPersistence()
            appState.settings.aimlAdvancedParams = ModelParameters()
            
            if newMode == .comfyUI {
                let accepted = AppStorageContext.defaults.bool(forKey: "comfyUIWarningAccepted")

                if !accepted {
                    // Dismiss any current sheet, then show warning
                    appState.presentedModal = nil
                    DispatchQueue.main.async {
                        appState.presentedModal = .comfyUIWarning
                    }
                }

            }
        }
    }

    private func handleSelectedModelChange() {
        Task {
            await Task.yield()
            handleImageSlotPersistence()

            appState.settings.aimlAdvancedParams = ModelParameters(aspectRatio: appState.settings.aimlAdvancedParams.aspectRatio)

            // Initialize default parameters for the selected model. An unregistered id has no
            // descriptor table, and merging an all-nil defaults set copies nothing — which is
            // exactly what the registry's early return did.
            if let model = Catalog.model(for: appState.settings.selectedAIMLModel) {
                if model.task == .video {
                    appState.settings.aimlAdvancedParams = ParamDecoder.defaults(ParamCatalog.descriptors(for: model))
                } else {
                ParamDefaults.merge(
                    ParamDecoder.defaults(ParamCatalog.descriptors(for: model)),
                    into: &appState.settings.aimlAdvancedParams
                )
                }
            }

            let model = appState.currentAIMLModel
            let currentMethod = appState.settings.imageSubmissionMethod
            if (currentMethod == .base64 && !model.acceptsBase64) ||
               (currentMethod == .imgBB && !model.acceptsPublicURL) ||
               (currentMethod == .binary && !model.acceptsBinary) {
                if model.acceptsBase64 {
                    appState.settings.imageSubmissionMethod = .base64
                } else if model.acceptsPublicURL && !appState.settings.imgbbApiKey.isEmpty {
                    appState.settings.imageSubmissionMethod = .imgBB
                } else if model.acceptsBinary {
                    appState.settings.imageSubmissionMethod = .binary
                } else {
                    appState.settings.imageSubmissionMethod = .base64
                }
                Log.debug("Auto-switched image submission to \(appState.settings.imageSubmissionMethod) for model \(appState.settings.selectedAIMLModel)")
            }
        }
    }

    private func handleImageNodesChange() {
        Task {
            await Task.yield()
            if appState.settings.provider == .comfyUI {
                handleImageSlotPersistence()
            }
        }
    }

    private func handleSelectedImageNodeIDsChange() {
        Task {
            await Task.yield()
            if appState.settings.provider == .comfyUI {
                handleImageSlotPersistence()

                // Persist selected image node IDs to AppStorage
                let idsArray = Array(appState.generation.selectedImageNodeIDs)
                if let data = try? JSONEncoder().encode(idsArray),
                   let jsonString = String(data: data, encoding: .utf8) {
                    appState.settings.comfySelectedImageNodeIDsJSON = jsonString
                }
            }
        }
    }
 
    var body: some View {
        configuredView
        .onAppear {
            // aimlAdvancedParams is not persisted, so a launch-restored model
            // selection starts with generic values its builder may not accept.
            // Apply the restored model's own defaults once so the params chip
            // and the first submission are valid without opening Model Options.
            let modelId = appState.settings.selectedAIMLModel
            if !hasInitializedLaunchParams && !modelId.isEmpty {
                hasInitializedLaunchParams = true
                if let model = Catalog.model(for: modelId) {
                    ParamDefaults.merge(
                        ParamDecoder.defaults(ParamCatalog.descriptors(for: model)),
                        into: &appState.settings.aimlAdvancedParams
                    )
                }
            }

            // Same root cause as the params above, one level out: every path that fills the
            // model picker hangs off an `onChange` — provider changed, key changed, task
            // changed, or the Fetch button. Since Stage 1 persists the selection, a launch
            // that reopens on AI/ML *restores* the provider rather than changing it, so none
            // of them fire and the picker reads "no models" even though `loadCachedAIMLModels()`
            // has already put 900+ ids in `allAIMLModels`. Populate it once here.
            // `fetchAvailableModels()` is cheap on a warm cache — it just runs the local filter.
            if appState.settings.provider == .aimlapi && !appState.settings.aimlapiKey.isEmpty {
                fetchAvailableModels()
            }
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK") {}
        } message: {
            Text(successMessage)
        }
        .alert("Server Available", isPresented: $showServerSuccessAlert) {
            Button("OK") {}
        } message: {
            Text("The ComfyUI server is reachable and responding.")
        }
        .alert("Server Error", isPresented: $showServerErrorAlert) {
            Button("OK") {}
        } message: {
            Text(serverErrorMessage)
        }
        .errorAlert(errorItem: $errorItem, detailedError: $detailedError)
        .sheet(item: $detailedError) { detail in
            DetailedErrorView(message: detail.message) {
                detailedError = nil
            }
        }
        .sheet(isPresented: $showHelp) {
            HelpView(mode: appState.settings.provider)
        }
    }
 
    @ViewBuilder
    private var geminiConfiguration: some View {
        configCard {
            // Model row: Label + Refresh + Picker
            HStack(spacing: isCompact ? 8 : 10) {
                Text("Model:")
                    .font(labelFont)
                    .foregroundColor(.secondary)
                    .help("Select Gemini image generation model")
                    .fixedSize()

                // Refresh button
                Button {
                    Task { await appState.settings.fetchAvailableGeminiModels(forceRefresh: true) }
                } label: {
                    Image(systemName: appState.settings.isFetchingGeminiModels ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                        .font(.system(size: isCompact ? 13 : 15))
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(appState.settings.isFetchingGeminiModels ? 360 : 0))
                        .animation(appState.settings.isFetchingGeminiModels ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: appState.settings.isFetchingGeminiModels)
                }
                .buttonStyle(.borderless)
                .disabled(appState.settings.apiKey.isEmpty || appState.settings.isFetchingGeminiModels)
                .help("Refresh model list from Google (cached for 24 hours)")
                .accessibilityLabel("Refresh model list")

                // Model picker (takes remaining space)
                if appState.settings.availableGeminiModels.isEmpty {
                    Text(appState.settings.apiKey.isEmpty ? "No API key" : "Loading…")
                        .font(pickerFont)
                        .foregroundColor(.secondary)
                        .italic()
                        .fixedSize()
                } else {
                    Menu {
                        ForEach(appState.settings.availableGeminiModels) { model in
                            Button {
                                appState.settings.selectedGeminiModel = model.shortName
                            } label: {
                                HStack {
                                    // Camera icon for real image models
                                    Image(systemName: "photo")
                                    
                                    // Friendly name — the override table
                                    // (Catalog/Models/PresentationOverrides.swift) absorbed the
                                    // switch that used to be written here and again at the closed
                                    // label below.
                                    Text(Catalog.geminiOverrides[model.shortName]?.displayName
                                         ?? model.displayName)
                                    
                                    Spacer()
                                    
                                    // NEW badge — the override table flags exactly one id `isNew`
                                    if Catalog.geminiOverrides[model.shortName]?.isNew == true {
                                        Text("NEW")
                                            .font(.caption2).bold()
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                    
                                    // Checkmark when selected
                                    if model.shortName == appState.settings.selectedGeminiModel {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .font(pickerFont)
                            }
                        }
                    } label: {
                        HStack {
                            Text(Catalog.geminiOverrides[appState.settings.selectedGeminiModel]?
                                    .displayName
                                 ?? (appState.settings.selectedGeminiModel.isEmpty
                                     ? "Select model" : appState.settings.selectedGeminiModel))
                            .font(pickerFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Currently selected Gemini model")
                }
            }
            .frame(minHeight: isCompact ? 32 : 36)
        }
        .onAppear {
                if appState.settings.availableGeminiModels.isEmpty &&
                   !appState.settings.apiKey.isEmpty &&
                   !appState.settings.isFetchingGeminiModels {
                    Task { await appState.settings.fetchAvailableGeminiModels() }
                }
            }
            .onChange(of: appState.settings.apiKey) { newKey in
                // Trigger auto-fetch when API key becomes valid
                if !newKey.isEmpty &&
                   appState.settings.availableGeminiModels.isEmpty &&
                   appState.settings.provider == .gemini &&
                   !appState.settings.isFetchingGeminiModels {
                    Task { await appState.settings.fetchAvailableGeminiModels() }
                }
            }
    }
 
    @ViewBuilder
    private var grokConfiguration: some View {
        configCard {
            videoModeToggle
            if appState.settings.isVideoMode {
                Text("Grok Imagine Video 1.5").font(.headline)
            } else {
                grokModelRow
            }
        }
    }

    @ViewBuilder
    private var grokModelRow: some View {
        // The catalog is cross-provider, so this MUST filter by provider — `selectable(task:)`
        // also returns the AI/ML rows. Sorting is the catalog's (models sorted by id inside a
        // family group), which is why "Grok Imagine Image" now precedes the Quality row; the
        // hardcoded array listed Quality first.
        let grokModels = Catalog.selectable(task: .image)
            .flatMap(\.models)
            .filter { $0.provider == .grok }
            .sorted { lhs, rhs in
                if lhs.id == "grok-imagine-image-2.0" { return rhs.id != lhs.id }
                if rhs.id == "grok-imagine-image-2.0" { return false }
                return lhs.id < rhs.id
            }
        HStack(spacing: isCompact ? 6 : 10) {
            Text("Model:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Select the Grok model")
                .fixedSize()
            Menu {
                ForEach(grokModels, id: \.id) { model in
                    Button {
                        appState.settings.selectedGrokModel = model.id
                    } label: {
                        Text(model.displayName)
                            .font(pickerFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } label: {
                HStack {
                    // Was the raw id. The catalog's displayName is what the open menu shows, so the
                    // closed control now agrees with it.
                    Text(Catalog.model(for: appState.settings.selectedGrokModel)?.displayName
                         ?? (appState.settings.selectedGrokModel.isEmpty
                             ? "Select model" : appState.settings.selectedGrokModel))
                        .font(pickerFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .help("Choose the Grok model for generation")
            .accessibilityLabel("Grok model selector")
        }
        .frame(minHeight: isCompact ? 32 : 36)
    }
 
    // In ConfigurationSection.swift, update aimlConfiguration
 
    @ViewBuilder
    private var aimlConfiguration: some View {
        configCard {
            aimlModelRow
        }
        .onChange(of: appState.settings.aimlapiKey) { newKey in
            // Auto-fetch models when a valid key is entered/changed
            if !newKey.isEmpty && appState.settings.provider == .aimlapi {
                fetchAvailableModels()  // Uses cache if available, fetches if not
            }
        }
    }
 
    private var fetchModelsButton: some View {
        HStack(spacing: 4) {
            Button(action: {
                self.fetchAvailableModels()
            }) {
                Text(isFetchingModels ? "Fetching..." : "Fetch Models")
                    .font(DS.pickerFont(compact: isCompact))
            }
            .buttonStyle(.bordered)
            .disabled(appState.settings.aimlapiKey.isEmpty || isFetchingModels)
            .help("Fetch available image models from AI/ML API")
            .accessibilityLabel("Fetch models")
            .alignmentGuide(.leading) { d in d[.leading] }
            Spacer()
        }
    }
 
    @ViewBuilder
    private var aimlModelRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Model label, refresh button, and picker (or "No models")
            HStack(spacing: isCompact ? 6 : 10) {
                modelLabel
                refreshButton

                if availableModels.isEmpty {
                    noModelsView
                } else {
                    modelPickerDropdown
                        .id("aimlModelPicker_\(appState.settings.isVideoMode ? "video" : "image")_\(appState.settings.showAllAIMLModels ? "adv" : "safe")_\(availableModels.count)")
                }
            }
            .frame(minHeight: isCompact ? 32 : 36)

            cardDivider

            // Row 2: Video mode toggle
            videoModeToggle
                .frame(minHeight: isCompact ? 32 : 36)

            // Row 3: video params summary — tap opens Model Options (finding #7:
            // duration/resolution/aspect were invisible without the side panel)
            if appState.settings.isVideoMode && !videoParamsSummaryParts.isEmpty {
                cardDivider
                videoParamsChipRow
                    .frame(minHeight: isCompact ? 28 : 32)
            }
        }
    }

    /// "16:9 · 1080p · 10s · audio on" — derived strictly from the selected
    /// model's OWN encoded payload on the current parameters, so the chip
    /// always matches the request payload that will actually be sent (a generic
    /// ModelParameters read showed values the model's table clamps, ignores, or
    /// hardcodes — e.g. "720p · 5s" for ltxv, which only emits 6/8/10s).
    /// Only user-facing keys the model emits are rendered; if it emits none,
    /// the chip is hidden. Model-switch defaults come from the existing
    /// handleSelectedModelChange reset + initializeDefaultParams, which the
    /// encoder then reflects. No cost estimate — the app has no pricing table
    /// (actual cost is captured per response after the fact).
    private var videoParamsSummaryParts: [String] {
        // Honest nil: an id the catalog does not know has no table, so it emitted no user-facing
        // keys and the chip was already hidden. Returning [] here says that outright.
        guard let model = Catalog.model(for: appState.settings.selectedAIMLModel) else { return [] }
        let payload = ParamEncoder.encode(
            ParamCatalog.descriptors(for: model),
            params: appState.settings.aimlAdvancedParams,
            context: ParamCatalog.context(for: model, hasInputImages: !appState.ui.imageSlots.isEmpty)
        )

        func formatted(_ value: Any, suffix: String = "") -> String? {
            if value is Bool { return nil }  // booleans are labeled by the caller
            if let s = value as? String {
                guard !s.isEmpty else { return nil }
                return s.hasSuffix(suffix) ? s : s + suffix
            }
            if let n = value as? NSNumber {
                let d = n.doubleValue
                let text = d == d.rounded() ? String(Int(d)) : String(d)
                return text + suffix
            }
            return nil
        }

        var parts: [String] = []
        if let aspect = payload["aspect_ratio"], let text = formatted(aspect) { parts.append(text) }
        if let resolution = payload["resolution"], let text = formatted(resolution) { parts.append(text) }
        if let duration = payload["duration"], let text = formatted(duration, suffix: "s") { parts.append(text) }
        if let audio = payload["generate_audio"] as? Bool { parts.append(audio ? "audio on" : "audio off") }
        return parts
    }

    private var videoParamsChipRow: some View {
        Button {
            appState.presentedModal = .advancedSettings  // routed to the Model Options panel
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: isCompact ? 10 : 11))
                    .foregroundStyle(.secondary)
                Text(videoParamsSummaryParts.joined(separator: " · "))
                    .font(pickerFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Current video settings — click to open Model Options")
        .accessibilityLabel("Video settings summary")
        .accessibilityHint("Opens the Model Options panel.")
    }

    // Opens a searchable model picker (Favorites / Recent / All) — scales to ~600 models.
    private var modelPickerDropdown: some View {
        Button {
            showModelPicker = true
        } label: {
            HStack {
                if appState.settings.favoriteAIMLModels.contains(appState.settings.selectedAIMLModel) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                }
                Text(selectedModelDisplayText)
                    .font(pickerFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Choose the AI/ML model")
        .accessibilityLabel("AI/ML model selector")
        .sheet(isPresented: $showModelPicker) {
            AIMLModelPickerSheet(appState: appState)
        }
    }


    // Helper for the label text
    private var selectedModelDisplayText: String {
        if appState.settings.selectedAIMLModel.isEmpty {
            return "Select a model"
        }
        return appState.settings.selectedAIMLModel
    }
 
    // Extract the refresh button so we don't duplicate code
    private var refreshButton: some View {
        Button(action: { fetchAvailableModels(forceRefresh: true) }) {
            Image(systemName: isFetchingModels ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                .font(.system(size: isCompact ? 12 : 16))
                .foregroundColor(.blue)
                .rotationEffect(.degrees(isFetchingModels ? 360 : 0))
                .animation(isFetchingModels ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isFetchingModels)
        }
        .buttonStyle(.borderless)
        .disabled(appState.settings.aimlapiKey.isEmpty || isFetchingModels)
        .help("Refresh model list from AI/ML API (cached for 24 hours)")
        .accessibilityLabel("Refresh models")
    }
 
    private var modelLabel: some View {
        Text("Model:")
            .font(labelFont)
            .foregroundColor(.secondary)
            .help("Select an AI/ML image model")
            .fixedSize()
    }
 
    private var noModelsView: some View {
        Text("No models")
            .font(textFont)
            .foregroundColor(.gray)
            .italic()
            .fixedSize()
    }
 
    private var videoModeToggle: some View {
        HStack(spacing: 4) {
            Text("Video Mode:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .fixedSize()
            Toggle("", isOn: Binding(
                get: { appState.settings.task == .video },
                set: { appState.settings.task = $0 ? .video : .image }
            ))
                .labelsHidden()
                .onChange(of: appState.settings.task) { _ in
                    Task {
                        await Task.yield()
                        if appState.settings.provider == .aimlapi { self.fetchAvailableModels() }
                    }
                }
                .fixedSize()
        }
        .accessibilityLabel("Video Mode toggle")
    }
 
 
    @ViewBuilder
    private var comfyUIConfiguration: some View {
        ZStack {
            VStack(spacing: isCompact ? 8 : 12) {
                // Card 1: Server connection
                configCard {
                    comfyServerURLRow
                        .frame(minHeight: isCompact ? 32 : 36)
                }

                // Card 2: Workflow
                configCard {
                    comfyWorkflowRow
                        .frame(minHeight: isCompact ? 32 : 36)
                }

                // Card 3: Node configuration (only when workflow loaded)
                if !appState.generation.allNodes.isEmpty || !appState.generation.promptNodes.isEmpty {
                    configCard {
                        VStack(alignment: .leading, spacing: 0) {
                            // Show all nodes toggle
                            if !appState.generation.allNodes.isEmpty {
                                Toggle("Show all nodes", isOn: $appState.settings.comfyShowAllNodes)
                                    .font(labelFont)
                                    .help("When enabled, all workflow nodes appear in the Prompt, Output, and Additional Input dropdowns instead of only auto-detected compatible nodes. Use this to select custom or non-standard nodes.")
                                    .frame(minHeight: isCompact ? 32 : 36)
                            }

                            // Prompt node picker
                            if appState.settings.comfyShowAllNodes {
                                if !appState.generation.allNodes.isEmpty {
                                    cardDivider
                                    comfyPromptNodeRow
                                }
                            } else if !appState.generation.promptNodes.isEmpty {
                                if !appState.generation.allNodes.isEmpty { cardDivider }
                                comfyPromptNodeRow
                            }

                            // Image input nodes
                            let imageNodesToShow = appState.settings.comfyShowAllNodes ? appState.generation.allNodes : appState.generation.imageNodes
                            if !imageNodesToShow.isEmpty {
                                cardDivider
                                Text("Input Image Nodes")
                                    .font(labelFont)
                                    .foregroundColor(.secondary)
                                    .help("Check the image nodes to use (limits input slots)")
                                ForEach(imageNodesToShow) { node in
                                    Toggle(node.label, isOn: Binding(
                                        get: { appState.generation.selectedImageNodeIDs.contains(node.id) },
                                        set: { isOn in
                                            if isOn {
                                                appState.generation.selectedImageNodeIDs.insert(node.id)
                                            } else {
                                                appState.generation.selectedImageNodeIDs.remove(node.id)
                                            }
                                        }
                                    ))
                                    .font(textFont)
                                    .minimumScaleFactor(0.8)
                                    .padding(.vertical, 4)
                                    .help("Toggle to enable this node for image input")
                                }
                            }

                            // Output node picker
                            if appState.settings.comfyShowAllNodes {
                                if !appState.generation.allNodes.isEmpty {
                                    cardDivider
                                    comfyOutputNodeRow
                                }
                            } else if !appState.generation.outputNodes.isEmpty {
                                cardDivider
                                comfyOutputNodeRow
                            }
                        }
                    }
                }

                if let id = appState.generation.savedWorkflowID,
                   let saved = workflowLibrary.workflows.first(where: { $0.id == id }) {
                    configCard {
                        Button("Edit Named Workflow Inputs") { workflowToMap = saved }
                        Button("Run Saved Workflow…") { appState.presentedModal = .namedWorkflow(workflowID: saved.id, assetID: nil) }
                        Text("\(saved.exposedInputs.count) exposed inputs · revision \(saved.revision)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Card 4: Additional inputs (if workflow loaded)
                if appState.generation.comfyWorkflow != nil {
                    configCard {
                        AdditionalInputsSection()
                    }
                }
            }

            if showCopiedMessage {
                LiquidGlassToast(message: "Copied to Clipboard")
                    .transition(.toastTransition)
                    .help("Confirmation that text was copied to clipboard")
            }
        }
        .sheet(item: $workflowToMap) { workflow in
            WorkflowInputMappingView(workflow: workflow, serverURL: appState.settings.comfyServerURL)
        }
        .onChange(of: appState.settings.comfyJSONPath) { newPath in
            // Auto-connect to server when a workflow is loaded
            // This fetches sampler/scheduler/model options for the Advanced Parameters
            if !newPath.isEmpty && appState.generation.comfyServerStatus != .checking {
                testServer()
            }
        }
    }
 
    @ViewBuilder
    private var comfyServerURLRow: some View {
        HStack(spacing: isCompact ? 2 : 8) {
            Text("Server:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Enter the URL of your ComfyUI server")
                .fixedSize()

            // Status indicator
            serverStatusIndicator
                .help(serverStatusHelp)

            TextField("e.g., http://localhost:8188", text: $appState.settings.comfyServerURL)
                .textFieldStyle(.roundedBorder)
                .font(textFont)
                .autocorrectionDisabled()
                .frame(maxWidth: .infinity)
                .minimumScaleFactor(0.8)
                .help(Text(verbatim: "Server URL, e.g., http://localhost:8188"))
                .accessibilityLabel("ComfyUI server URL")
                .onChange(of: appState.settings.comfyServerURL) { _ in
                    // Reset status when URL changes (user must manually test)
                    appState.generation.comfyServerStatus = .unknown
                    appState.generation.fetchedSamplers = nil
                    appState.generation.fetchedSchedulers = nil
                    appState.generation.fetchedCheckpoints = nil
                    appState.generation.fetchedVAEs = nil
                    appState.generation.fetchedLoRAs = nil
                }
            Button(action: {
                testServer()
            }) {
                Image(systemName: isTestingServer ? "arrow.clockwise.circle" : "checkmark.circle")
                    .font(.system(size: isCompact ? 12 : 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .disabled(isTestingServer || appState.settings.comfyServerURL.isEmpty)
            .help("Check if the ComfyUI server is available")
            .accessibilityLabel("Test server connection")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var serverStatusIndicator: some View {
        switch appState.generation.comfyServerStatus {
        case .unknown:
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
        case .checking:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 8, height: 8)
        case .connected:
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        case .failed:
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
    }

    private var serverStatusHelp: String {
        switch appState.generation.comfyServerStatus {
        case .unknown:
            return "Server status unknown - click test button"
        case .checking:
            return "Checking server connection..."
        case .connected(let nodeCount):
            return "Connected (\(nodeCount) node types available)"
        case .failed(let error):
            return "Connection failed: \(error)"
        }
    }
 
    @ViewBuilder
    private var comfyWorkflowRow: some View {
        HStack(spacing: isCompact ? 2 : 8) {
            Text("Workflow:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Select a workflow from library or browse for file")
                .fixedSize()

            Menu {
                // Current workflow (if loaded)
                if !appState.settings.comfyJSONPath.isEmpty {
                    Section {
                        Label(URL(fileURLWithPath: appState.settings.comfyJSONPath).lastPathComponent, systemImage: "checkmark")
                    }
                }

                // Saved workflows
                if !workflowLibrary.workflows.isEmpty {
                    Section("Saved Workflows") {
                        ForEach(workflowLibrary.sortedWorkflows) { workflow in
                            Menu {
                                Button {
                                    loadSavedWorkflow(workflow)
                                } label: {
                                    Label("Load", systemImage: "play")
                                }
                                Divider()
                                Button {
                                    proposedWorkflowName = workflow.name
                                    workflowToRename = workflow
                                } label: {
                                    Label("Rename...", systemImage: "pencil")
                                }
                                Button {
                                    exportWorkflow(workflow)
                                } label: {
                                    Label("Export to File...", systemImage: "square.and.arrow.up")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    workflowLibrary.deleteWorkflow(workflow)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            } label: {
                                Label(workflow.name, systemImage: "doc.fill")
                            }
                        }
                    }
                }

                Divider()

                // Browse for file
                Button {
                    Log.debug("Showing json file picker")
                    PlatformFilePicker.presentOpenPanel(allowedTypes: [.json, .png], allowsMultiple: false, canChooseDirectories: false) { result in
                        onComfyJSONSelected(result)
                    }
                } label: {
                    Label("Browse for File...", systemImage: "folder")
                }

                // Save current workflow (only if one is loaded)
                if appState.generation.comfyWorkflow != nil {
                    Divider()
                    if let id = appState.generation.savedWorkflowID,
                       let saved = workflowLibrary.workflows.first(where: { $0.id == id }) {
                        Button {
                            saveCurrentWorkflow(name: saved.name, replacingID: id)
                        } label: {
                            Label("Update Saved Workflow", systemImage: "square.and.arrow.down")
                        }
                    }
                    Button {
                        // Default name is the filename without extension
                        let filename = URL(fileURLWithPath: appState.settings.comfyJSONPath).deletingPathExtension().lastPathComponent
                        let baseName = filename.isEmpty ? "My Workflow" : filename
                        saveWorkflowName = appState.generation.savedWorkflowID == nil ? baseName : baseName + " Copy"
                        showSaveWorkflowDialog = true
                    } label: {
                        Label(appState.generation.savedWorkflowID == nil ? "Save to Library..." : "Save a Copy...", systemImage: "plus.square.on.square")
                    }
                }
            } label: {
                HStack {
                    Text(appState.settings.comfyJSONPath.isEmpty ? "Select Workflow" : URL(fileURLWithPath: appState.settings.comfyJSONPath).lastPathComponent)
                        .font(pickerFont)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .help("Select workflow from library or browse")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if let message = workflowLibrary.storageError { errorItem = AlertError(message: message, fullMessage: nil) }
        }
        .onChange(of: workflowLibrary.storageError) { _, message in
            if let message { errorItem = AlertError(message: message, fullMessage: nil) }
        }
        .sheet(isPresented: $showSaveWorkflowDialog) {
            SaveWorkflowSheet(
                workflowName: $saveWorkflowName,
                onSave: { name in
                    saveCurrentWorkflow(name: name)
                    showSaveWorkflowDialog = false
                },
                onCancel: {
                    showSaveWorkflowDialog = false
                }
            )
        }
        .alert("Rename Workflow", isPresented: Binding(
            get: { workflowToRename != nil },
            set: { if !$0 { workflowToRename = nil } }
        )) {
            TextField("Workflow Name", text: $proposedWorkflowName)
            Button("OK") {
                if let workflow = workflowToRename,
                   !proposedWorkflowName.trimmingCharacters(in: .whitespaces).isEmpty {
                    workflowLibrary.renameWorkflow(workflow, to: proposedWorkflowName.trimmingCharacters(in: .whitespaces))
                }
                workflowToRename = nil
            }
            Button("Cancel", role: .cancel) {
                workflowToRename = nil
            }
        } message: {
            Text("Enter a new name for the workflow.")
        }
    }

    /// Loads a saved workflow from the library
    private func loadSavedWorkflow(_ workflow: SavedWorkflow) {
        guard let workflowJSON = workflowLibrary.getWorkflowJSON(workflow) else {
            Log.debug("Failed to load workflow JSON from library")
            return
        }

        // Load the workflow
        appState.generation.comfyWorkflow = workflowJSON
        appState.generation.savedWorkflowID = workflow.id
        appState.settings.comfyJSONPath = workflow.name  // Use name as display path

        // Process nodes (this clears additionalInputs)
        appState.generation.processWorkflowForNodes(json: workflowJSON)

        // Restore saved node selections
        if let promptNodeID = workflow.promptNodeID {
            appState.generation.comfyPromptNodeID = promptNodeID
        }
        if let outputNodeID = workflow.outputNodeID {
            appState.generation.comfyOutputNodeID = outputNodeID
        }
        appState.generation.selectedImageNodeIDs = Set(workflow.imageNodeIDs)

        // Restore additional inputs (after processWorkflowForNodes which clears them)
        if let savedInputs = workflow.additionalInputs {
            // Filter out inputs that reference nodes no longer in the workflow
            let validNodeIDs = Set(appState.generation.allNodes.map { $0.id })
            let validInputs = savedInputs.filter { input in
                input.boundNodeID.isEmpty || validNodeIDs.contains(input.boundNodeID)
            }
            appState.generation.additionalInputs = validInputs
        }

        // Mark as used (moves to top of recent list)
        workflowLibrary.markAsUsed(workflow)

        Log.debug("Loaded saved workflow: \(workflow.name) with \(workflow.additionalInputs?.count ?? 0) additional inputs")
    }

    /// Saves the current workflow to the library
    private func saveCurrentWorkflow(name: String, replacingID: UUID? = nil) {
        guard let workflow = appState.generation.comfyWorkflow else { return }

        do {
            let saved = try workflowLibrary.saveWorkflow(
                name: name,
                workflowJSON: workflow,
                promptNodeID: appState.generation.comfyPromptNodeID,
                outputNodeID: appState.generation.comfyOutputNodeID,
                imageNodeIDs: appState.generation.selectedImageNodeIDs,
                additionalInputs: appState.generation.additionalInputs,
                replacingID: replacingID,
                exposedInputs: appState.generation.savedWorkflowID.flatMap { id in workflowLibrary.workflows.first { $0.id == id }?.exposedInputs },
                outputNodeIDs: appState.generation.savedWorkflowID.flatMap { id in workflowLibrary.workflows.first { $0.id == id }?.outputNodeIDs }
            )
            appState.generation.savedWorkflowID = saved.id
            Log.debug("Saved workflow to library: \(name) with \(appState.generation.additionalInputs.count) additional inputs")
        } catch {
            Log.debug("Failed to save workflow: \(error)")
            errorItem = AlertError(message: "Could not save workflow: \(error.localizedDescription)", fullMessage: nil)
        }
    }

    /// Exports a saved workflow to a JSON file
    private func exportWorkflow(_ workflow: SavedWorkflow) {
        guard let json = workflowLibrary.getWorkflowJSON(workflow) else { return }
        let safeName = workflow.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        PlatformFileSaver.presentSavePanel(
            suggestedName: "\(safeName).json",
            allowedTypes: [.json]
        ) { result in
            if case .success(let url) = result {
                do {
                    let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: url, options: .atomic)
                } catch {
                    Log.debug("Failed to export workflow: \(error)")
                }
            }
        }
    }

    @ViewBuilder
    private var comfyPromptNodeRow: some View {
        let nodeList = appState.settings.comfyShowAllNodes ? appState.generation.allNodes : appState.generation.promptNodes

        HStack(spacing: isCompact ? 2 : 8) {
            Text("Prompt Node:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Select the prompt node from the workflow")
                .fixedSize()

            let selectedNode = nodeList.first { $0.id == appState.generation.comfyPromptNodeID }
                ?? appState.generation.allNodes.first { $0.id == appState.generation.comfyPromptNodeID }

            Menu {
                ForEach(nodeList) { node in
                    Button {
                        appState.generation.comfyPromptNodeID = node.id
                    } label: {
                        Text(node.label)
                            .font(pickerFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } label: {
                HStack {
                    Text(selectedNode?.label ?? "Select node...")
                        .font(pickerFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .help("Choose the prompt node")
            .accessibilityLabel("Prompt node selector")

            Button(action: {
                if let selectedNode = nodeList.first(where: { $0.id == appState.generation.comfyPromptNodeID }) {
                    copyToClipboard(selectedNode.promptText ?? "")
                    withAnimation {
                        showCopiedMessage = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showCopiedMessage = false
                        }
                    }
                }
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: isCompact ? 12 : 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
            .help("Copy prompt text to clipboard")
            .accessibilityLabel("Copy prompt text")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
 
    @ViewBuilder
    private var comfyOutputNodeRow: some View {
        let nodeList = appState.settings.comfyShowAllNodes ? appState.generation.allNodes : appState.generation.outputNodes

        HStack(spacing: isCompact ? 2 : 8) {
            Text("Output Node:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Select the output node from the workflow")
                .fixedSize()

            let selectedNode = nodeList.first { $0.id == appState.generation.comfyOutputNodeID }
                ?? appState.generation.allNodes.first { $0.id == appState.generation.comfyOutputNodeID }

            Menu {
                ForEach(nodeList) { node in
                    Button {
                        appState.generation.comfyOutputNodeID = node.id
                    } label: {
                        Text(node.label)
                            .font(pickerFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } label: {
                HStack {
                    Text(selectedNode?.label ?? "Select node...")
                        .font(pickerFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .help("Choose the output node")
            .accessibilityLabel("Output node selector")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
 
    @ViewBuilder
    private var comfyBatchSizeRow: some View {
        HStack(spacing: isCompact ? 2 : 8) {
            Text("Batch Size:")
                .font(labelFont)
                .foregroundColor(.secondary)
                .help("Number of images to generate in one run")
                .fixedSize()
 
            HStack(spacing: 0) {
                TextField("", value: $appState.settings.comfyBatchSize, formatter: NumberFormatter())
                    .font(textFont)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(width: 50)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
 
                Stepper("", value: $appState.settings.comfyBatchSize, in: 1...32)
            }
            .fixedSize()
            .help("Number of images to generate in one run (uses random seeds for variation)")
            .accessibilityLabel("Batch size stepper")
            .onChange(of: appState.settings.comfyBatchSize) { newValue in
                Task {
                    await Task.yield()
                    appState.settings.comfyBatchSize = max(1, min(32, newValue))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
 
    private func testServer() {
        isTestingServer = true
        serverErrorMessage = ""
        appState.generation.comfyServerStatus = .checking

        Task {
            defer { isTestingServer = false }

            // Auto-fix missing scheme in the stored URL
            let baseURL = ComfyUIFormatConverter.normalizedServerURL(appState.settings.comfyServerURL)
            if !baseURL.isEmpty && baseURL != appState.settings.comfyServerURL {
                appState.settings.comfyServerURL = baseURL
            }

            do {
                // Fetch + cache object_info for offline workflow conversion
                let objectInfo = try await ComfyUIFormatConverter.fetchAndCacheObjectInfo(serverURL: baseURL)
                appState.generation.comfyServerStatus = .connected(nodeCount: objectInfo.count)

                // Extract sampler/scheduler options from KSampler node info
                extractSamplerSchedulerOptions(from: objectInfo)
                showServerSuccessAlert = true
            } catch let error as ComfyUIFormatConverter.ObjectInfoFetchError {
                serverErrorMessage = error.localizedDescription
                appState.generation.comfyServerStatus = .failed(error.localizedDescription)
                showServerErrorAlert = true
            } catch {
                serverErrorMessage = "Failed to connect: \(error.localizedDescription)"
                showServerErrorAlert = true
                appState.generation.comfyServerStatus = .failed(error.localizedDescription)
            }
        }
    }

    /// Extracts the option list from a ComfyUI object_info combo entry, tolerating both the
    /// legacy form `[[String], meta]` and the newer `["COMBO", {"options"/"choices": [...]}]`.
    static func comboOptions(_ info: [Any]?) -> [String]? {
        guard let info = info else { return nil }
        if let opts = info.first as? [String] { return opts }            // legacy: first element is the list
        for element in info {                                            // newer: metadata dict carries the list
            if let meta = element as? [String: Any] {
                if let opts = meta["options"] as? [String] { return opts }
                if let opts = meta["choices"] as? [String] { return opts }
            }
        }
        return nil
    }

    /// Extracts sampler, scheduler, and model options from ComfyUI object_info response
    private func extractSamplerSchedulerOptions(from objectInfo: [String: Any]) {
        // Extract sampler/scheduler from KSampler nodes
        let samplerNodeTypes = ["KSampler", "KSamplerAdvanced", "SamplerCustom"]
        for nodeType in samplerNodeTypes {
            guard let nodeInfo = objectInfo[nodeType] as? [String: Any],
                  let input = nodeInfo["input"] as? [String: Any],
                  let required = input["required"] as? [String: Any] else {
                continue
            }

            // Extract sampler_name options
            if appState.generation.fetchedSamplers == nil,
               let samplerOptions = Self.comboOptions(required["sampler_name"] as? [Any]) {
                appState.generation.fetchedSamplers = samplerOptions
                Log.debug("Fetched \(samplerOptions.count) samplers from ComfyUI")
            }

            // Extract scheduler options
            if appState.generation.fetchedSchedulers == nil,
               let schedulerOptions = Self.comboOptions(required["scheduler"] as? [Any]) {
                appState.generation.fetchedSchedulers = schedulerOptions
                Log.debug("Fetched \(schedulerOptions.count) schedulers from ComfyUI")
            }

            if appState.generation.fetchedSamplers != nil && appState.generation.fetchedSchedulers != nil {
                break
            }
        }

        // Extract checkpoint options from CheckpointLoaderSimple or CheckpointLoader
        let checkpointNodeTypes = ["CheckpointLoaderSimple", "CheckpointLoader"]
        for nodeType in checkpointNodeTypes {
            guard appState.generation.fetchedCheckpoints == nil,
                  let nodeInfo = objectInfo[nodeType] as? [String: Any],
                  let input = nodeInfo["input"] as? [String: Any],
                  let required = input["required"] as? [String: Any],
                  let ckptOptions = Self.comboOptions(required["ckpt_name"] as? [Any]) else {
                continue
            }
            appState.generation.fetchedCheckpoints = ckptOptions
            Log.debug("Fetched \(ckptOptions.count) checkpoints from ComfyUI")
            break
        }

        // Extract VAE options from VAELoader
        if appState.generation.fetchedVAEs == nil,
           let nodeInfo = objectInfo["VAELoader"] as? [String: Any],
           let input = nodeInfo["input"] as? [String: Any],
           let required = input["required"] as? [String: Any],
           let vaeOptions = Self.comboOptions(required["vae_name"] as? [Any]) {
            appState.generation.fetchedVAEs = vaeOptions
            Log.debug("Fetched \(vaeOptions.count) VAEs from ComfyUI")
        }

        // Extract LoRA options from LoraLoader
        if appState.generation.fetchedLoRAs == nil,
           let nodeInfo = objectInfo["LoraLoader"] as? [String: Any],
           let input = nodeInfo["input"] as? [String: Any],
           let required = input["required"] as? [String: Any],
           let loraOptions = Self.comboOptions(required["lora_name"] as? [Any]) {
            appState.generation.fetchedLoRAs = loraOptions
            Log.debug("Fetched \(loraOptions.count) LoRAs from ComfyUI")
        }
    }
 
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
 

    
    private func fetchAvailableModels(forceRefresh: Bool = false) {
        // Cache fresh → use it, no network call
        if !forceRefresh && !appState.allAIMLModels.isEmpty && !appState.isAIMLModelCacheStale {
            filterModelsLocally()
            return
        }

        guard !appState.settings.aimlapiKey.isEmpty else {
            errorItem = AlertError(message: "Enter API key first", fullMessage: nil)
            return
        }

        let hasStaleCache = !appState.allAIMLModels.isEmpty

        // Stale cache exists → serve it immediately, fetch silently in background
        if !forceRefresh && hasStaleCache {
            filterModelsLocally()
        }

        // Clear cache if forcing refresh
        if forceRefresh {
            appState.clearAIMLModelCache()
        }

        // Only show loading indicator if there's nothing to display
        let showLoading = forceRefresh || !hasStaleCache

        Task {
            if showLoading {
                await MainActor.run {
                    isFetchingModels = true
                    errorItem = nil
                }
            }

            defer {
                if showLoading {
                    Task { @MainActor in isFetchingModels = false }
                }
            }

            let url = AIMLEndpoints.modelsURL

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(appState.settings.aimlapiKey)", forHTTPHeaderField: "Authorization")

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(AIMLEndpoints.ModelsResponse.self, from: data)
                let allIDs = response.data.map { $0.id }
                // Curated mode matches registry IDs against the API model list. Many registry
                // IDs are *aliases* of a canonical /models `id` (e.g. "google/veo-3.1-i2v" ->
                // canonical "veo-3.1-..."), so include aliases in the match set — otherwise
                // those configured models silently vanish from the curated picker.
                let matchSet = response.data.flatMap { [$0.id] + ($0.aliases ?? []) }
                // id→aliases map (both lowercased) so a selected-but-unregistered id can be
                // normalized to the registry-canonical id it aliases (WS-4 selection de-drift).
                var aliasMap: [String: [String]] = [:]
                for model in response.data {
                    let aliases = model.aliases ?? []
                    if !aliases.isEmpty {
                        aliasMap[model.id.lowercased()] = aliases.map { $0.lowercased() }
                    }
                }

                // Derived off the main actor: it is a pure grouping pass over ~900 entries.
                let servedModels = ServedModel.generationModels(from: response)
                await MainActor.run {
                    appState.cacheAIMLModels(allIDs, matchSet: matchSet, aliases: aliasMap)
                    appState.cacheAIMLServedModels(servedModels)
                    filterModelsLocally()
                }
            } catch {
                // Only show error if user is waiting (no stale cache to fall back on)
                if showLoading {
                    await MainActor.run {
                        errorItem = AlertError(message: "Fetch error: \(error.localizedDescription)", fullMessage: nil)
                    }
                }
            }
        }
    }

    /// Rebuilds the picker's id list from the catalog and the captured `/models` metadata.
    ///
    /// This replaced a 35-token substring heuristic. Measured against the captured live response,
    /// that heuristic put **23 non-video entries in the video list** (22 MiniMax: 5 music, 6 speech,
    /// 11 pure LLMs) because its video branch had no negative filter, **missed 14 real video
    /// models**, and emitted **131 image rows over 120 unique ids** — the 11 duplicates being the
    /// ids the API serves on two endpoint families at once, which is what fed
    /// `ForEach(others, id: \.self)` duplicate SwiftUI identities. `ModelBrowser` classifies by the
    /// endpoint family the API itself publishes, canonicalizes through the alias index and dedupes
    /// at the boundary, so all three are structural rather than fixed.
    private func filterModelsLocally() {
        // Nothing fetched yet is not an error — it is the pre-fetch state, and it must stay silent.
        guard !appState.aimlServedModels.isEmpty else {
            availableModels = []
            appState.configurationAvailableModels = []
            return
        }

        let finalModels = ModelBrowser.selectableIDs(
            task: appState.settings.task,
            served: appState.aimlServedModels,
            showAll: appState.settings.showAllAIMLModels)

        availableModels = finalModels
        appState.configurationAvailableModels = finalModels
        // One policy, one place. The auto-select-first that used to live here reassigned whenever
        // the persisted selection was absent from the list it had just rebuilt — which fires on
        // every curated/advanced toggle and every image↔video switch — and the didSet then nilled
        // the user's hand-edited JSON. `SelectionHealer` reassigns only when the selection is
        // genuinely unusable, and never while a custom payload exists.
        appState.healSelectedAIMLModel()

        if finalModels.isEmpty {
            let type = appState.settings.isVideoMode ? "video" : "image"
            errorItem = AlertError(
                message: "No \(type) models found",
                fullMessage: "Try toggling Advanced Mode or check your API key."
            )
        } else {
            errorItem = nil
        }
    }
 
    private var isMacOS: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
 
    private func handleImageSlotPersistence() {
        // Capture appState reference for use in async block
        let state = appState

        DispatchQueue.main.async {
            // Capture current values inside async block to avoid race conditions
            let currentMax = state.maxImageSlots
            let currentCount = state.ui.imageSlots.count

            if currentMax < currentCount {
                // Decrease: move excess to lastImageSlots
                let excessCount = currentCount - currentMax
                let excess = Array(state.ui.imageSlots.suffix(excessCount))
                state.ui.imageSlots.removeLast(excessCount)
                state.ui.lastImageSlots = excess + state.ui.lastImageSlots
            } else if currentMax > currentCount && !state.ui.lastImageSlots.isEmpty {
                // Increase: restore from lastImageSlots
                let needed = currentMax - currentCount
                let toRestoreCount = min(needed, state.ui.lastImageSlots.count)
                let toRestore = Array(state.ui.lastImageSlots.prefix(toRestoreCount))
                state.ui.imageSlots += toRestore
                state.ui.lastImageSlots.removeFirst(toRestoreCount)
            }
        }
    }
}
 
extension View {
    func errorAlert(errorItem: Binding<AlertError?>, detailedError: Binding<DetailedError?>) -> some View {
        alert(item: errorItem) { error in
            if let full = error.fullMessage {
                Alert(
                    title: Text("Operation Failed"),
                    message: error.message.isEmpty ? nil : Text(error.message),
                    primaryButton: .default(Text("OK")),
                    secondaryButton: .default(Text("More Info")) {
                        detailedError.wrappedValue = DetailedError(message: full)
                    }
                )
            } else {
                Alert(
                    title: Text("Operation Failed"),
                    message: error.message.isEmpty ? nil : Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}
