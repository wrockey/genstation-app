// BatchGeneratorView.swift
// Sheet for generating batch prompts using LLM

import SwiftUI

enum BatchInsertMode: String, CaseIterable {
    case append = "Append"
    case prepend = "Prepend"
    case replace = "Replace"
}

struct BatchGeneratorView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var enhancer = PromptEnhancer.shared
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    let existingPromptCount: Int
    let onInsert: ([String], BatchInsertMode) -> Void

    @FocusState private var isDescriptionFocused: Bool
    @State private var description: String = ""
    @State private var promptCount: Int = 10
    @State private var generatedPrompts: [String] = []
    @State private var isGenerating: Bool = false
    @State private var isEditing: Bool = false
    @State private var editableText: String = ""
    @State private var errorMessage: String? = nil
    @State private var selectedModel: EnhancementModel = PromptEnhancer.shared.lastModel
    @State private var insertMode: BatchInsertMode = .append
    @State private var showReplaceConfirm: Bool = false
    @State private var showingKeyRequiredInfo: String? = nil
    @State private var pendingPrivacyService: PrivacyService? = nil

    private var isCompact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    private let minCount = 1
    private let maxCount = 50

    var body: some View {
        #if os(iOS)
        NavigationStack {
            mainContent
                .toolbar(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isDescriptionFocused = false
                        }
                    }
                }
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
                    descriptionSection
                    countSection

                    if isGenerating {
                        loadingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if !generatedPrompts.isEmpty {
                        resultsSection
                    }
                }
                .padding(.horizontal, isCompact ? 16 : 24)
                .padding(.vertical, isCompact ? 16 : 20)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif

            Divider()

            // Footer
            footer
        }
        #if os(macOS)
        .frame(minWidth: 450, idealWidth: 550, maxWidth: 650)
        .frame(minHeight: 500, idealHeight: 600, maxHeight: 750)
        #endif
        .background(Color.platformWindowBackground)
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
                        Task { await performGeneration(skipPrivacyCheck: true) }
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
                    Task { await performGeneration(skipPrivacyCheck: true) }
                }
            }
        }
        #endif
        .alert("Replace Existing Prompts?", isPresented: $showReplaceConfirm) {
            Button("Replace", role: .destructive) {
                performInsert()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace \(existingPromptCount) existing prompt\(existingPromptCount == 1 ? "" : "s") with the generated ones.")
        }
        .onAppear {
            selectedModel = PromptEnhancer.shared.lastModel
            restoreDraftIfAvailable()
            promptCountText = "\(promptCount)"
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") {
                clearDraft()
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(maxWidth: .infinity, alignment: .leading)

            Label(isCompact ? "Batch Prompts" : "Generate Batch Prompts", systemImage: "sparkles")
                .font(.headline)
                .lineLimit(1)
                .fixedSize()

            Spacer()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Describe what you want to generate:")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)

            TextEditor(text: $description)
                .focused($isDescriptionFocused)
                .font(.body)
                .padding(8)
                .frame(minHeight: 100, maxHeight: 160)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(DS.Radius.standard)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.standard)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("e.g., famous landmarks at different times of day")
                            .foregroundColor(.secondary.opacity(0.6))
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }

            if !generatedPrompts.isEmpty {
                Button(action: {
                    Task { await performGeneration() }
                }) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(description.isEmpty || isGenerating)
            }
        }
    }

    // MARK: - Count Section

    @State private var promptCountText: String = "10"

    private var countSection: some View {
        HStack(spacing: 12) {
            Text("Number of prompts:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Button(action: { if promptCount > minCount { promptCount -= 1; promptCountText = "\(promptCount)" } }) {
                    Image(systemName: "minus.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(promptCount <= minCount)
                .accessibilityLabel("Decrease prompt count")
                .help("Decrease count")

                TextField("", text: $promptCountText)
                    .font(.body.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                    #if os(macOS)
                    .textFieldStyle(.squareBorder)
                    #else
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    #endif
                    .onChange(of: promptCountText) { newValue in
                        // Filter to digits only
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            promptCountText = filtered
                        }
                        // Update promptCount if valid
                        if let value = Int(filtered) {
                            promptCount = min(max(value, minCount), maxCount)
                        }
                    }
                    .onSubmit {
                        // Clamp and update on submit
                        promptCount = min(max(promptCount, minCount), maxCount)
                        promptCountText = "\(promptCount)"
                    }

                Button(action: { if promptCount < maxCount { promptCount += 1; promptCountText = "\(promptCount)" } }) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(promptCount >= maxCount)
                .accessibilityLabel("Increase prompt count")
                .help("Increase count")
            }
            .foregroundColor(.primary)

            Spacer()

            if generatedPrompts.isEmpty && !isGenerating {
                Button(action: {
                    Task { await performGeneration() }
                }) {
                    Label("Generate", systemImage: "sparkles")
                        .fixedSize()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(description.isEmpty)
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Generating \(promptCount) prompts...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.caption)
                        .foregroundColor(.purple.opacity(0.6))
                        .offset(y: isGenerating ? -3 : 0)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: isGenerating
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Generation failed")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Try Again") {
                    Task { await performGeneration() }
                }
                .buttonStyle(.bordered)

                Button("Dismiss") {
                    errorMessage = nil
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Generated Prompts (\(generatedPrompts.count))")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { isEditing.toggle() }) {
                    Label(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(isEditing ? "Finish editing" : "Edit generated prompts")
                .help("Edit generated prompts")
            }

            if isEditing {
                TextEditor(text: $editableText)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(minHeight: 150, maxHeight: 300)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(DS.Radius.standard)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.standard)
                            .stroke(Color.purple.opacity(0.5), lineWidth: 1)
                    )
                    .onChange(of: editableText) { newValue in
                        // Update generatedPrompts when editing finishes
                        generatedPrompts = newValue
                            .components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(generatedPrompts.enumerated()), id: \.offset) { index, prompt in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .trailing)

                                Text(prompt)
                                    .font(.callout)
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 4)

                            if index < generatedPrompts.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(minHeight: 120, maxHeight: 250)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(DS.Radius.standard)
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
                VStack(spacing: 10) {
                    HStack {
                        modelPicker
                        Spacer()
                    }
                    HStack {
                        Spacer()
                        footerActionButtons
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            } else {
                HStack {
                    modelPicker
                    Spacer()
                    footerActionButtons
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
                ForEach(EnhancementModel.allCases) { model in
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

    private var footerActionButtons: some View {
        HStack(spacing: 10) {
            // Insert mode menu + button
            Menu {
                ForEach(BatchInsertMode.allCases, id: \.self) { mode in
                    Button(action: { insertMode = mode }) {
                        HStack {
                            Text(mode.rawValue)
                            if mode == insertMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(insertMode.rawValue)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
            } primaryAction: {
                handleInsert()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(generatedPrompts.isEmpty || isGenerating)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    // MARK: - Draft Management

    private func restoreDraftIfAvailable() {
        if let draft = appState.ui.batchGeneratorDraft {
            description = draft.description
            promptCount = draft.promptCount
            appState.ui.batchGeneratorDraft = nil  // Clear after restoring
        }
    }

    private func clearDraft() {
        appState.ui.batchGeneratorDraft = nil
    }

    // MARK: - Helpers

    private func isModelAvailable(_ model: EnhancementModel) -> Bool {
        model.selectProvider(
            geminiKey: appState.settings.apiKey,
            aimlKey: appState.settings.aimlapiKey,
            grokKey: appState.settings.grokApiKey
        ) != nil
    }

    private func performGeneration(skipPrivacyCheck: Bool = false) async {
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

        isGenerating = true
        errorMessage = nil

        do {
            let results = try await PromptEnhancer.shared.generateBatch(
                description: description,
                count: promptCount,
                model: selectedModel,
                geminiKey: appState.settings.apiKey,
                aimlKey: appState.settings.aimlapiKey,
                grokKey: appState.settings.grokApiKey
            )

            await MainActor.run {
                generatedPrompts = results
                editableText = results.joined(separator: "\n")
                isGenerating = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isGenerating = false
            }
        }
    }

    private func handleInsert() {
        if insertMode == .replace && existingPromptCount > 0 {
            showReplaceConfirm = true
        } else {
            performInsert()
        }
    }

    private func performInsert() {
        clearDraft()
        onInsert(generatedPrompts, insertMode)
        dismiss()
    }
}

// MARK: - Preview

#if DEBUG
struct BatchGeneratorView_Previews: PreviewProvider {
    static var previews: some View {
        BatchGeneratorView(existingPromptCount: 5) { _, _ in }
        .environmentObject(AppState())
    }
}
#endif
