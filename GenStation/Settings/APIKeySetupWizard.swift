// APIKeySetupWizard.swift
// Multi-step wizard for setting up API keys on first launch

import SwiftUI
import GenStationCore

// MARK: - API Provider

enum APIProvider: String, CaseIterable, Identifiable {
    case gemini = "gemini"
    case aimlapi = "aimlapi"
    case grok = "grok"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .aimlapi: return "AI/ML API"
        case .grok: return "xAI Grok"
        }
    }

    var icon: String {
        switch self {
        case .gemini: return "sparkle"
        case .aimlapi: return "cube.transparent"
        case .grok: return "bolt.fill"
        }
    }

    var tagline: String {
        switch self {
        case .gemini: return "Image generation and editing"
        case .aimlapi: return "Image and video models from multiple providers"
        case .grok: return "Image generation, editing, and video"
        }
    }

    var keyPageURL: URL {
        switch self {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey") ?? URL(string: "https://aistudio.google.com")!
        case .aimlapi: return URL(string: "https://aimlapi.com/app/keys") ?? URL(string: "https://aimlapi.com")!
        case .grok: return URL(string: "https://console.x.ai/api-keys") ?? URL(string: "https://console.x.ai")!
        }
    }

    var instructions: String {
        switch self {
        case .gemini:
            return "1. Sign in with your Google account\n2. Click 'Create API Key'\n3. Copy the key and paste it below"
        case .aimlapi:
            return "1. Create an account or sign in\n2. Go to API Keys section\n3. Create a new key and copy it"
        case .grok:
            return "1. Sign in to the xAI console\n2. Navigate to API Keys\n3. Generate a new key and copy it"
        }
    }
}

// MARK: - Test Status

enum APIKeyTestStatus: Equatable {
    case idle
    case testing
    case success
    case failed(String)

    static func == (lhs: APIKeyTestStatus, rhs: APIKeyTestStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.testing, .testing), (.success, .success):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Wizard Step

enum WizardStep: Equatable {
    case welcome
    case providerSelection
    case providerSetup(APIProvider)
    case comfySetup
    case completion
}

// MARK: - API Key Setup Wizard

struct APIKeySetupWizard: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let onComplete: () -> Void

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    // MARK: - State

    @State private var checkTask: Task<Void, Never>?
    @State private var checkID = UUID()
    @State private var currentStep: WizardStep = .providerSelection
    @State private var selectedProviders: Set<APIProvider> = []

    // Per-provider key input
    @State private var geminiKey: String = ""
    @State private var aimlapiKey: String = ""
    @State private var grokKey: String = ""

    // Per-provider test status
    @State private var geminiTestStatus: APIKeyTestStatus = .idle
    @State private var aimlapiTestStatus: APIKeyTestStatus = .idle
    @State private var grokTestStatus: APIKeyTestStatus = .idle

    // Track which providers were configured
    @State private var configuredProviders: Set<APIProvider> = []
    @State private var imgbbConfigured: Bool = false
    @State private var choseComfy = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            if currentStep != .welcome && currentStep != .completion {
                progressIndicator
                    .padding(.top, 16)
            }

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case .welcome:
                        welcomeStep
                    case .providerSelection:
                        providerSelectionStep
                    case .providerSetup(let provider):
                        providerSetupStep(provider)
                    case .comfySetup:
                        ExistingComfySetupView { choseComfy = true; currentStep = .completion }
                    case .completion:
                        completionStep
                    }
                }
                .padding(.horizontal, isCompact ? 20 : 32)
                .padding(.vertical, 32)
                .frame(maxWidth: isCompact ? .infinity : 600)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: isCompact ? nil : 500, idealWidth: isCompact ? nil : 600, maxWidth: isCompact ? .infinity : 700)
        .frame(minHeight: isCompact ? nil : 540, idealHeight: isCompact ? nil : 650, maxHeight: isCompact ? .infinity : 800)
        .background(Color.systemBackground)
        .onDisappear { invalidateCheck() }
        .onChange(of: geminiKey) { _, _ in invalidateCheck(); geminiTestStatus = .idle }
        .onChange(of: aimlapiKey) { _, _ in invalidateCheck(); aimlapiTestStatus = .idle }
        .onChange(of: grokKey) { _, _ in invalidateCheck(); grokTestStatus = .idle }
        .onChange(of: currentStep) { _, _ in invalidateCheck() }
        .onAppear {
            // Pre-populate with any existing keys
            geminiKey = appState.settings.apiKey
            aimlapiKey = appState.settings.aimlapiKey
            grokKey = appState.settings.grokApiKey

            // Mark providers with existing keys as already configured
            if !appState.settings.apiKey.isEmpty {
                configuredProviders.insert(.gemini)
            }
            if !appState.settings.aimlapiKey.isEmpty {
                configuredProviders.insert(.aimlapi)
            }
            if !appState.settings.grokApiKey.isEmpty {
                configuredProviders.insert(.grok)
            }
            if !appState.settings.imgbbApiKey.isEmpty {
                imgbbConfigured = true
            }
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStepIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var totalSteps: Int {
        // provider selection + each provider + imgbb (if AI/ML API selected) + completion
        2 + selectedProviders.count
    }

    private var currentStepIndex: Int {
        switch currentStep {
        case .welcome: return 0
        case .providerSelection: return 0
        case .providerSetup(let provider):
            let sortedProviders = selectedProviders.sorted { $0.rawValue < $1.rawValue }
            return 1 + (sortedProviders.firstIndex(of: provider) ?? 0)
        case .comfySetup: return 1
        case .completion: return totalSteps - 1
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.modal))
                .shadow(radius: 6)

            VStack(spacing: 12) {
                Text("Set Up Your AI Providers")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("GenStation connects to various AI services.\nLet's configure your API keys.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: { currentStep = .providerSelection }) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Skip for Now") {
                    appState.settings.hasSeenOutputFolderSetup = true
                onComplete()
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Provider Selection Step

    private var providerSelectionStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Choose a Starting Provider")
                    .font(.title.bold())

                Text("Connect one now; add others later in Settings. Usage is billed separately by your provider.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(APIProvider.allCases) { provider in
                    providerCard(provider)
                }
            }

            Button("Connect an existing ComfyUI server") {
                selectedProviders = []
                currentStep = .comfySetup
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: { goToFirstProvider() }) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedProviders.isEmpty)

                Button("Skip All") {
                    currentStep = .completion
                }
                .foregroundColor(.secondary)
            }
        }
    }

    private func providerCard(_ provider: APIProvider) -> some View {
        let isSelected = selectedProviders.contains(provider)

        return Button(action: {
            if isSelected {
                selectedProviders.remove(provider)
            } else {
                selectedProviders = [provider]
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Image(systemName: provider.icon)
                    .font(.title2)
                    .foregroundColor(.primary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(provider.tagline)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.panel)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.panel)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Provider Setup Step

    private func providerSetupStep(_ provider: APIProvider) -> some View {
        let binding = keyBinding(for: provider)
        let testStatus = testStatus(for: provider)

        return VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: provider.icon)
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Set Up \(provider.displayName)")
                    .font(.title.bold())
            }

            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("How to get your API key:")
                    .font(.headline)

                Text(provider.instructions)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)

                Link(destination: provider.keyPageURL) {
                    HStack {
                        Text("Get API Key")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.headline)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: DS.Radius.panel).fill(Color.secondary.opacity(0.05)))

            Text("Checking does not generate content or establish available credits or model eligibility.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Save without checking") {
                invalidateCheck()
                let key = binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty && saveKey(key, for: provider) {
                    configuredProviders.insert(provider)
                    setTestStatus(.idle, for: provider)
                } else {
                    setTestStatus(.failed("Could not save the key. Your existing key is unchanged."), for: provider)
                }
            }

            // Key input
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    SecureField("Paste your API key here", text: binding)
                        .textFieldStyle(.roundedBorder)

                    Button(action: { pasteFromClipboard(to: binding) }) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("Paste from clipboard")
                }

                // Test button and status
                HStack(spacing: 12) {
                    Button(action: { testKey(for: provider) }) {
                        HStack(spacing: 6) {
                            if testStatus == .testing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.circle")
                            }
                            Text("Test Key")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(binding.wrappedValue.isEmpty || testStatus == .testing)

                    testStatusView(testStatus)

                    Spacer()
                }
                .padding(.top, 4)
            }

            Spacer()

            // Navigation
            VStack(spacing: 16) {
                Button(action: { goToNextStep(from: provider) }) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(testStatus == .testing)

                Button("Skip this provider") {
                    goToNextStep(from: provider)
                }
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Connection status

    @ViewBuilder
    private func testStatusView(_ status: APIKeyTestStatus) -> some View {
        switch status {
        case .idle:
            Text("Not checked").font(.caption).foregroundStyle(.secondary)
        case .testing:
            Text("Testing...")
                .font(.caption)
                .foregroundColor(.secondary)
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connection authenticated")
                    .foregroundColor(.green)
            }
            .font(.caption.weight(.medium))
        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .foregroundColor(.red)
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Completion Step

    private var completionStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            VStack(spacing: 12) {
                Text(configuredProviders.isEmpty && !choseComfy ? "Set Up Later" : "Ready to Create")
                    .font(.largeTitle.bold())

                Text("Provider usage is billed separately. A connection check does not generate content or guarantee credits or model access.")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            // Summary
            VStack(alignment: .leading, spacing: 12) {
                ForEach(APIProvider.allCases) { provider in
                    HStack(spacing: 12) {
                        Image(systemName: configuredProviders.contains(provider) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(configuredProviders.contains(provider) ? .green : .secondary)

                        Image(systemName: provider.icon)
                            .foregroundColor(.primary)
                            .frame(width: 24)

                        Text(provider.displayName)
                            .foregroundColor(configuredProviders.contains(provider) ? .primary : .secondary)

                        Spacer()

                        if configuredProviders.contains(provider) {
                            Text("Key saved")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Not configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // ImgBB row (if AI/ML API was selected or configured)
                if selectedProviders.contains(.aimlapi) || imgbbConfigured {
                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 12) {
                        Image(systemName: imgbbConfigured ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(imgbbConfigured ? .green : .secondary)

                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundColor(.primary)
                            .frame(width: 24)

                        Text("ImgBB Hosting")
                            .foregroundColor(imgbbConfigured ? .primary : .secondary)

                        Spacer()

                        if imgbbConfigured {
                            Text("Key saved")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Optional")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: DS.Radius.panel).fill(Color.secondary.opacity(0.05)))

            // Settings reminder
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
                Text("You can configure additional providers anytime in Settings > Setup Wizard")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .multilineTextAlignment(.center)

            Spacer()

            Button(action: {
                if let provider = selectedProviders.first {
                    appState.settings.provider = Provider(rawValue: provider.rawValue)!
                    appState.settings.task = .image
                    if provider == .aimlapi && !ReleaseModelPolicy.allows(appState.settings.selectedAIMLModel, task: .image) {
                        appState.settings.selectedAIMLModel = "google/gemini-3.1-flash-image-preview"
                    }
                }
                appState.settings.hasSeenOutputFolderSetup = true
                onComplete()
            }) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.vertical)
    }

    // MARK: - Helpers

    private func keyBinding(for provider: APIProvider) -> Binding<String> {
        switch provider {
        case .gemini: return $geminiKey
        case .aimlapi: return $aimlapiKey
        case .grok: return $grokKey
        }
    }

    private func testStatus(for provider: APIProvider) -> APIKeyTestStatus {
        switch provider {
        case .gemini: return geminiTestStatus
        case .aimlapi: return aimlapiTestStatus
        case .grok: return grokTestStatus
        }
    }

    private func setTestStatus(_ status: APIKeyTestStatus, for provider: APIProvider) {
        switch provider {
        case .gemini: geminiTestStatus = status
        case .aimlapi: aimlapiTestStatus = status
        case .grok: grokTestStatus = status
        }
    }

    private func goToFirstProvider() {
        let sortedProviders = selectedProviders.sorted { $0.rawValue < $1.rawValue }
        if let first = sortedProviders.first {
            currentStep = .providerSetup(first)
        } else {
            currentStep = .completion
        }
    }

    private func goToNextStep(from provider: APIProvider) {
        let sortedProviders = selectedProviders.sorted { $0.rawValue < $1.rawValue }
        if let index = sortedProviders.firstIndex(of: provider),
           index + 1 < sortedProviders.count {
            currentStep = .providerSetup(sortedProviders[index + 1])
        } else {
            currentStep = .completion
        }
    }

    private func pasteFromClipboard(to binding: Binding<String>) {
        #if os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            binding.wrappedValue = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #else
        if let string = UIPasteboard.general.string {
            binding.wrappedValue = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
    }

    // MARK: - API Key Testing

    private func invalidateCheck() {
        checkTask?.cancel()
        checkID = UUID()
        if geminiTestStatus == .testing { geminiTestStatus = .idle }
        if grokTestStatus == .testing { grokTestStatus = .idle }
        if aimlapiTestStatus == .testing { aimlapiTestStatus = .idle }
    }

    private func testKey(for provider: APIProvider) {
        let key = keyBinding(for: provider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        invalidateCheck()
        let id = checkID
        setTestStatus(.testing, for: provider)
        checkTask = Task { @MainActor in
            do {
                try await KeyValidation.check(provider: Provider(rawValue: provider.rawValue)!, key: key)
                guard !Task.isCancelled, id == checkID,
                      keyBinding(for: provider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) == key else { return }
                guard saveKey(key, for: provider) else {
                    setTestStatus(.failed("Connection authenticated, but Keychain could not save the key. Try saving again."), for: provider)
                    return
                }
                setTestStatus(.success, for: provider)
                configuredProviders.insert(provider)
            } catch {
                guard !Task.isCancelled, id == checkID else { return }
                setTestStatus(.failed(error.localizedDescription), for: provider)
            }
        }
    }

    private func saveKey(_ key: String, for provider: APIProvider) -> Bool {
        switch provider {
        case .gemini:
            guard KeychainHelper.saveAPIKey(key) else { return false }
            appState.settings.apiKey = key
        case .aimlapi:
            guard KeychainHelper.saveAIMLAPIKey(key) else { return false }
            appState.settings.aimlapiKey = key
        case .grok:
            guard KeychainHelper.saveGrokAPIKey(key) else { return false }
            appState.settings.grokApiKey = key
        }
        return true
    }

}

// MARK: - Preview

#if DEBUG
struct APIKeySetupWizard_Previews: PreviewProvider {
    static var previews: some View {
        APIKeySetupWizard(onComplete: {})
            .environmentObject(AppState())
    }
}
#endif
