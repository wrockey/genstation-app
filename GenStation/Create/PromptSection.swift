import SwiftUI
import GenStationCore

struct PromptSection: View {
    @Binding var prompt: String
    @Binding var isUnsafe: Bool
    @Binding var platformTextView: (any PlatformTextView)?
    @EnvironmentObject var appState: AppState

    // Batch mode bindings
    @Binding var batchStartIndex: Int
    @Binding var batchEndIndex: Int

    // Batch mode callbacks
    let onBatchFileSelected: (Result<[URL], Error>) -> Void
    let onEditBatchFile: () -> Void
    let onReloadBatchFile: () -> Void
    let onClearBatchFile: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.undoManager) private var undoManager

    @State private var localPrompt: String = ""
    @State private var debounceTimer: Timer?
    @State private var textViewHeight: CGFloat = 140  // Must match minHeight to avoid contradictory constraints
    @State private var showEnhanceSheet: Bool = false
    @State private var showStyleBrowserSheet: Bool = false
    @State private var showGenerateSheet: Bool = false
    @State private var showVideoHelperSheet: Bool = false
    // Model selection now handled inside EnhancePromptView sheet

    #if os(iOS)
    @FocusState private var isPromptFocused: Bool
    #endif

    private var isCompact: Bool {
        sizeClass == .compact
    }

    /// Placeholder follows the active mode — "video" in AIML video mode (finding #8)
    private var promptPlaceholder: String {
        appState.settings.usesVideoQueue
            ? "Enter your prompt for video generation here..."
            : "Enter your prompt for image generation here..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header with mode picker
            HStack {
                Label {
                    Text("Prompt")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                } icon: {
                    Image(systemName: "text.bubble")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 32)
                }

                Spacer()

                // Mode segmented control
                Picker("", selection: $appState.ui.promptMode) {
                    ForEach(UIState.PromptMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
            .padding(.horizontal, 4)

            // Content Area - adapts based on mode
            VStack(spacing: 16) {
                // Text editor - shows single prompt or batch prompts
                Group {
                    if appState.ui.promptMode == .single {
                        // ─────── SINGLE MODE ───────
                        singleModeEditor
                            .accessibilityIdentifier("genstation.prompt")
                    } else {
                        // ─────── BATCH MODE ───────
                        batchModeEditor
                    }
                }
                .animation(DS.Anim.quick, value: appState.ui.promptMode)

                if let source = appState.ui.draftSourcePrompt {
                    DisclosureGroup("Source image prompt") { Text(source).textSelection(.enabled) }
                }
                Button("Use example prompt") {
                    let example = appState.settings.task == .video
                        ? "A slow camera push toward the subject, with gentle natural movement and steady lighting."
                        : "A small ceramic fox on a wooden desk beside a sunlit window, soft shadows, detailed studio photograph."
                    if localPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        debounceTimer?.invalidate()
                        localPrompt = example
                        prompt = example
                    }
                }
                .disabled(!localPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                // Action Bar - Styles indicator and Enhance button
                promptActionBar

                // Safety Warning - functional red color (not mode accent)
                if isUnsafe {
                    Text("Warning: Prompt may contain inappropriate content.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.red.opacity(0.85)))
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.top, 8)
        }
        .sheet(isPresented: $showEnhanceSheet) {
            EnhancePromptView(
                originalPrompt: currentPrompt,
                initialModel: PromptEnhancer.shared.lastModel,
                onApply: { enhancedPrompt in
                    let oldPrompt = prompt
                    localPrompt = enhancedPrompt
                    prompt = enhancedPrompt
                    // Defer undo registration until after the sheet dismisses
                    // so the window's undoManager is back in the responder chain
                    DispatchQueue.main.async {
                        #if os(macOS)
                        let um = NSApp.keyWindow?.undoManager
                        #else
                        let um = undoManager
                        #endif
                        um?.registerUndo(withTarget: appState) { state in
                            state.prompt = oldPrompt
                        }
                        um?.setActionName("Enhance Prompt")
                    }
                },
                onPromptChanged: { newPrompt in
                    localPrompt = newPrompt
                    prompt = newPrompt
                }
            )
            .environmentObject(appState)
        }

        // iOS global appearance reset
        #if os(iOS)
        .onAppear {
            UITextView.appearance().backgroundColor = .clear
            platformTextView = nil
        }
        .onDisappear {
            UITextView.appearance().backgroundColor = nil
        }
        #endif

        // Menu command handlers
        .onChange(of: appState.ui.requestOpenEnhancePrompt) { requested in
            guard requested else { return }
            appState.ui.requestOpenEnhancePrompt = false
            showEnhanceSheet = true
        }
        .onChange(of: appState.ui.requestOpenVideoHelper) { requested in
            guard requested else { return }
            appState.ui.requestOpenVideoHelper = false
            if appState.settings.usesVideoQueue {
                showVideoHelperSheet = true
            }
        }
    }

    // MARK: - Action Bar

    private var promptActionBar: some View {
        HStack(spacing: 12) {
            // Styles first (pick styles → then enhance)
            if appState.ui.selectedStyles.isEmpty {
                addStylesLink
            } else {
                styleChips
            }

            if appState.ui.promptMode == .single {
                // Single mode: Enhance button
                enhanceButton

                // Video Helper button - only show for video models
                if appState.settings.usesVideoQueue {
                    videoHelperButton
                }
            } else {
                // Batch mode: Generate prompts button
                batchGenerateButton
            }

            Spacer()
        }
        .padding(.top, 14)
        .sheet(isPresented: $showStyleBrowserSheet) {
            NavigationStack {
                TabFilterStyleBrowser()
                    .environmentObject(appState)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showStyleBrowserSheet = false }
                        }
                    }
                    .navigationTitle("Style Browser")
                    #if os(macOS)
                    .navigationSubtitle("\(appState.ui.selectedStyles.count) selected")
                    #endif
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 600)
            #endif
        }
    }

    private var batchGenerateButton: some View {
        Button(action: { showGenerateSheet = true }) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                if !isCompact {
                    Text("Generate")
                        .fontWeight(.medium)
                }
            }
            .font(.callout)
            .foregroundColor(.purple)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .fill(Color.purple.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
        .help("Generate batch prompts with AI")
        .accessibilityLabel("Generate batch prompts")
        .sheet(isPresented: $showGenerateSheet) {
            BatchGeneratorView(existingPromptCount: appState.batchPrompts.count) { prompts, mode in
                insertGeneratedPrompts(prompts, mode: mode)
            }
            .environmentObject(appState)
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
        // Update indices
        batchStartIndex = 1
        batchEndIndex = appState.batchPrompts.count

        // Keep new-file flag in sync so the editor loads the generated prompts, not the stale empty array
        if appState.ui.batchNewFilePrompts != nil {
            appState.ui.batchNewFilePrompts = appState.batchPrompts
        }

        // If no batch file is open, open the batch editor so user can see/save the prompts
        if appState.batchFilePath.isEmpty {
            onEditBatchFile()
        }
    }

    private var addStylesLink: some View {
        Button(action: {
            showStyleBrowserSheet = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "paintpalette")
                if !isCompact {
                    Text("Styles")
                        .fontWeight(.medium)
                }
            }
            .font(.callout)
            .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .fill(Color.blue.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .help("Select styles to guide enhancement")
        .accessibilityLabel("Styles")
    }

    private var styleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(appState.ui.selectedStyles).sorted(by: { $0.name < $1.name }), id: \.id) { style in
                    HStack(spacing: 4) {
                        Text(style.name)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)

                        Button(action: {
                            appState.ui.selectedStyles.remove(style)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.footnote)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(style.name)")
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(14)
                }

                // "+" button to open style browser
                Button(action: { showStyleBrowserSheet = true }) {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
                .help("Add or change styles")
                .accessibilityLabel("Add styles")
            }
        }
    }

    private var enhanceButton: some View {
        Button(action: {
            showEnhanceSheet = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                if !isCompact {
                    Text("Enhance")
                        .fontWeight(.medium)
                }
            }
            .font(.callout)
            .foregroundColor(.purple)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .fill(Color.purple.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
        .disabled(currentPrompt.isEmpty)
        .help("Enhance prompt (⌘E)")
        .accessibilityLabel("Enhance prompt")
        .keyboardShortcut("e", modifiers: .command)
    }

    // MARK: - Video Helper Button

    private var videoHelperButton: some View {
        Button(action: { showVideoHelperSheet = true }) {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                if !isCompact {
                    Text("Video Helper")
                        .fontWeight(.medium)
                }
            }
            .font(.callout)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .foregroundColor(.orange)
        .help("Build a video prompt with templates and guidance")
        .accessibilityLabel("Video Helper")
        .sheet(isPresented: $showVideoHelperSheet) {
            VideoPromptHelperView(
                currentModelId: appState.settings.selectedVideoModel,
                onApply: { generatedPrompt in
                    localPrompt = generatedPrompt
                    prompt = generatedPrompt
                }
            )
            .environmentObject(appState)
        }
    }

    // MARK: - Single Mode Editor

    private var singleModeEditor: some View {
        Group {
            #if os(iOS)
            TextEditor(text: $localPrompt)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .lineSpacing(6)
                .disableAutocorrection(false)
                .autocapitalization(.sentences)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(minHeight: 140)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .focused($isPromptFocused)
                .onChange(of: localPrompt) { newValue in
                    debounceTimer?.invalidate()
                    debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                        prompt = newValue
                        isUnsafe = !ContentView.isPromptSafe(newValue).0
                    }
                }
                .onAppear { localPrompt = prompt }
                .onChange(of: prompt) { newExternal in
                    // Only sync external → local when NOT actively editing
                    // Prevents cursor-jump-to-end caused by debounce round-trip
                    if !isPromptFocused && newExternal != localPrompt {
                        localPrompt = newExternal
                    }
                }
                .onChange(of: isPromptFocused) { focused in
                    if !focused {
                        // Final sync when user dismisses keyboard
                        prompt = localPrompt
                        isUnsafe = !ContentView.isPromptSafe(localPrompt).0
                    }
                }
                .onDisappear { prompt = localPrompt }
                .overlay(alignment: .topLeading) {
                    if localPrompt.isEmpty {
                        Text(promptPlaceholder)
                            .foregroundColor(.secondary.opacity(0.6))
                            .font(.system(size: 17, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
            #elseif os(macOS)
            CustomTextEditor(text: $localPrompt, platformTextView: $platformTextView)
                .frame(minHeight: 140, idealHeight: textViewHeight, maxHeight: max(textViewHeight, 600))
                .frame(minWidth: 300)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if localPrompt.isEmpty {
                        Text(promptPlaceholder)
                            .foregroundColor(.secondary.opacity(0.6))
                            .font(.system(size: 17, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: localPrompt) { newValue in
                    // Debounce sync to AppState to avoid re-rendering image thumbnails on every keystroke
                    debounceTimer?.invalidate()
                    debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                        prompt = newValue
                        isUnsafe = !ContentView.isPromptSafe(newValue).0
                    }

                    // Height calculation runs immediately for responsive resizing
                    guard let nsTextView = platformTextView as? NSTextView else { return }
                    nsTextView.layoutManager?.ensureLayout(for: nsTextView.textContainer!)
                    let usedRect = nsTextView.layoutManager?.usedRect(for: nsTextView.textContainer!)
                    let contentHeight = usedRect?.height ?? 0
                    let insetHeight = nsTextView.textContainerInset.height * 2
                    let lineFragmentPadding = (nsTextView.textContainer?.lineFragmentPadding ?? 0) * 2
                    let extraPadding: CGFloat = 32

                    let calculatedHeight = contentHeight + insetHeight + lineFragmentPadding + extraPadding

                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        textViewHeight = max(140, min(calculatedHeight, 600))
                    }
                }
                .onAppear {
                    localPrompt = prompt
                    if let _ = platformTextView as? NSTextView {
                        DispatchQueue.main.async {
                            let temp = self.localPrompt
                            self.localPrompt = ""
                            self.localPrompt = temp
                        }
                    }
                }
                .onChange(of: prompt) { newExternal in
                    // Sync external → local (enhance, use-as-prompt, etc.)
                    if newExternal != localPrompt {
                        localPrompt = newExternal
                    }
                }
                .onDisappear { prompt = localPrompt }
            #endif
        }
    }

    // MARK: - Batch Mode Editor

    private var batchModeEditor: some View {
        VStack(spacing: 12) {
            // Current prompt display - shows the prompt currently being generated
            // Read-only display, synced with the main prompt binding during batch runs
            Text(prompt.isEmpty ? "Current prompt will appear here during batch run..." : prompt)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(prompt.isEmpty ? .secondary.opacity(0.6) : .primary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

            // Batch info and range pickers
            batchInfoBar
        }
    }

    private var batchInfoBar: some View {
        Group {
            if appState.batchPrompts.isEmpty {
                // Empty state
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Load a batch file or generate prompts to get started")
                        .font(DS.bodyFont)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            } else {
                // Batch loaded state - two lines for clarity
                VStack(alignment: .leading, spacing: 8) {
                    // Line 1: File info and prompt count
                    HStack(spacing: 8) {
                        if !appState.batchFilePath.isEmpty {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)

                            Text(URL(fileURLWithPath: appState.batchFilePath).lastPathComponent)
                                .font(DS.bodyFont.weight(.medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Text("\(appState.batchPrompts.count) prompts")
                            .font(DS.bodyFont)
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    // Line 2: Range pickers
                    HStack(spacing: 12) {
                        Text("Range:")
                            .font(DS.bodyFont.weight(.medium))
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            batchPicker(binding: $batchStartIndex)

                            Text("to")
                                .font(DS.bodyFont)
                                .foregroundColor(.secondary)

                            batchPicker(binding: $batchEndIndex)
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func batchPicker(binding: Binding<Int>) -> some View {
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

    // MARK: - Helpers

    private var currentPrompt: String {
        return localPrompt
    }

}
