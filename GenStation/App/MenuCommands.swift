// MenuCommands.swift
// Comprehensive macOS menu bar implementation

import SwiftUI
#if os(macOS)
import AppKit
import GenStationCore

// MARK: - App Menu Commands

struct AppMenuCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About GenStation") {
                showAboutPanel()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                NotificationCenter.default.post(name: openGeneralSettingsNotification, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private func showAboutPanel() {
        let creditsText = """
        GenStation is a client for AI image generation.

        • No built-in image generation
        • Connects to Gemini, Grok, AIMLAPI, and ComfyUI
        • You bring your own API keys
        • We collect zero personal data

        Thank you for using GenStation.

        Image upscaling: Real-ESRGAN (BSD 3-Clause)
        Core ML model: john-rocky/CoreML-Models (MIT)
        """

        let urlString = "https://genstation.art"
        guard let url = URL(string: urlString) else { return }

        let attributedCredits = NSMutableAttributedString(string: creditsText + "\n" + urlString)

        let fullRange = NSRange(location: 0, length: attributedCredits.length)
        attributedCredits.addAttributes([
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ], range: fullRange)

        let linkRange = NSRange(location: attributedCredits.length - urlString.count, length: urlString.count)
        attributedCredits.addAttribute(.link, value: url, range: linkRange)
        attributedCredits.addAttribute(.foregroundColor, value: NSColor.linkColor, range: linkRange)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        attributedCredits.addAttribute(.paragraphStyle, value: paragraphStyle, range: linkRange)

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "GenStation",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            .version: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1",
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2025–2026 William Rockey\nReleased under the MIT License.",
            .credits: attributedCredits
        ]

        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}

// MARK: - File Menu Commands

struct FileMenuCommands: Commands {
    @ObservedObject var appState: AppState
    @Binding var showClearHistoryConfirmation: Bool

    /// True if user is in batch prompt mode OR batch editor is visible
    private var isBatchContext: Bool {
        appState.ui.promptMode == .batch || appState.ui.isBatchEditorVisible
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Prompt") {
                appState.prompt = ""
                appState.ui.imageSlots.removeAll()
                appState.settings.aimlAdvancedParams = ModelParameters()
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("Open Workflow...") {
                openWorkflowFile()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(appState.settings.provider != .comfyUI)

            Button("Open Batch File...") {
                openBatchFile()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Save Batch File") {
                NotificationCenter.default.post(name: Notification.Name("SaveBatchFile"), object: nil)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!isBatchContext || appState.batchPrompts.isEmpty)

            Button("Save Batch File As...") {
                NotificationCenter.default.post(name: Notification.Name("SaveBatchFileAs"), object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!isBatchContext || appState.batchPrompts.isEmpty)

            Divider()

            Button("Import History Package...") {
                importHistoryPackage()
            }
            .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button("Set Output Folder...") {
                selectOutputFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
        }
    }

    private func openWorkflowFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a ComfyUI workflow JSON or PNG file"

        if panel.runModal() == .OK, let url = panel.url {
            NotificationCenter.default.post(
                name: Notification.Name("OpenComfyWorkflow"),
                object: url
            )
        }
    }

    private func openBatchFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.text, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a batch prompts text file"

        if panel.runModal() == .OK, let url = panel.url {
            NotificationCenter.default.post(
                name: Notification.Name("OpenBatchFile"),
                object: url
            )
        }
    }

    private func importHistoryPackage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "tar.gz") ?? .data,
            .init(filenameExtension: "genstation") ?? .data,
            .zip,
            .gzip
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.message = "Select a GenStation history package"

        if panel.runModal() == .OK, let url = panel.url {
            appState.ui.requestImportPackageURL = url
        }
    }

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select output folder for generated images"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])
                AppStorageContext.defaults.set(bookmarkData, forKey: "outputDirBookmark")
                appState.settings.outputDirectory = url
            } catch {
                Log.debug("Failed to create bookmark: \(error)")
            }
        }
    }
}

// MARK: - View Menu Commands

struct ViewMenuCommands: Commands {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("View") {
            // Power Panel shortcuts
            Section {
                Button("Show Style Browser") {
                    NotificationCenter.default.post(name: Notification.Name("SelectPowerPanel"), object: PowerPanelType.styles)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Show Model Options") {
                    NotificationCenter.default.post(name: Notification.Name("SelectPowerPanel"), object: PowerPanelType.advanced)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Show Batch Editor") {
                    NotificationCenter.default.post(name: Notification.Name("SelectPowerPanel"), object: PowerPanelType.batch)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Show Session Gallery") {
                    NotificationCenter.default.post(name: Notification.Name("SelectPowerPanel"), object: PowerPanelType.response)
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Show History") {
                    NotificationCenter.default.post(name: Notification.Name("SelectPowerPanel"), object: PowerPanelType.history)
                }
                .keyboardShortcut("5", modifiers: .command)
            }

            Divider()

            Button("Show/Hide Detail Pane") {
                NotificationCenter.default.post(name: Notification.Name("ToggleDetailPane"), object: nil)
            }
            .keyboardShortcut("d", modifiers: .command)

            Divider()

            Button("Pop Out Session Gallery") {
                openWindow(id: "response-window")
            }
            .keyboardShortcut("g", modifiers: [.command, .option])

            Button("Pop Out History") {
                openWindow(id: "history-panel-window")
            }
            .keyboardShortcut("h", modifiers: [.command, .option])
        }

        // Jobs panel is also reachable from the Window menu (always, even when idle)
        CommandGroup(after: .windowList) {
            Divider()
            Button("Jobs") {
                appState.presentedModal = .jobs
            }
            .keyboardShortcut("j", modifiers: [.command, .option])
        }
    }
}

// MARK: - Generation Menu Commands

struct GenerationMenuCommands: Commands {
    @ObservedObject var appState: AppState
    @Binding var isGenerating: Bool

    var body: some Commands {
        CommandMenu("Generation") {
            Button("Generate") {
                NotificationCenter.default.post(name: Notification.Name("SubmitGeneration"), object: nil)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isGenerating || appState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Stop Generation") {
                NotificationCenter.default.post(name: Notification.Name("StopGeneration"), object: nil)
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!isGenerating)

            Divider()

            // Mode submenu
            Menu("Mode") {
                ForEach(Provider.allCases, id: \.self) { mode in
                    Button {
                        appState.settings.provider = mode
                    } label: {
                        HStack {
                            Text(mode.rawValue.capitalized)
                            if appState.settings.provider == mode {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(Provider.allCases.firstIndex(of: mode)! + 1))), modifiers: .control)
                }
            }

            Divider()

            Button("Enhance Prompt...") {
                NotificationCenter.default.post(name: Notification.Name("EnhancePrompt"), object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Video Prompt Helper...") {
                NotificationCenter.default.post(name: Notification.Name("OpenVideoHelper"), object: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
            .disabled(appState.settings.provider != .aimlapi || !appState.settings.isVideoMode)

            Divider()

            Button("Batch Generate") {
                NotificationCenter.default.post(name: Notification.Name("BatchGenerate"), object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(isGenerating || appState.batchPrompts.isEmpty)

            Divider()

            Button("Test API Connection") {
                NotificationCenter.default.post(name: Notification.Name("TestAPIConnection"), object: nil)
            }
        }
    }
}

// MARK: - History Menu Commands

struct HistoryMenuCommands: Commands {
    @ObservedObject var appState: AppState
    @Binding var showClearHistoryConfirmation: Bool

    var body: some Commands {
        CommandMenu("History") {
            Button("Search History...") {
                NotificationCenter.default.post(name: Notification.Name("SearchHistory"), object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Divider()

            Button("Add Folder") {
                appState.historyState.addFolder(undoManager: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Select All Items") {
                NotificationCenter.default.post(name: Notification.Name("SelectAllHistoryItems"), object: nil)
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
            .disabled(appState.historyState.history.isEmpty)

            Button("Deselect All") {
                appState.historyState.multiSelection.removeAll()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(appState.historyState.multiSelection.isEmpty)

            Divider()

            Button("Delete Selected") {
                NotificationCenter.default.post(name: Notification.Name("DeleteSelectedHistory"), object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(appState.historyState.multiSelection.isEmpty)

            Divider()

            Button("Clear All History...") {
                showClearHistoryConfirmation = true
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(appState.historyState.history.isEmpty)
        }
    }
}

// MARK: - Help Menu Commands

struct HelpMenuCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("GenStation Help") {
                appState.presentedModal = .help(appState.settings.provider)
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button("Welcome Guide") {
                appState.presentedModal = .onboarding
            }

            Button("API Setup Wizard") {
                appState.presentedModal = .apiKeySetup
            }

            Divider()

            Button("Legal Notice & Terms") {
                appState.presentedModal = .mandatory
            }

            Divider()

            Button("GenStation Website") {
                if let url = URL(string: "https://genstation.art") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Combined Menu Commands

struct GenStationMenuCommands: Commands {
    @ObservedObject var appState: AppState
    @Binding var showClearHistoryConfirmation: Bool
    @Binding var isGenerating: Bool

    var body: some Commands {
        AppMenuCommands(appState: appState)
        FileMenuCommands(appState: appState, showClearHistoryConfirmation: $showClearHistoryConfirmation)
        ViewMenuCommands(appState: appState)
        GenerationMenuCommands(appState: appState, isGenerating: $isGenerating)
        HistoryMenuCommands(appState: appState, showClearHistoryConfirmation: $showClearHistoryConfirmation)
        HelpMenuCommands(appState: appState)
    }
}

// MARK: - Menu Command Handlers ViewModifier

// MARK: - Menu Command Handlers View

/// A view that listens for menu command notifications and triggers appropriate actions.
/// Use as a background to attach menu command handlers to a view hierarchy.
struct MenuCommandHandlersView: View {
    @ObservedObject var appState: AppState
    @Binding var selectedPowerPanel: PowerPanelType
    @Binding var detailVisible: Bool
    var isLoading: Bool
    var onSubmit: () -> Void
    var onStop: () -> Void
    var onBatch: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SearchHistory"))) { _ in
                withAnimation(DS.Anim.standard) {
                    selectedPowerPanel = .history
                    detailVisible = true
                }
                appState.ui.requestFocusHistorySearch = true
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SelectPowerPanel"))) { notification in
                if let panel = notification.object as? PowerPanelType {
                    withAnimation(DS.Anim.standard) {
                        selectedPowerPanel = panel
                        detailVisible = true
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleDetailPane"))) { _ in
                withAnimation(DS.Anim.standard) {
                    detailVisible.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SubmitGeneration"))) { _ in
                onSubmit()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StopGeneration"))) { _ in
                onStop()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("EnhancePrompt"))) { _ in
                appState.ui.requestOpenEnhancePrompt = true
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenVideoHelper"))) { _ in
                appState.ui.requestOpenVideoHelper = true
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BatchGenerate"))) { _ in
                onBatch()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TestAPIConnection"))) { _ in
                testAPIConnection()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenBatchFile"))) { notification in
                if let url = notification.object as? URL {
                    handleOpenBatchFile(url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenComfyWorkflow"))) { notification in
                if let url = notification.object as? URL {
                    handleOpenWorkflow(url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SelectAllHistoryItems"))) { _ in
                let allItemIds = appState.historyState.history.flatMap { entry -> [UUID] in
                    switch entry {
                    case .item(let item): return [item.id]
                    case .folder(let folder): return folder.children.compactMap { child in
                        if case .item(let item) = child { return item.id }
                        return nil
                    }
                    }
                }
                appState.historyState.multiSelection = Set(allItemIds)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DeleteSelectedHistory"))) { _ in
                handleDeleteSelected()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SaveBatchFile"))) { _ in
                handleSaveBatchFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SaveBatchFileAs"))) { _ in
                handleSaveBatchFileAs()
            }
            .onChange(of: isLoading) { newValue in
                NotificationCenter.default.post(
                    name: Notification.Name("GenerationStateChanged"),
                    object: newValue
                )
            }
    }

    private func handleDeleteSelected() {
        guard !appState.historyState.multiSelection.isEmpty else { return }
        let entries = appState.historyState.findEntries(with: appState.historyState.multiSelection)
        let itemCount = entries.flatMap { $0.allItems }.count
        let hasFiles = entries.flatMap { $0.allItems }.contains { $0.fileExists(appState: appState) }

        appState.presentedModal = .deleteConfirmation(DeleteConfirmationInfo(
            title: itemCount == 1 ? "Delete Item" : "Delete \(itemCount) Items",
            message: "This will remove the selected items from history.",
            hasDeletableFiles: hasFiles,
            onConfirm: { deleteFiles in
                appState.historyState.deleteEntries(
                    entries,
                    deleteFiles: deleteFiles,
                    undoManager: nil
                )
                appState.historyState.multiSelection.removeAll()
            }
        ))
    }

    private func handleOpenBatchFile(_ url: URL) {
        do {
            // Create security-scoped bookmark
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])
            AppStorageContext.defaults.set(bookmarkData, forKey: "batchFileBookmark")

            // Read the file content
            let content = try String(contentsOf: url, encoding: .utf8)
            let prompts = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // Update app state
            appState.batchPrompts = prompts
            appState.batchFileURL = url
            appState.batchFilePath = url.path
            appState.batchFileVersion += 1

            // Switch to batch mode in the prompt section
            appState.ui.promptMode = .batch

            Log.debug("Opened batch file via menu: \(url.path) with \(prompts.count) prompts")
        } catch {
            Log.debug("Failed to open batch file: \(error)")
        }
    }

    private func handleOpenWorkflow(_ url: URL) {
        appState.settings.provider = .comfyUI

        // Parse the file into a workflow dict (JSON file or PNG metadata)
        var json: [String: Any]?
        switch url.pathExtension.lowercased() {
        case "json":
            do {
                let data = try Data(contentsOf: url)
                json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            } catch {
                Log.debug("Failed to load workflow JSON: \(error)")
                appState.generation.workflowError = "Failed to load workflow: \(error.localizedDescription)"
                return
            }
        case "png":
            if let workflowStr = appState.generation.extractWorkflowFromPNG(url: url),
               let data = workflowStr.data(using: .utf8) {
                json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            if json == nil {
                Log.debug("Menu: No embedded ComfyUI workflow found in PNG")
                appState.generation.workflowError = "No embedded ComfyUI workflow found in the PNG."
                return
            }
        default:
            return
        }
        guard let json = json else {
            appState.generation.workflowError = "Invalid workflow."
            return
        }

        // Same preparation path as the file picker: UI format is converted to API format
        // (auto-fetching object_info when needed) instead of being stored raw. The menu
        // callback is synchronous, so the async prepare runs in a Task.
        let serverURL = appState.settings.comfyServerURL
        appState.generation.workflowImportToken += 1
        let importToken = appState.generation.workflowImportToken
        Task { @MainActor in
            do {
                let prepared = try await ComfyUIFormatConverter.prepareWorkflowFetchingObjectInfoIfNeeded(
                    json: json, serverURL: serverURL
                )
                // Latest-wins: a newer import (or one still fetching object_info) bumps the
                // token, so a slow fetch that finished late must not clobber the newer load.
                guard importToken == appState.generation.workflowImportToken else {
                    Log.debug("Menu: workflow import superseded by a newer one; discarding result")
                    return
                }
                if prepared.wasConverted {
                    Log.debug("Menu: Converted UI workflow to API format (\(prepared.workflow.count) nodes)")
                }
                appState.generation.comfyWorkflow = prepared.workflow
                appState.generation.savedWorkflowID = nil
                appState.settings.comfyJSONURL = url
                appState.settings.comfyJSONPath = url.path
                appState.generation.processWorkflowForNodes(json: prepared.workflow)
                if prepared.wasConverted {
                    appState.generation.showNonAPIFormatWarning = true
                }
            } catch let prepError as ComfyUIFormatConverter.WorkflowPreparationError {
                guard importToken == appState.generation.workflowImportToken else { return }
                Log.debug("Menu: workflow preparation failed: \(prepError)")
                var message = prepError.errorDescription ?? "Failed to load workflow"
                if let remediation = prepError.remediation {
                    message += "\n\n\(remediation)"
                }
                appState.generation.workflowError = message
            } catch {
                guard importToken == appState.generation.workflowImportToken else { return }
                Log.debug("Menu: workflow preparation failed: \(error)")
                appState.generation.workflowError = "Failed to load workflow: \(error.localizedDescription)"
            }
        }
    }

    private func handleSaveBatchFile() {
        guard !appState.batchPrompts.isEmpty else { return }

        let textToSave = appState.batchPrompts.joined(separator: "\n")

        if let existingURL = appState.batchFileURL {
            // Save to existing file
            saveBatchToURL(existingURL, content: textToSave)
        } else {
            // No file yet - show Save As dialog
            handleSaveBatchFileAs()
        }
    }

    private func handleSaveBatchFileAs() {
        guard !appState.batchPrompts.isEmpty else { return }

        let textToSave = appState.batchPrompts.joined(separator: "\n")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "batch.txt"
        panel.title = "Save Batch File"

        if panel.runModal() == .OK, let url = panel.url {
            saveBatchToURL(url, content: textToSave)

            // Update app state with new file location
            appState.batchFileURL = url
            appState.batchFilePath = url.path

            // Create bookmark for future access
            if let bookmark = try? url.bookmarkData(options: [.withSecurityScope]) {
                AppStorageContext.defaults.set(bookmark, forKey: "batchFileBookmark")
            }
        }
    }

    private func saveBatchToURL(_ url: URL, content: String) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            appState.batchFileVersion += 1
            Log.debug("Saved batch file to: \(url.path)")
        } catch {
            Log.debug("Failed to save batch file: \(error)")
        }
    }

    // MARK: - Test API Connection

    private func testAPIConnection() {
        let mode = appState.settings.provider

        Task {
            do {
                switch mode {
                case .gemini:
                    let key = appState.settings.apiKey
                    guard !key.isEmpty else {
                        await showTestResult(success: false, message: "No Gemini API key configured.")
                        return
                    }
                    try await KeyValidation.check(provider: .gemini, key: key)
                    guard key == appState.settings.apiKey, mode == appState.settings.provider else { return }
                    await showTestResult(success: true, message: "Connection authenticated. Model access and sufficient credits are not guaranteed.")

                case .grok:
                    let key = appState.settings.grokApiKey
                    guard !key.isEmpty else {
                        await showTestResult(success: false, message: "No Grok API key configured.")
                        return
                    }
                    try await KeyValidation.check(provider: .grok, key: key)
                    guard key == appState.settings.grokApiKey, mode == appState.settings.provider else { return }
                    await showTestResult(success: true, message: "Connection authenticated. Model access and sufficient credits are not guaranteed.")

                case .aimlapi:
                    let key = appState.settings.aimlapiKey
                    guard !key.isEmpty else {
                        await showTestResult(success: false, message: "No AI/ML API key configured.")
                        return
                    }
                    try await KeyValidation.check(provider: .aimlapi, key: key)
                    guard key == appState.settings.aimlapiKey else { return }
                    await showTestResult(success: true, message: "Connection authenticated. Model access and sufficient credits are not guaranteed.")

                case .comfyUI:
                    let rawServerURL = appState.settings.comfyServerURL
                    guard !rawServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        await showTestResult(success: false, message: "No ComfyUI server URL configured.")
                        return
                    }
                    let baseURL = ComfyUIEndpoints.normalizedServerURL(rawServerURL)
                    guard let url = ComfyUIEndpoints.objectInfoURL(serverURL: rawServerURL) else {
                        await showTestResult(success: false, message: "Invalid ComfyUI server URL.")
                        return
                    }
                    let (data, response) = try await URLSession.shared.data(from: url)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        if let objectInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            ComfyUIFormatConverter.cacheObjectInfo(objectInfo, serverURL: baseURL)
                            await MainActor.run {
                                appState.generation.comfyServerStatus = .connected(nodeCount: objectInfo.count)
                            }
                            await showTestResult(success: true, message: "ComfyUI server is available (\(objectInfo.count) nodes).")
                        } else {
                            await showTestResult(success: true, message: "ComfyUI server is available.")
                        }
                    } else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        await showTestResult(success: false, message: "ComfyUI server returned status \(status).")
                    }
                }
            } catch {
                await showTestResult(success: false, message: "Connection failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func showTestResult(success: Bool, message: String) {
        let alert = NSAlert()
        alert.messageText = success ? "Connection Successful" : "Connection Failed"
        alert.informativeText = message
        alert.alertStyle = success ? .informational : .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension View {
    func menuCommandHandlers(
        appState: AppState,
        selectedPowerPanel: Binding<PowerPanelType>,
        detailVisible: Binding<Bool>,
        isLoading: Bool,
        onSubmit: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onBatch: @escaping () -> Void
    ) -> some View {
        self.background(
            MenuCommandHandlersView(
                appState: appState,
                selectedPowerPanel: selectedPowerPanel,
                detailVisible: detailVisible,
                isLoading: isLoading,
                onSubmit: onSubmit,
                onStop: onStop,
                onBatch: onBatch
            )
        )
    }
}
#endif
