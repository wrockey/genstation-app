import SwiftUI
import GenStationCore

// Define response structure for /v1/chat/completions
struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

struct GeneralOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showApiKey: Bool = false
    @State private var showGrokApiKey: Bool = false
    @State private var showAIMLApiKey: Bool = false
    @State private var showImgBBApiKey: Bool = false
    @State private var isTestingApi: Bool = false
    @State private var testingService: String? = nil
    @State private var errorItem: AlertError? = nil
    @State private var successMessage: String = ""
    @State private var showSuccessAlert: Bool = false
    @State private var showHostingInfo = false
    @State private var showDetailedError: Bool = false
    @State private var detailedErrorMessage: String? = nil
    @Binding var isPresented: Bool
    
    private var isCompact: Bool {
        sizeClass == .compact
    }
    
    private var labelFont: Font {
        .system(.subheadline, design: .default, weight: .medium)
    }
    
    private var textFont: Font {
        .system(size: isCompact ? 13 : 15, weight: .medium, design: .monospaced)
    }
    
    private var isMacOS: Bool {
#if os(macOS)
        return true
#else
        return false
#endif
    }
    
    @MainActor
    private func showDetailedErrorSheet(message: String) {
        detailedErrorMessage = message
        showDetailedError = true
    }
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            scrollContent
                .toolbar(.hidden, for: .navigationBar)
                .keyboardDoneButton()
        }
        #else
        scrollContent
        #endif
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: isCompact ? 12 : 16) {
                Text("General Options")
                    .font(.headline)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                GroupBox(label: HStack(spacing: 6) {
                    Image(systemName: "key.fill").foregroundColor(.blue)
                    Text("API Keys")
                }.font(.headline)) {
                    VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
                        geminiApiKeyRow
                        grokApiKeyRow
                        aimlApiKeyRow
                        aimlImgBBApiKeyRow

                        Divider()
                            .padding(.vertical, 4)

                        HStack(spacing: 12) {
                            Button(action: {
                                isPresented = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    appState.presentedModal = .apiKeySetup
                                }
                            }) {
                                Label("Setup Wizard", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.bordered)
                            .help("Re-run the API key setup wizard")

                        }
                    }
                    .padding()
                }
                .groupBoxStyle(CardGroupBoxStyle())

                GroupBox(label: HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundColor(.blue)
                    Text("Output Folder")
                }.font(.headline)) {
                    VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                        HStack(spacing: 8) {
                            #if os(iOS)
                            Text(appState.settings.outputPath.isEmpty ? "No folder selected" : URL(fileURLWithPath: appState.settings.outputPath).lastPathComponent)
                                .font(textFont)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            #else
                            Text(appState.settings.outputPath.isEmpty ? "No folder selected" : appState.settings.outputPath)
                                .font(textFont)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            #endif

                            Button(action: {
                                PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                                    if case .success(let urls) = result, let url = urls.first {
                                        appState.settings.outputPath = url.path
                                        appState.settings.outputDirectory = url
                                        // Save bookmark for sandbox access
                                        #if os(macOS)
                                        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                                            AppStorageContext.defaults.set(bookmark, forKey: "outputDirBookmark")
                                        }
                                        #else
                                        // On iOS, start security scope before creating bookmark
                                        let didStart = url.startAccessingSecurityScopedResource()
                                        if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                                            AppStorageContext.defaults.set(bookmark, forKey: "outputDirBookmark")
                                            Log.debug("iOS Bookmark: Created bookmark for \(url.path), didStart=\(didStart)")
                                        }
                                        // Keep security scope active - don't call stopAccessing
                                        #endif
                                    }
                                }
                            }) {
                                Label("Browse", systemImage: "folder")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Folder where generated images will be saved.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(CardGroupBoxStyle())

GroupBox(label: HStack(spacing: 6) {
                    Image(systemName: "eye").foregroundColor(.blue)
                    Text("Display Options")
                }.font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-present generated images", isOn: $appState.settings.autoPresentGeneratedImages)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("When enabled, single image generations will automatically open in a viewer. Batch generations show a notification instead.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)

                        Toggle("Save images as JPEG", isOn: $appState.settings.saveOutputAsJPEG)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Converts PNG output to JPEG to save storage. Prompt is embedded in EXIF metadata and GPS data is stripped.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)

                        Toggle("Video job notifications", isOn: $appState.settings.jobNotificationsEnabled)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Notifies you when a video job finishes, fails, or is about to expire on the provider's servers (~24 hours).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                    }
                    .padding()
                }
                .groupBoxStyle(CardGroupBoxStyle())

                #if os(macOS)
                agentAccessSection
                #endif

                GroupBox(label: HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill").foregroundColor(.blue)
                    Text("Help & Support")
                }.font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: {
                            isPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                appState.presentedModal = .onboarding
                            }
                        }) {
                            Label("Replay Tutorial", systemImage: "play.circle")
                        }
                        .buttonStyle(.bordered)
                        .help("Replay the onboarding tutorial")

                        Text("Re-watch the getting started tutorial to learn about GenStation's features.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                    }
                    .padding()
                }
                .groupBoxStyle(CardGroupBoxStyle())

                GroupBox(label: HStack(spacing: 6) {
                    Image(systemName: "heart.fill").foregroundColor(.pink)
                    Text("Acknowledgments")
                }.font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Style Library")
                            .font(.subheadline.bold())

                        Text("Prompt styles curated from Douleb/SDXL-A1111-Styles and community sources.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Link(destination: URL(string: "https://github.com/Douleb/SDXL-A1111-Styles") ?? URL(string: "https://github.com")!) {
                            Label("View on GitHub", systemImage: "link")
                                .font(.caption)
                        }

                        Text("Licensed under MIT License")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        Text("Image Upscaling")
                            .font(.subheadline.bold())

                        Text("Real-ESRGAN (BSD 3-Clause License)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Core ML model by john-rocky/CoreML-Models (MIT License)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Link(destination: URL(string: "https://github.com/john-rocky/CoreML-Models") ?? URL(string: "https://github.com")!) {
                            Label("View on GitHub", systemImage: "link")
                                .font(.caption)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(CardGroupBoxStyle())

                Button("Done") {
                    isPresented = false
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding()
        }
        .alert("Image hosting", isPresented: $showHostingInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("ImgBB has no read-only key check. The key is used when you explicitly upload an input for a workflow that needs a public URL. This shares the image with the hosting service. No test image was uploaded.")
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK") {}
        } message: {
            Text(successMessage)
        }
        .alert(item: $errorItem) { error in
            Alert(
                title: Text("Error"),
                message: Text(error.message),
                primaryButton: .default(Text("OK")),
                secondaryButton: .default(Text("More Info"), action: {
                    showDetailedErrorSheet(message: error.fullMessage ?? error.message)
                })
            )
        }
        .sheet(isPresented: $showDetailedError) {
            DetailedErrorView(message: detailedErrorMessage ?? "") {
                DispatchQueue.main.async {
                    showDetailedError = false
                    detailedErrorMessage = nil
                }
            }
        }
    }

#if os(macOS)
    // MARK: - Agent Access (MCP server, WS-7)

    private var agentAccessSection: some View {
        GroupBox(label: HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundColor(.purple)
            Text("Agent Access")
        }.font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable agent access (MCP server)", isOn: Binding(
                    get: { appState.settings.mcpServerEnabled },
                    set: { enabled in
                        appState.settings.mcpServerEnabled = enabled
                        if enabled {
                            appState.mcpService.startStored()
                        } else {
                            appState.mcpService.stop()
                        }
                    }
                ))
                .font(.subheadline)
                .fontWeight(.medium)

                Text("Lets agent CLIs (e.g. Claude Code) generate images and video through GenStation via MCP. API keys are sent only to their provider, never to the agent. Image requests use the approval mode you choose below; video and workflows require individual approval.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)

                AgentBudgetControls()
                Text("Local helpers share durable MCP jobs and can view folder names, create/rename folders, and move individually accessible assets. Folder membership never shares other originals. Validate without generating, submit with a stable request ID, then poll and reuse the original asset.")
                    .font(.caption).foregroundColor(.secondary)

                Divider()

                Button {
                    PlatformPasteboard.clearContents()
                    PlatformPasteboard.writeString(mcpSetupCommand)
                    successMessage = "MCP setup command copied to the clipboard. Run it in a terminal to register GenStation with Claude Code."
                    showSuccessAlert = true
                } label: {
                    Label("Copy MCP Setup Command", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(!appState.settings.mcpServerEnabled)

                Text("Copies `\(mcpSetupCommand)` — run it once in a terminal to let Claude Code use GenStation. Other MCP clients can register the same helper binary as a stdio server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }
            .padding()
        }
        .groupBoxStyle(CardGroupBoxStyle())
    }

    /// `claude mcp add` command pointing at the helper bundled inside this app.
    private var mcpSetupCommand: String {
        let helperPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/genstation-mcp").path
        return "claude mcp add genstation -- \"\(helperPath)\""
    }
#endif

    @ViewBuilder
    private var geminiApiKeyRow: some View {
        Group {
            if isCompact {
                LazyVStack(alignment: .leading, spacing: 4) {
                    geminiApiKeyLabel
                    geminiApiKeyInputAndControls
                }
            } else {
                HStack(spacing: isCompact ? 2 : 8) {
                    geminiApiKeyLabel
                    geminiApiKeyInputAndControls
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var geminiApiKeyLabel: some View {
        Text("Gemini API Key:")
            .font(labelFont)
            .foregroundColor(.secondary)
            .help("Enter your Gemini API key here")
            .fixedSize()
    }
    
    private var geminiApiKeyInputAndControls: some View {
        APIKeyField(
            service: "Gemini",
            storedKey: $appState.settings.apiKey,
            showKey: $showApiKey,
            isCompact: isCompact,
            textFont: textFont,
            isTesting: testingService == "Gemini",
            testDisabled: isTestingApi,
            commit: { handleAPIKeyChange($0) },
            onTest: { testApiKey() }
        )
    }
    
    @ViewBuilder
    private var grokApiKeyRow: some View {
        Group {
            if isCompact {
                LazyVStack(alignment: .leading, spacing: 4) {
                    grokApiKeyLabel
                    grokApiKeyInputAndControls
                }
            } else {
                HStack(spacing: isCompact ? 2 : 8) {
                    grokApiKeyLabel
                    grokApiKeyInputAndControls
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var grokApiKeyLabel: some View {
        Text("Grok API Key:")
            .font(labelFont)
            .foregroundColor(.secondary)
            .help("Enter your Grok API key here")
            .fixedSize()
    }
    
    private var grokApiKeyInputAndControls: some View {
        APIKeyField(
            service: "Grok",
            storedKey: $appState.settings.grokApiKey,
            showKey: $showGrokApiKey,
            isCompact: isCompact,
            textFont: textFont,
            isTesting: testingService == "Grok",
            testDisabled: isTestingApi,
            commit: { handleGrokAPIKeyChange($0) },
            onTest: { testGrokApiKey() }
        )
    }
    
    @ViewBuilder
    private var aimlApiKeyRow: some View {
        Group {
            if isCompact {
                LazyVStack(alignment: .leading, spacing: 4) {
                    apiKeyLabel
                    apiKeyInputAndControls
                }
            } else {
                HStack(spacing: isCompact ? 2 : 8) {
                    apiKeyLabel
                    apiKeyInputAndControls
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var apiKeyLabel: some View {
        Text("AI/ML API Key:")
            .font(labelFont)
            .foregroundColor(.secondary)
            .help("Enter your aimlapi.com API key")
            .fixedSize()
    }
    
    private var apiKeyInputAndControls: some View {
        APIKeyField(
            service: "AI/ML",
            storedKey: $appState.settings.aimlapiKey,
            showKey: $showAIMLApiKey,
            isCompact: isCompact,
            textFont: textFont,
            isTesting: testingService == "AI/ML",
            testDisabled: isTestingApi,
            commit: { handleAIMLAPIKeyChange($0) },
            onTest: { testAIMLApiKey() }
        )
    }
    
    @ViewBuilder
    private var aimlImgBBApiKeyRow: some View {
        Group {
            if isCompact {
                LazyVStack(alignment: .leading, spacing: 4) {
                    imgBBLabel
                    imgBBInputAndControls
                }
            } else {
                HStack(spacing: isCompact ? 2 : 8) {
                    imgBBLabel
                    imgBBInputAndControls
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var imgBBLabel: some View {
        Text("ImgBB API Key:")
            .font(labelFont)
            .foregroundColor(.secondary)
            .help("Enter your ImgBB API key for image uploads (required for some models, enables public URLs for all i2i)")
            .fixedSize()
    }
    
    private var imgBBInputAndControls: some View {
        APIKeyField(
            service: "ImgBB",
            storedKey: $appState.settings.imgbbApiKey,
            showKey: $showImgBBApiKey,
            isCompact: isCompact,
            textFont: textFont,
            isTesting: testingService == "ImgBB",
            testDisabled: isTestingApi,
            commit: { handleImgBBAPIKeyChange($0) },
            onTest: { testImgBBApiKey() }
        )
    }

    private func handleAPIKeyChange(_ newValue: String) {
        DispatchQueue.main.async {
            if newValue.isEmpty {
                KeychainHelper.deleteAPIKey()
            } else if KeychainHelper.saveAPIKey(newValue) {
                // Optional: Add a saved message if desired
            } else {
                errorItem = AlertError(message: "Failed to securely store Gemini API key.", fullMessage: nil)
            }
        }
    }
    
    private func testApiKey() {
        let key = appState.settings.apiKey
        isTestingApi = true
        testingService = "gemini"
        Task { @MainActor in
            defer { isTestingApi = false; testingService = nil }
            do {
                try await KeyValidation.check(provider: .gemini, key: key)
                guard key == appState.settings.apiKey else { return }
                successMessage = "Connection authenticated. Model access and sufficient credits are not guaranteed."
                showSuccessAlert = true
            } catch {
                guard key == appState.settings.apiKey else { return }
                errorItem = AlertError(message: error.localizedDescription, fullMessage: nil)
            }
        }
    }

    private func handleGrokAPIKeyChange(_ newValue: String) {
        DispatchQueue.main.async {
            if newValue.isEmpty {
                KeychainHelper.deleteGrokAPIKey()
            } else if KeychainHelper.saveGrokAPIKey(newValue) {
                // Optional: Add a saved message if desired
            } else {
                errorItem = AlertError(message: "Failed to securely store Grok API key.", fullMessage: nil)
            }
        }
    }
    
    private func testGrokApiKey() {
        let key = appState.settings.grokApiKey
        isTestingApi = true
        testingService = "grok"
        Task { @MainActor in
            defer { isTestingApi = false; testingService = nil }
            do {
                try await KeyValidation.check(provider: .grok, key: key)
                guard key == appState.settings.grokApiKey else { return }
                successMessage = "Connection authenticated. Model access and sufficient credits are not guaranteed."
                showSuccessAlert = true
            } catch {
                guard key == appState.settings.grokApiKey else { return }
                errorItem = AlertError(message: error.localizedDescription, fullMessage: nil)
            }
        }
    }

    private func handleAIMLAPIKeyChange(_ newValue: String) {
        DispatchQueue.main.async {
            if newValue.isEmpty {
                KeychainHelper.deleteAIMLAPIKey()
            } else if KeychainHelper.saveAIMLAPIKey(newValue) {
                // Optional: Add saved message
            } else {
                errorItem = AlertError(message: "Failed to securely store AI/ML API key.", fullMessage: nil)
            }
        }
    }
    
    private func testAIMLApiKey() {
        let key = appState.settings.aimlapiKey
        isTestingApi = true
        testingService = "AI/ML"
        Task { @MainActor in
            defer { isTestingApi = false; testingService = nil }
            do {
                try await KeyValidation.check(provider: .aimlapi, key: key)
                guard key == appState.settings.aimlapiKey else { return }
                successMessage = "Connection authenticated. Model access and sufficient credits are not guaranteed."
                showSuccessAlert = true
            } catch {
                guard key == appState.settings.aimlapiKey else { return }
                errorItem = AlertError(message: error.localizedDescription, fullMessage: nil)
            }
        }
    }

    private func handleImgBBAPIKeyChange(_ newValue: String) {
        DispatchQueue.main.async {
            if newValue.isEmpty {
                KeychainHelper.deleteImgBBAPIKey()
            } else if KeychainHelper.saveImgBBAPIKey(newValue) {
                // Optional: Add saved message
            } else {
                errorItem = AlertError(message: "Failed to securely store ImgBB API key.", fullMessage: nil)
            }
        }
    }
    
    private func testImgBBApiKey() {
        showHostingInfo = true
    }

}

/// API-key input row (field + eye/paste/test cluster) that edits a local draft and
/// persists only on commit — submit, focus loss, paste, or pressing Test. A stray
/// keystroke can no longer silently replace a stored key, and the field is defocused
/// on appear so a stored key never starts auto-selected.
private struct APIKeyField: View {
    let service: String
    @Binding var storedKey: String
    @Binding var showKey: Bool
    let isCompact: Bool
    let textFont: Font
    let isTesting: Bool
    let testDisabled: Bool
    let commit: (String) -> Void
    let onTest: () -> Void

    @State private var draft: String = ""
    /// The stored value captured when this field last gained focus. Used to tell "the user
    /// made no edits" apart from "the user typed something": if the draft still equals this
    /// snapshot on commit, we skip the write so an external write (e.g. the setup wizard)
    /// that landed while we were focused isn't clobbered. (finding #10)
    @State private var focusSnapshot: String = ""
    @FocusState private var isFocused: Bool

#if os(macOS)
    private static let terminationNotification = NSApplication.willTerminateNotification
#else
    private static let terminationNotification = UIApplication.willResignActiveNotification
#endif

    var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            Group {
                if showKey {
                    TextField("Enter or paste API key", text: $draft)
                        .help("Visible \(service) API key input")
                } else {
                    SecureField("Enter or paste API key", text: $draft)
                        .help("Hidden \(service) API key input")
                }
            }
            .focused($isFocused)
            .onSubmit { commitDraft() }
            .textFieldStyle(.roundedBorder)
            .font(textFont)
            .autocorrectionDisabled()
            .frame(maxWidth: .infinity)
            .minimumScaleFactor(0.8)
            .accessibilityLabel("\(service) API key input")

            actionCluster
        }
        .onAppear {
            draft = storedKey
            focusSnapshot = storedKey
            // Don't let the field grab initial focus with the stored key selected —
            // that's how a stray keystroke could wipe a saved key.
            DispatchQueue.main.async { isFocused = false }
        }
        .onChange(of: storedKey) { newValue in
            // Stay in sync with external writers (setup wizard, other views)
            if !isFocused && draft != newValue {
                draft = newValue
            }
        }
        .onChange(of: isFocused) { focused in
            if focused {
                // Snapshot the stored value at focus-begin so commitDraft can detect a
                // no-op session and avoid clobbering a concurrent external write.
                focusSnapshot = storedKey
            } else {
                commitDraft()
            }
        }
        .onDisappear {
            // Closing the sheet while the field is still focused must not drop the edit
            commitDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.terminationNotification)) { _ in
            // Cmd-Q / backgrounding with the field still focused doesn't fire onDisappear,
            // so commit any pending draft on termination too. (finding #5)
            commitDraft()
        }
    }

    private func commitDraft() {
        // No edits during this focus session → don't write. Otherwise a value that landed in
        // storedKey externally (e.g. the setup wizard) while we were focused would be
        // overwritten by our stale draft. (finding #10)
        guard draft != focusSnapshot else { return }
        guard draft != storedKey else { return }
        storedKey = draft
        commit(draft)
    }

    private func pasteFromClipboard() {
        var pastedText: String? = nil
#if os(macOS)
        pastedText = NSPasteboard.general.string(forType: .string)
#elseif os(iOS)
        pastedText = UIPasteboard.general.string
#endif
        if let text = pastedText {
            draft = text
            commitDraft()
        }
    }

    private var actionCluster: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            Button {
                showKey.toggle()
            } label: {
                Image(systemName: showKey ? "eye.slash" : "eye")
                    .font(.system(size: isCompact ? 13 : 15))
                    .foregroundStyle(.secondary)
                    .frame(width: isCompact ? 36 : 30, height: isCompact ? 36 : 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Toggle \(service) API key visibility")
            .accessibilityLabel("Toggle \(service) API key visibility")

            Button(action: pasteFromClipboard) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: isCompact ? 13 : 15))
                    .foregroundStyle(.secondary)
                    .frame(width: isCompact ? 36 : 30, height: isCompact ? 36 : 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Paste \(service) API key from clipboard")
            .accessibilityLabel("Paste \(service) API key")

            Button {
                // Make sure the key being tested is the one on screen
                commitDraft()
                onTest()
            } label: {
                Group {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(draft.isEmpty ? Color.secondary.opacity(0.4) : .blue)
                    }
                }
                .font(.system(size: isCompact ? 13 : 15))
                .frame(width: isCompact ? 36 : 30, height: isCompact ? 36 : 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(draft.isEmpty || testDisabled)
            .help("Test the \(service) API key")
            .accessibilityLabel("Test \(service) API key")
        }
        .padding(.horizontal, isCompact ? 2 : 4)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            configuration.label
                .font(.headline)
                .foregroundColor(.primary)
            configuration.content
        }
        .padding()
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}
