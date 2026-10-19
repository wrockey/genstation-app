import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import GenStationCore

struct MainFormView: View {
    @Binding var prompt: String
    @Binding var showApiKey: Bool
    @Binding var isTestingApi: Bool
    @Binding var errorItem: AlertError?
    @Binding var imageScale: CGFloat
    @Binding var promptTextView: (any PlatformTextView)?
    @State private var isUnsafe: Bool = false
    let isLoading: Bool
    let progress: Double
    let progressStep: Int
    let progressMax: Int
    let currentNodeName: String?
    @Binding var isCancelled: Bool
    let onSubmit: () -> Void
    let onStop: () -> Void
    let onPopOut: () -> Void
    let onAnnotate: (UUID) -> Void
    let onDescribeImage: (UIState.ImageSlot) -> Void
    let onComfyJSONSelected: (Result<[URL], Error>) -> Void
    let onBatchFileSelected: (Result<[URL], Error>) -> Void
    let onBatchSubmit: () -> Void
    let onEditBatchFile: () -> Void
    let onClearBatchFile: () -> Void
    let onReloadBatchFile: () -> Void
    @EnvironmentObject var appState: AppState
    @Environment(\.undoManager) private var undoManager
    @State private var showCopiedMessage: Bool = false
    @Binding var batchFilePath: String
    @Binding var batchStartIndex: Int
    @Binding var batchEndIndex: Int
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showUndoButton: Bool = false
    @State private var localProvider: Provider = .gemini
    @Binding var aimlBalance: Double?
    @Binding var balanceFetchTask: Task<Void, Never>?
    @State private var showOpeningEditorToast: Bool = false
    @State private var scrollToSubmitTrigger: Bool = false
    
    // MARK: - Liquid Glass Core
        private var modeAccent: Color {
            appState.settings.provider.liquidAccent
        }

        /// Unified neutral glass background - no mode tint
        private var glassBackground: some View {
            Group {
                Color.clear.background(.ultraThickMaterial)
            }
        }

    /// Subtle divider between sections
    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
    }

    private var isCompact: Bool {
        sizeClass == .compact
    }

    private var isSubmitDisabled: Bool {
        switch localProvider {
        case .gemini:
            return appState.settings.apiKey.isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
        case .comfyUI:
            let effectivePromptEmpty = appState.prompt.isEmpty && selectedPromptText.isEmpty
            let warningNotAccepted = !AppStorageContext.defaults.bool(forKey: "comfyUIWarningAccepted")
            
            return appState.generation.comfyWorkflow == nil ||
                   appState.generation.comfyPromptNodeID.isEmpty ||
                   appState.generation.comfyOutputNodeID.isEmpty ||
                   appState.settings.comfyServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   effectivePromptEmpty ||
                   warningNotAccepted
            
        case .grok:
            return appState.settings.grokApiKey.isEmpty || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
        case .aimlapi:
            let apiKeyMissing = appState.settings.aimlapiKey.isEmpty
            let promptEmpty = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let requiresImage = appState.currentAIMLModel.requiresInputImage
            let noImagesLoaded = appState.ui.imageSlots.allSatisfy { $0.thumbnail == nil }
            
            return apiKeyMissing || promptEmpty || (requiresImage && noImagesLoaded)
        }
    }
    
    private var submitButtonHint: String? {
        // 1. Output folder (highest priority)
        if appState.settings.outputPath.isEmpty {
            return "Select an output folder in General Options"
        }
        
        // 2. API key checks
        switch appState.settings.provider {
        case .gemini:
            if appState.settings.apiKey.isEmpty {
                return "Enter your Gemini API key in General Options"
            }
        case .grok:
            if appState.settings.grokApiKey.isEmpty {
                return "Enter your Grok API key in General Options"
            }
        case .aimlapi:
            if appState.settings.aimlapiKey.isEmpty {
                return "Enter your AI/ML API key in General Options"
            }
        case .comfyUI:
            break
        }
        
        // 3. NEW: Required input image (AIMLAPI only)
        if appState.settings.provider == .aimlapi,
           appState.currentAIMLModel.requiresInputImage,
           appState.ui.imageSlots.allSatisfy({ $0.thumbnail == nil }) {
            return "This model requires at least one input image"
        }
        
        // 4. Prompt requirement
        let promptEmpty = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if promptEmpty && appState.settings.provider != .comfyUI {
            return "Enter a prompt"
        }
        
        // 5. ComfyUI-specific blockers (your existing logic)
        if appState.settings.provider == .comfyUI {
            if appState.generation.comfyWorkflow == nil {
                return "Load a ComfyUI workflow (.json or .png)"
            }
            if appState.settings.comfyServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Enter your ComfyUI server URL"
            }
            if appState.generation.comfyPromptNodeID.isEmpty {
                return "Select a prompt node in the workflow"
            }
            if appState.generation.comfyOutputNodeID.isEmpty {
                return "Select an output node (e.g. SaveImage)"
            }
            if !AppStorageContext.defaults.bool(forKey: "comfyUIWarningAccepted") {
                return "You must accept the ComfyUI responsibility warning"
            }
            let nodeHasText = !(selectedPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if prompt.isEmpty && !nodeHasText {
                return "Enter a prompt, or select a prompt node that contains text"
            }
        }
        
        return nil
    }

    private var selectedPromptText: String {
        appState.generation.promptNodes.first(where: { $0.id == appState.generation.comfyPromptNodeID })?.promptText ?? ""
    }

    private var isBatchSubmitDisabled: Bool {
        switch localProvider {
        case .gemini:
            if appState.settings.apiKey.isEmpty {
                return true
            }
        case .comfyUI:
            if appState.generation.comfyWorkflow == nil || appState.generation.comfyPromptNodeID.isEmpty || appState.generation.comfyOutputNodeID.isEmpty || appState.settings.comfyServerURL.isEmpty {
                return true
            }
        case .grok:
            if appState.settings.grokApiKey.isEmpty {
                return true
            }
        case .aimlapi:
            if appState.settings.aimlapiKey.isEmpty {
                return true
            }
        }
        guard !appState.batchPrompts.isEmpty else { return true }
        let start = batchStartIndex
        let end = batchEndIndex
        return start < 1 || end > appState.batchPrompts.count || start > end
    }

    private var mainSections: some View {
        VStack(spacing: 0) {
            modePickerSection
                .padding(.bottom, 20)

            sectionDivider
            configurationSection

            sectionDivider
            promptSection

            sectionDivider
            inputImagesSection

            sectionDivider
            submitOrLoadingSection
                .background(
                    ScrollToHelper(trigger: scrollToSubmitTrigger, anchor: .top) {
                        scrollToSubmitTrigger = false
                    }
                )

            sectionDivider
            responseSection
        }
        .padding(.horizontal, isCompact ? 16 : 24)
        .padding(.vertical, 20)
    }

    private var modePickerSection: some View {
        ModePickerView(localProvider: $localProvider)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.1), radius: 8)
            .tint(modeAccent)  // Only selected segment uses mode color
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Neutral section header
            Label {
                Text("Configuration")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
            } icon: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 32)
            }
            .padding(.horizontal, 4)

            ConfigurationSectionView(
                showApiKey: $showApiKey,
                isTestingApi: $isTestingApi,
                errorItem: $errorItem,
                aimlBalance: $aimlBalance,
                balanceFetchTask: $balanceFetchTask,
                onComfyJSONSelected: onComfyJSONSelected
            )
            .padding(.top, 8)
        }
    }

    private var promptSection: some View {
        ZStack(alignment: .bottomTrailing) {
            PromptSection(
                prompt: $prompt,
                isUnsafe: $isUnsafe,
                platformTextView: $promptTextView,
                batchStartIndex: $batchStartIndex,
                batchEndIndex: $batchEndIndex,
                onBatchFileSelected: onBatchFileSelected,
                onEditBatchFile: onEditBatchFile,
                onReloadBatchFile: onReloadBatchFile,
                onClearBatchFile: onClearBatchFile
            )
            .frame(maxWidth: .infinity)

            // Floating action cluster - swaps based on mode
            Group {
                if appState.ui.promptMode == .single {
                    // Single mode: paste/copy/clear
                    HStack(spacing: 16) {
                        Button(action: pasteToPrompt) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Paste from clipboard")
                        .accessibilityLabel("Paste from clipboard")

                        Button(action: copyPromptToClipboard) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(prompt.isEmpty ? .secondary : .blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(prompt.isEmpty)
                        .opacity(prompt.isEmpty ? 0.4 : 1.0)
                        .help("Copy prompt")
                        .accessibilityLabel("Copy prompt")

                        Button(action: clearPrompt) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(prompt.isEmpty ? .secondary : .red)
                        }
                        .buttonStyle(.plain)
                        .disabled(prompt.isEmpty)
                        .opacity(prompt.isEmpty ? 0.4 : 1.0)
                        .help("Clear prompt")
                        .accessibilityLabel("Clear prompt")
                        .keyboardShortcut(.delete)

                        // Mini submit shortcut
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 1, height: 20)

                        Button {
                            onSubmit()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                scrollToSubmitTrigger = true
                            }
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(isSubmitDisabled || isLoading ? .secondary : modeAccent)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitDisabled || isLoading)
                        .opacity(isSubmitDisabled || isLoading ? 0.4 : 1.0)
                        .help("Generate")
                        .accessibilityLabel("Generate image")
                    }
                } else {
                    // Batch mode: new/open | run
                    HStack(spacing: 16) {
                        Button {
                            // New: clear file, open editor with empty untitled buffer
                            appState.ui.batchNewFilePrompts = []
                            appState.batchPrompts = []
                            appState.batchFilePath = ""
                            appState.batchFileURL = nil
                            AppStorageContext.defaults.removeObject(forKey: "batchFileBookmark")
                            onEditBatchFile()
                        } label: {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("New batch file")
                        .accessibilityLabel("New batch file")

                        Button {
                            PlatformFilePicker.presentOpenPanel(
                                allowedTypes: [.plainText],
                                allowsMultiple: false,
                                canChooseDirectories: false,
                                callback: onBatchFileSelected
                            )
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Open batch file")
                        .accessibilityLabel("Open batch file")

                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 1, height: 20)

                        Button {
                            onBatchSubmit()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                scrollToSubmitTrigger = true
                            }
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(isBatchSubmitDisabled || isLoading ? .secondary : modeAccent)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBatchSubmitDisabled || isLoading)
                        .opacity(isBatchSubmitDisabled || isLoading ? 0.4 : 1.0)
                        .help("Run Batch")
                        .accessibilityLabel("Run batch")
                    }
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.1), radius: 8)
            .animation(DS.Anim.standard, value: appState.ui.promptMode)
            .padding(.trailing, 20)
            .offset(y: 84)
        }
        .padding(.bottom, 80)
    }

    private var inputImagesSection: some View {
        InputImagesSectionView(
            errorItem: $errorItem,
            onAnnotate: onAnnotate,
            onDescribeImage: onDescribeImage
        )
    }

    private var submitOrLoadingSection: some View {
        let isBatchMode = appState.ui.promptMode == .batch

        return VStack(alignment: .leading, spacing: 12) {
            // Section header - "Generate" for both single and batch modes
            Label {
                Text(isLoading ? "Generating…" : "Generate")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
            } icon: {
                Image(systemName: isLoading ? "bolt.horizontal.fill" : "paperplane.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 32)
            }
            .padding(.horizontal, 4)

            if isLoading {
                LoadingView(mode: appState.settings.provider, progress: progress, progressStep: progressStep, progressMax: progressMax, currentNodeName: currentNodeName, isCancelled: $isCancelled, onStop: onStop, batchTotal: appState.ui.batchTotalCount, batchCurrent: appState.ui.batchCurrentIndex, videoJobQueue: appState.settings.usesVideoQueue ? appState.jobQueue : nil)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 16) {
                    // Custom JSON/Endpoint Warning (AI/ML API only)
                    if appState.settings.provider == .aimlapi &&
                       (appState.settings.customAIMLPayload != nil || appState.settings.customAIMLEndpoint != nil) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.yellow)

                            Text("Custom JSON Active")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)

                            Spacer()

                            Button {
                                appState.settings.customAIMLPayload = nil
                                appState.settings.customAIMLEndpoint = nil
                            } label: {
                                Text("Reset")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                        )
                        .help("UI settings are overridden by custom JSON. Click Reset to use UI controls.")
                    }

                    if isBatchMode {
                        // Batch Submit Button
                        Button {
                            onBatchSubmit()
                        } label: {
                            Label("Run Batch", systemImage: "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isBatchSubmitDisabled || isLoading ? .gray : modeAccent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .shadow(color: modeAccent.opacity(0.4), radius: 12, y: 6)
                        .scaleEffect(isBatchSubmitDisabled ? 0.96 : 1.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isBatchSubmitDisabled)
                        .disabled(isBatchSubmitDisabled || isLoading)
                    } else {
                        // Single Submit Button
                        SubmitButtonView(isDisabled: isSubmitDisabled, onSubmit: onSubmit)
                            .tint(modeAccent)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .shadow(color: modeAccent.opacity(0.4), radius: 12, y: 6)
                            .scaleEffect(isSubmitDisabled ? 0.96 : 1.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isSubmitDisabled)
                    }

                    // Helpful Hint - shows for both modes
                    if let hint = currentHint {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.orange)

                            Text(hint)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .scale))
                        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: hint)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var currentHint: String? {
        if appState.ui.promptMode == .batch {
            return batchSubmitHint
        } else {
            return submitButtonHint
        }
    }

    private var batchSubmitHint: String? {
        if appState.batchPrompts.isEmpty {
            return "Enter prompts or load a batch file"
        }
        return nil
    }

    private var batchModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Neutral section header
            Label {
                Text("Batch Mode")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
            } icon: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 32)
            }
            .padding(.horizontal, 4)

            BatchModeSectionView(
                batchFilePath: $batchFilePath,
                batchStartIndex: $batchStartIndex,
                batchEndIndex: $batchEndIndex,
                showOpeningEditorToast: $showOpeningEditorToast,
                isLoading: isLoading,
                isBatchSubmitDisabled: isBatchSubmitDisabled,
                onBatchFileSelected: onBatchFileSelected,
                onEditBatchFile: onEditBatchFile,
                onReloadBatchFile: onReloadBatchFile,
                onClearBatchFile: onClearBatchFile,
                onBatchSubmit: onBatchSubmit
            )
            .padding(.top, 8)
        }
    }

    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Neutral section header
            Label {
                Text("Response")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
            } icon: {
                Image(systemName: "photo.stack")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 32)
            }
            .padding(.horizontal, 4)

            ResponseSectionView(
                imageScale: $imageScale,
                errorItem: $errorItem,
                showUndoButton: $showUndoButton,
                undoManager: undoManager,
                onPopOut: onPopOut
            )
            .padding(.top, 8)
        }
    }

    private var copiedToast: some View {
        Group {
            if showCopiedMessage {
                LiquidGlassToast(message: "Copied to Clipboard")
                    .transition(.toastTransition)
                    .zIndex(1)
            }
        }
    }

    private var openingEditorToast: some View {
        Group {
            #if os(macOS)
            if showOpeningEditorToast {
                LiquidGlassToast(message: "Opening Text Editor…")
                    .transition(.toastTransition)
                    .zIndex(1)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation {
                                showOpeningEditorToast = false
                            }
                        }
                    }
                    .accessibilityLabel("Opening Text Editor")
            }
            #endif
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                mainSections
                    .animation(DS.Anim.springGentle, value: appState.settings.provider)  // Liquid mode switch feel
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            #endif
            .background(glassBackground)  // Deep liquid glass across the entire scrollable area
            .clipShape(RoundedRectangle(cornerRadius: isCompact ? 0 : 24, style: .continuous))  // Soft edges on wider layouts
            copiedToast
            openingEditorToast
        }
        .onAppear {
            localProvider = appState.settings.provider
            if !appState.batchPrompts.isEmpty {
                batchStartIndex = 1
                batchEndIndex = appState.batchPrompts.count
            }
        }
        .onChange(of: localProvider) { newMode in
            Task {
                appState.settings.provider = newMode
            }
        }
        .onChange(of: appState.settings.provider) { newMode in
            // Sync from external changes (e.g., menu commands)
            if localProvider != newMode {
                localProvider = newMode
            }
        }
        .onChange(of: appState.batchPrompts) { newPrompts in
            let count = newPrompts.count
            batchStartIndex = 1
            batchEndIndex = count
        }
    }

    private func pasteToPrompt() {
        if let textView = promptTextView {
            textView.paste()
        } else {
            var pastedText: String? = nil
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            pastedText = pasteboard.string(forType: .string)
            #elseif os(iOS)
            pastedText = UIPasteboard.general.string
            #endif
            if let text = pastedText {
                let oldPrompt = prompt
                prompt = text
                undoManager?.registerUndo(withTarget: appState, selector: #selector(AppState.setPrompt(_:)), object: oldPrompt)
            }
        }
    }

    private func copyPromptToClipboard() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = prompt
        #endif
        withAnimation {
            showCopiedMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedMessage = false
            }
        }
    }

    private func clearPrompt() {
        if let textView = promptTextView {
            let oldPrompt = prompt
            textView.clear()
            undoManager?.registerUndo(withTarget: appState, selector: #selector(AppState.setPrompt(_:)), object: oldPrompt)
        } else if !prompt.isEmpty {
            let oldPrompt = prompt
            prompt = ""
            undoManager?.registerUndo(withTarget: appState, selector: #selector(AppState.setPrompt(_:)), object: oldPrompt)
        }
    }

    init(
        prompt: Binding<String>,
        showApiKey: Binding<Bool>,
        isTestingApi: Binding<Bool>,
        errorItem: Binding<AlertError?>,
        imageScale: Binding<CGFloat>,
        promptTextView: Binding<(any PlatformTextView)?>,
        isLoading: Bool,
        progress: Double,
        progressStep: Int,
        progressMax: Int,
        currentNodeName: String?,
        isCancelled: Binding<Bool>,
        aimlBalance: Binding<Double?>,
        balanceFetchTask: Binding<Task<Void, Never>?>,
        onSubmit: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onPopOut: @escaping () -> Void,
        onAnnotate: @escaping (UUID) -> Void,
        onDescribeImage: @escaping (UIState.ImageSlot) -> Void,
        onComfyJSONSelected: @escaping (Result<[URL], Error>) -> Void,
        onBatchFileSelected: @escaping (Result<[URL], Error>) -> Void,
        onBatchSubmit: @escaping () -> Void,
        onEditBatchFile: @escaping () -> Void,
        onClearBatchFile: @escaping () -> Void,
        onReloadBatchFile: @escaping () -> Void,
        batchFilePath: Binding<String>,
        batchStartIndex: Binding<Int>,
        batchEndIndex: Binding<Int>
    ) {
        self._prompt = prompt
        self._showApiKey = showApiKey
        self._isTestingApi = isTestingApi
        self._errorItem = errorItem
        self._imageScale = imageScale
        self._promptTextView = promptTextView
        self.isLoading = isLoading
        self.progress = progress
        self.progressStep = progressStep
        self.progressMax = progressMax
        self.currentNodeName = currentNodeName
        self._isCancelled = isCancelled
        self.onSubmit = onSubmit
        self.onStop = onStop
        self.onPopOut = onPopOut
        self.onAnnotate = onAnnotate
        self.onDescribeImage = onDescribeImage
        self.onComfyJSONSelected = onComfyJSONSelected
        self.onBatchFileSelected = onBatchFileSelected
        self.onBatchSubmit = onBatchSubmit
        self.onEditBatchFile = onEditBatchFile
        self.onClearBatchFile = onClearBatchFile
        self.onReloadBatchFile = onReloadBatchFile
        self._batchFilePath = batchFilePath
        self._batchStartIndex = batchStartIndex
        self._batchEndIndex = batchEndIndex
        self._aimlBalance = aimlBalance
        self._balanceFetchTask = balanceFetchTask
    }
}

private struct LiquidGlassSection<Content: View, Trailing: View>: View {
    let icon: String
    let title: String
    private let trailing: Trailing
    private let content: Content
    @EnvironmentObject var appState: AppState
    
    private var modeAccent: Color {
        appState.settings.provider.liquidAccent
    }
    
    init(
        icon: String,
        title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(modeAccent)  // Title in mode color
                } icon: {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(modeAccent)
                        .frame(width: 32)
                }
                .padding(.horizontal, 4)
                
                Spacer()
                
                if !(trailing is EmptyView) {
                    trailing
                }
            }
            
            content
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        Color.clear.background(.ultraThickMaterial)
                        modeAccent.opacity(0.08)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(modeAccent.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: modeAccent.opacity(0.25), radius: 16, y: 8)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Sub-Views

private struct ModePickerView: View {
    @Binding var localProvider: Provider

    var body: some View {
        Picker("Mode", selection: $localProvider) {
            Label("Gemini", systemImage: "sparkles").tag(Provider.gemini)
            Label("ComfyUI", systemImage: "cpu").tag(Provider.comfyUI)
            Label("Grok", systemImage: "brain.head.profile").tag(Provider.grok)
            Label("AIMLAPI", systemImage: "network").tag(Provider.aimlapi)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

private struct ConfigurationSectionView: View {
    @Binding var showApiKey: Bool
    @Binding var isTestingApi: Bool
    @Binding var errorItem: AlertError?
    @Binding var aimlBalance: Double?
    @Binding var balanceFetchTask: Task<Void, Never>?
    let onComfyJSONSelected: (Result<[URL], Error>) -> Void
    @EnvironmentObject var appState: AppState

    var body: some View {
        ConfigurationSection(
            showApiKey: $showApiKey,
            isTestingApi: $isTestingApi,
            params: $appState.settings.aimlAdvancedParams,
            errorItem: $errorItem,
            aimlBalance: $aimlBalance,
            balanceFetchTask: $balanceFetchTask,
            onComfyJSONSelected: onComfyJSONSelected
        )
    }
}

private struct InputImagesSectionView: View {
    @Binding var errorItem: AlertError?
    let onAnnotate: (UUID) -> Void
    let onDescribeImage: (UIState.ImageSlot) -> Void

    var body: some View {
        InputImagesSection(
            errorItem: $errorItem,
            onAnnotate: onAnnotate,
            onDescribeImage: onDescribeImage
        )
    }
}

private struct BatchModeSectionView: View {
    @Binding var batchFilePath: String
    @Binding var batchStartIndex: Int
    @Binding var batchEndIndex: Int
    @Binding var showOpeningEditorToast: Bool

    let isLoading: Bool
    let isBatchSubmitDisabled: Bool

    let onBatchFileSelected: (Result<[URL], Error>) -> Void
    let onEditBatchFile: () -> Void
    let onReloadBatchFile: () -> Void
    let onClearBatchFile: () -> Void
    let onBatchSubmit: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var showGenerateSheet: Bool = false

    private var modeAccent: Color {
        appState.settings.provider.liquidAccent
    }

    var body: some View {
        VStack(spacing: 16) {
            // File info display - simple, no nested glass
            if batchFilePath.isEmpty {
                // Empty state
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("Select a .txt file with one prompt per line")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            } else {
                // File loaded state - compact horizontal layout
                VStack(spacing: 14) {
                    // File name and count on one line
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)

                        Text(URL(fileURLWithPath: batchFilePath).lastPathComponent)
                            .font(DS.prominentFont.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if appState.batchPrompts.count > 0 {
                            Text("(\(appState.batchPrompts.count) prompts)")
                                .font(DS.bodyFont)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    // Range pickers and submit button on one line
                    if !appState.batchPrompts.isEmpty {
                        HStack(spacing: 12) {
                            // Start picker
                            HStack(spacing: 6) {
                                Text("Start")
                                    .font(DS.bodyFont.weight(.medium))
                                    .foregroundColor(.secondary)
                                unifiedBatchPicker(binding: $batchStartIndex)
                            }

                            Text("—")
                                .foregroundColor(.secondary)

                            // End picker
                            HStack(spacing: 6) {
                                Text("End")
                                    .font(DS.bodyFont.weight(.medium))
                                    .foregroundColor(.secondary)
                                unifiedBatchPicker(binding: $batchEndIndex)
                            }

                            Spacer()

                            // Submit button - compact
                            Button {
                                onBatchSubmit()
                            } label: {
                                Label("Run Batch", systemImage: "play.fill")
                                    .font(DS.prominentFont.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(isBatchSubmitDisabled || isLoading ? .gray : modeAccent)
                            .controlSize(.regular)
                            .disabled(isBatchSubmitDisabled || isLoading)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Floating action pill - consistent with other sections
            HStack(spacing: 16) {
                // Generate with AI button
                Button {
                    showGenerateSheet = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.purple)
                }
                .buttonStyle(.plain)
                .help("Generate batch prompts with AI")
                .accessibilityLabel("Generate batch prompts with AI")

                Button {
                    PlatformFilePicker.presentOpenPanel(
                        allowedTypes: [.plainText],
                        allowsMultiple: false,
                        canChooseDirectories: false,
                        callback: onBatchFileSelected
                    )
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Choose batch file")
                .accessibilityLabel("Choose batch file")

                Button {
                    #if os(macOS)
                    withAnimation { showOpeningEditorToast = true }
                    #endif
                    onEditBatchFile()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Edit batch file")
                .accessibilityLabel("Edit batch file")

                Button(action: onReloadBatchFile) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(batchFilePath.isEmpty ? .secondary : .blue)
                }
                .buttonStyle(.plain)
                .disabled(batchFilePath.isEmpty)
                .opacity(batchFilePath.isEmpty ? 0.4 : 1.0)
                .help("Reload prompts")
                .accessibilityLabel("Reload prompts")

                Button(action: onClearBatchFile) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .disabled(batchFilePath.isEmpty)
                .opacity(batchFilePath.isEmpty ? 0.4 : 1.0)
                .help("Clear batch file")
                .accessibilityLabel("Clear batch file")
            }
            .padding(16)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.1), radius: 8)
            .padding(.trailing, 20)
            .offset(y: 70)
        }
        .padding(.bottom, 66)
        .sheet(isPresented: $showGenerateSheet) {
            BatchGeneratorView(existingPromptCount: appState.batchPrompts.count) { prompts, mode in
                insertGeneratedPrompts(prompts, mode: mode)
            }
            .environmentObject(appState)
        }
        .onChange(of: appState.batchPrompts) { newPrompts in
            guard !newPrompts.isEmpty else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                batchStartIndex = 1
                batchEndIndex = newPrompts.count
            }
        }
    }

    private func insertGeneratedPrompts(_ prompts: [String], mode: BatchInsertMode) {
        switch mode {
        case .append:
            appState.batchPrompts.append(contentsOf: prompts)
        case .prepend:
            appState.batchPrompts.insert(contentsOf: prompts, at: 0)
        case .replace:
            appState.batchPrompts = prompts
        }
        // Update indices to reflect new prompts
        batchStartIndex = 1
        batchEndIndex = appState.batchPrompts.count

        // Keep new-file flag in sync so the editor loads the generated prompts, not the stale empty array
        if appState.ui.batchNewFilePrompts != nil {
            appState.ui.batchNewFilePrompts = appState.batchPrompts
        }

        // If no batch file is open, open the batch editor so user can see/save the prompts
        if batchFilePath.isEmpty {
            onEditBatchFile()
        }
    }

    @ViewBuilder
    private func unifiedBatchPicker(binding: Binding<Int>) -> some View {
        let range = 1...max(1, appState.batchPrompts.count)

        #if os(macOS)
        Picker("", selection: binding) {
            ForEach(range, id: \.self) { num in
                Text("\(num)").tag(num)
            }
        }
        .labelsHidden()
        #else
        Picker("", selection: binding) {
            ForEach(range, id: \.self) { num in
                Text("\(num)").tag(num)
            }
        }
        .pickerStyle(.wheel)
        .frame(width: 70, height: 100)
        .clipped()
        .labelsHidden()
        #endif
    }
}

private struct ResponseSectionView: View {
    @Binding var imageScale: CGFloat
    @Binding var errorItem: AlertError?
    @Binding var showUndoButton: Bool
    let undoManager: UndoManager?
    let onPopOut: () -> Void

    var body: some View {
        ResponseSection(
            imageScale: $imageScale,
            errorItem: $errorItem,
            showUndoButton: $showUndoButton,
            onPopOut: onPopOut
        )
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
