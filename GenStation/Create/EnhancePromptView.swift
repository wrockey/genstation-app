// EnhancePromptView.swift
// Preview sheet for prompt enhancement

import SwiftUI

struct EnhancePromptView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var enhancer = PromptEnhancer.shared
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    let initialModel: EnhancementModel
    let onApply: (String) -> Void
    let onPromptChanged: ((String) -> Void)?

    /// Live styles from appState (user can modify in-sheet)
    private var styles: [PromptStyle] {
        Array(appState.ui.selectedStyles)
    }

    @State private var originalPrompt: String
    @State private var isEditingOriginal: Bool = false
    @State private var enhancedPrompt: String = ""
    @State private var isEditing: Bool = false
    @State private var selectedModel: EnhancementModel
    @State private var showStylesPopover: Bool = false
    @State private var showStyleBrowserSheet: Bool = false
    @State private var pendingPrivacyService: PrivacyService? = nil

    init(originalPrompt: String, styles: [PromptStyle] = [], initialModel: EnhancementModel = PromptEnhancer.shared.lastModel, onApply: @escaping (String) -> Void, onPromptChanged: ((String) -> Void)? = nil) {
        self._originalPrompt = State(initialValue: originalPrompt)
        self.initialModel = initialModel
        self.onApply = onApply
        self.onPromptChanged = onPromptChanged
        self._selectedModel = State(initialValue: initialModel)
    }
    @State private var errorMessage: String? = nil
    @State private var hasEnhanced: Bool = false
    @State private var showingKeyRequiredInfo: String? = nil

    private var isCompact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            mainContent
                .toolbar(.hidden, for: .navigationBar)
                .keyboardDoneButton()
        }
        #else
        mainContent
        #endif
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if enhancer.isEnhancing {
                        loadingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if hasEnhanced {
                        enhancedPromptView
                    } else {
                        initialView
                    }
                }
                .padding(.horizontal, isCompact ? 16 : 24)
                .padding(.vertical, isCompact ? 16 : 20)
            }

            Divider()

            // Footer
            footer
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 760)
        .frame(minHeight: 400, idealHeight: 500, maxHeight: 650)
        #endif
        .background(Color.platformWindowBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(maxWidth: .infinity, alignment: .leading)

            Label("Enhance Prompt", systemImage: "sparkles")
                .font(.headline)
                .lineLimit(1)
                .fixedSize()

            Spacer()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Enhancing your prompt...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Show sparkle animation hint
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.caption)
                        .foregroundColor(.purple.opacity(0.6))
                        .offset(y: enhancer.isEnhancing ? -3 : 0)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: enhancer.isEnhancing
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Couldn't enhance prompt")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Try Again") {
                    Task {
                        await performEnhancement()
                    }
                }
                .buttonStyle(.bordered)

                Button("Use Original") {
                    onApply(originalPrompt)
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var initialView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Original Prompt")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    isEditingOriginal.toggle()
                } label: {
                    Label(isEditingOriginal ? "Done" : "Edit", systemImage: isEditingOriginal ? "checkmark" : "pencil")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isEditingOriginal {
                TextEditor(text: $originalPrompt)
                    .font(.body)
                    .padding(8)
                    .frame(minHeight: 300, maxHeight: 400)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(DS.Radius.standard)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.standard)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
                    .onChange(of: originalPrompt) { newValue in
                        onPromptChanged?(newValue)
                    }
            } else {
                Text(originalPrompt)
                    .font(.body.italic())
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(DS.Radius.standard)
            }

            if !styles.isEmpty {
                Text("Styles to Integrate")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                FlowLayout(spacing: 6) {
                    ForEach(styles, id: \.id) { style in
                        Text(style.name)
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(DS.Radius.panel)
                    }
                }
            }

            Text("Click Enhance to improve your prompt with AI")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    private var enhancedPromptView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Enhanced Prompt")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Show which model was used
                if !enhancedPrompt.isEmpty {
                    Text("via \(selectedModel.displayName)")
                        .font(.subheadline)
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(4)
                }

                Spacer()

                Button {
                    withAnimation(DS.Anim.quick) {
                        enhancedPrompt = ""
                        hasEnhanced = false
                        isEditing = false
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Revert to original prompt")
                .accessibilityLabel("Revert to original prompt")

                Button(action: { isEditing.toggle() }) {
                    Label(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isEditing {
                TextEditor(text: $enhancedPrompt)
                    .font(.body)
                    .padding(8)
                    .frame(minHeight: 150, maxHeight: 350)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(DS.Radius.standard)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.standard)
                            .stroke(Color.purple.opacity(0.5), lineWidth: 1)
                    )
            } else {
                Text(enhancedPrompt)
                    .font(.body)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(DS.Radius.standard)
            }

            // Changes summary
            if !styles.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                    Text("Integrated: \(styles.map { $0.name }.joined(separator: ", "))")
                        .font(.subheadline)
                }
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            // API key info message
            if let keyInfo = showingKeyRequiredInfo {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundColor(.orange)
                    Text(keyInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { showingKeyRequiredInfo = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(DS.Radius.standard)
                .padding(.horizontal, 24)
            }

            if isCompact {
                // iPhone compact: stack vertically
                VStack(spacing: 10) {
                    HStack {
                        modelPicker
                        Spacer()
                        enhanceStylesButton
                    }
                    HStack {
                        Spacer()
                        actionButtons
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            } else {
                // macOS / iPad: two rows for breathing room
                VStack(spacing: 10) {
                    // Row 1: Model and styles
                    HStack {
                        modelPicker
                        enhanceStylesButton
                        Spacer()
                    }

                    // Row 2: Primary action, right-aligned
                    HStack {
                        Spacer()
                        actionButtons
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
        }
    }

    private var modelPicker: some View {
        HStack(spacing: 4) {
            Text("Model:")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize()
            Picker("", selection: $selectedModel) {
                ForEach(availableModels) { model in
                    Text(model.displayName)
                        .tag(model)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .onChange(of: selectedModel) { newModel in
                PromptEnhancer.shared.lastModel = newModel
                if !isModelAvailable(newModel) {
                    showingKeyRequiredInfo = newModel.requiredKeysDescription
                } else {
                    showingKeyRequiredInfo = nil
                }
            }
        }
    }

    private var enhanceStylesButton: some View {
        Button(action: { showStylesPopover = true }) {
            HStack(spacing: 5) {
                Image(systemName: "paintpalette")
                    .font(.footnote)
                if styles.isEmpty {
                    Text("Styles")
                        .font(.footnote.weight(.medium))
                } else {
                    Text("\(styles.count) style\(styles.count == 1 ? "" : "s")")
                        .font(.footnote.weight(.medium))
                }
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(DS.Radius.panel)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showStylesPopover, arrowEdge: .top) {
            enhanceStylesPopover
        }
        #if os(iOS)
        .fullScreenCover(item: $pendingPrivacyService) { service in
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        pendingPrivacyService = nil
                    }
                PrivacyNoticeSheet(service: service) { consented, dontShow in
                    if dontShow {
                        AppStorageContext.defaults.set(true, forKey: service.consentKey)
                    }
                    pendingPrivacyService = nil
                    if consented {
                        Task { await performEnhancement(skipPrivacyCheck: true) }
                    }
                }
            }
            .background(ClearBackgroundView())
        }
        #else
        .sheet(item: $pendingPrivacyService) { service in
            PrivacyNoticeSheet(service: service) { consented, dontShow in
                if dontShow {
                    AppStorageContext.defaults.set(true, forKey: service.consentKey)
                }
                pendingPrivacyService = nil
                if consented {
                    Task { await performEnhancement(skipPrivacyCheck: true) }
                }
            }
        }
        #endif
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

    private var enhanceStylesPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Selected Styles")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            if appState.ui.selectedStyles.isEmpty {
                Text("No styles selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.ui.selectedStyles).sorted(by: { $0.name < $1.name }), id: \.id) { style in
                            HStack {
                                Text(style.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Button(action: {
                                    appState.ui.selectedStyles.remove(style)
                                    if appState.ui.selectedStyles.isEmpty {
                                        showStylesPopover = false
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(style.name)")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            Button(action: {
                showStylesPopover = false
                showStyleBrowserSheet = true
            }) {
                HStack {
                    Image(systemName: "paintpalette")
                    Text("Open Style Browser...")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: { showStylesPopover = false }) {
                Text("Done")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 220, maxWidth: 280)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if hasEnhanced {
                Button {
                    Task { await performEnhancement() }
                } label: {
                    Label("Re-Enhance", systemImage: "sparkles")
                        .fixedSize()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(enhancer.isEnhancing)

                Button {
                    onApply(enhancedPrompt)
                    dismiss()
                } label: {
                    Label("Apply to Prompt", systemImage: "checkmark.circle")
                        .fixedSize()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)
                .disabled(enhancedPrompt.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            } else {
                Button {
                    Task { await performEnhancement() }
                } label: {
                    Label("Enhance", systemImage: "sparkles")
                        .fixedSize()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)
                .disabled(enhancer.isEnhancing)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    // MARK: - Helpers

    private var availableModels: [EnhancementModel] {
        EnhancementModel.allCases
    }

    /// Check if model has required API key(s) configured
    private func isModelAvailable(_ model: EnhancementModel) -> Bool {
        model.selectProvider(
            geminiKey: appState.settings.apiKey,
            aimlKey: appState.settings.aimlapiKey,
            grokKey: appState.settings.grokApiKey
        ) != nil
    }

    private func performEnhancement(skipPrivacyCheck: Bool = false) async {
        // Check privacy consent for the selected provider
        if !skipPrivacyCheck, let provider = selectedModel.selectProvider(
            geminiKey: appState.settings.apiKey,
            aimlKey: appState.settings.aimlapiKey,
            grokKey: appState.settings.grokApiKey
        ), !provider.privacyService.hasConsented {
            await MainActor.run {
                pendingPrivacyService = provider.privacyService
            }
            return
        }

        errorMessage = nil

        do {
            let result = try await enhancer.enhance(
                prompt: originalPrompt,
                styles: styles,
                model: selectedModel,
                geminiKey: appState.settings.apiKey,
                aimlKey: appState.settings.aimlapiKey,
                grokKey: appState.settings.grokApiKey
            )
            await MainActor.run {
                enhancedPrompt = result
                hasEnhanced = true
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Flow Layout for Style Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - Preview

#if DEBUG
struct EnhancePromptView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancePromptView(
            originalPrompt: "a cat sitting on a windowsill",
            styles: [],
            onApply: { _ in }
        )
        .environmentObject(AppState())
    }
}
#endif
