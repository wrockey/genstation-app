// ContentView.swift
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import Dispatch
import AppKit
#elseif os(iOS)
import UIKit
#endif
import GenStationCore

let openGeneralSettingsNotification = Notification.Name("OpenGeneralSettings")

#if os(macOS)
// MARK: - Native Split View for smooth resizing
struct NativeSplitView<Leading: View, Trailing: View>: NSViewRepresentable {
    let leading: Leading
    let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        let leadingHost = NSHostingView(rootView: leading)
        let trailingHost = NSHostingView(rootView: trailing)

        leadingHost.translatesAutoresizingMaskIntoConstraints = false
        trailingHost.translatesAutoresizingMaskIntoConstraints = false

        splitView.addArrangedSubview(leadingHost)
        splitView.addArrangedSubview(trailingHost)

        // Initial position is set on first layout in resizeSubviewsWithOldSize
        splitView.setPosition(splitView.bounds.width / 2, ofDividerAt: 0)

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        // Update hosted views
        if let leadingHost = splitView.arrangedSubviews.first as? NSHostingView<Leading> {
            leadingHost.rootView = leading
        }
        if let trailingHost = splitView.arrangedSubviews.last as? NSHostingView<Trailing> {
            trailingHost.rootView = trailing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, NSSplitViewDelegate {
        private var hasSetInitialPosition = false

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return 300
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return splitView.bounds.width - 300
        }

        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
            guard splitView.arrangedSubviews.count == 2 else {
                splitView.adjustSubviews()
                return
            }

            let leadingView = splitView.arrangedSubviews[0]
            let trailingView = splitView.arrangedSubviews[1]
            let dividerThickness = splitView.dividerThickness
            let newWidth = splitView.bounds.width

            if !hasSetInitialPosition {
                // First layout: split evenly between main content and detail pane
                hasSetInitialPosition = true
                let halfWidth = (newWidth - dividerThickness) / 2
                leadingView.frame = NSRect(x: 0, y: 0, width: halfWidth, height: splitView.bounds.height)
                trailingView.frame = NSRect(x: halfWidth + dividerThickness, y: 0, width: halfWidth, height: splitView.bounds.height)
            } else {
                // Subsequent resizes: preserve trailing pane width
                let trailingWidth = min(max(trailingView.frame.width, 300), 900)
                let leadingWidth = max(300, newWidth - trailingWidth - dividerThickness)
                leadingView.frame = NSRect(x: 0, y: 0, width: leadingWidth, height: splitView.bounds.height)
                trailingView.frame = NSRect(x: leadingWidth + dividerThickness, y: 0, width: trailingWidth, height: splitView.bounds.height)
            }
        }
    }
}
#endif
struct IdentifiableData: Identifiable, Codable, Hashable {
    var id: UUID
    let data: Data
    enum CodingKeys: String, CodingKey {
        case id
        case data
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(data, forKey: .data)
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        data = try container.decode(Data.self, forKey: .data)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(data)
    }
    static func == (lhs: IdentifiableData, rhs: IdentifiableData) -> Bool {
        return lhs.id == rhs.id && lhs.data == rhs.data
    }
    init(data: Data) {
        self.id = UUID()
        self.data = data
    }
}
 
struct DeleteConfirmationInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let hasDeletableFiles: Bool
    let onConfirm: (Bool) -> Void  // true = delete files too
}
enum PresentedModal: Identifiable, Equatable {
    case history
    case responseSheet
    case fullHistoryItem(UUID)
    case markupSlot(UUID)
    case textEditor(IdentifiableData)
    case advancedSettings
    case help(Provider)
    case comfyUIWarning
    case mandatory // For first-launch mandatory view
    case apiKeySetup // For first-launch API key setup wizard
    case onboarding // For onboarding view
    case outputFolderSetup // For first-launch output folder setup
    case contentFilterBlocked([(line: Int, prompt: String, phrases: [String])])
    case deleteConfirmation(DeleteConfirmationInfo)
    case imageDescription(String)
    case jobs // Video jobs / in-flight panel
    case namedWorkflow(workflowID: UUID?, assetID: UUID?)

    var id: String {
        switch self {
        case .history: return "history"
        case .responseSheet: return "responseSheet"
        case .fullHistoryItem(let uuid): return "fullHistoryItem_\(uuid.uuidString)"
        case .markupSlot(let uuid): return "markupSlot_\(uuid.uuidString)"
        case .textEditor(let data): return "textEditor_\(data.id.uuidString)"
        case .advancedSettings: return "advancedSettings"
        case .help(let mode): return "help_\(mode.rawValue)"
        case .comfyUIWarning: return "comfyUIWarning"
        case .mandatory: return "mandatory"
        case .apiKeySetup: return "apiKeySetup"
        case .onboarding: return "onboarding"
        case .outputFolderSetup: return "outputFolderSetup"
        case .contentFilterBlocked: return "contentFilterBlocked"
        case .deleteConfirmation: return "deleteConfirmation"
        case .imageDescription: return "imageDescription"
        case .jobs: return "jobs"
        case .namedWorkflow(let workflow, let asset): return "namedWorkflow_" + (workflow?.uuidString ?? "choose") + "_" + (asset?.uuidString ?? "none")
        }
    }
    
    static func == (lhs: PresentedModal, rhs: PresentedModal) -> Bool {
            lhs.id == rhs.id
        }
 
    var isSheetModal: Bool {
        switch self {
        case .history, .textEditor, .advancedSettings, .comfyUIWarning, .mandatory, .apiKeySetup, .onboarding, .outputFolderSetup, .responseSheet, .imageDescription, .jobs, .namedWorkflow:
            return true
        case .fullHistoryItem, .markupSlot:
            return false
        case .help(let mode):
            return mode != .comfyUI // Sheet for other modes, full for ComfyUI
        case .contentFilterBlocked:
            return true
        case .deleteConfirmation:
            return true
        }
    }
 
    var isFullCoverModal: Bool {
        return !isSheetModal
    }
    var prefersSheetInCompact: Bool {
        switch self {
        case .deleteConfirmation, .comfyUIWarning, .advancedSettings:
            return true
        default:
            return false
        }
    }
 
    var prefersFullScreenCover: Bool {
        switch self {
        case .responseSheet, .fullHistoryItem, .markupSlot, .onboarding, .mandatory, .apiKeySetup, .outputFolderSetup,
             .contentFilterBlocked, .help, .textEditor, .history:
            return true
        default:
            return false
        }
    }
   
}
enum GenerationError: LocalizedError {
    case invalidURL
    case encodingFailed(String)
    case apiError(String)
    case noWorkflow
    case invalidServerURL
    case invalidWebSocketURL
    case invalidPromptNode
    case noOutputImage
    case decodeFailed
    case fetchFailed(String)
    case invalidViewURL
    case invalidImageNode
    case noSamplerNode
    case uploadFailed(String)
    case queueFailed(String)
    case workflowNotConverted(String)
    case missingWorkflowInputs(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL. Please check your configuration and ensure the endpoint is correct."
        case .encodingFailed:
            return "Failed to encode request data. Verify your input (e.g., prompt or images) and try again."
        case .apiError(let detail):
            return ProviderFailure.redact(detail)
        case .noWorkflow:
            return "No ComfyUI workflow loaded. Please select a valid JSON or PNG workflow file in the configuration section."
        case .invalidServerURL:
            return "Invalid ComfyUI server URL. Ensure it starts with http:// or https:// and points to your running server (e.g., http://localhost:8188)."
        case .invalidWebSocketURL:
            return "Invalid WebSocket URL for progress updates. Verify your server URL and ensure the ComfyUI server is accessible."
        case .invalidPromptNode:
            return "Invalid prompt node in workflow. Select a different prompt node or reload the workflow."
        case .noOutputImage:
            return "No output image generated. Verify your workflow has a valid output node (e.g., SaveImage) and try again."
        case .decodeFailed:
            return "Failed to decode generated image. The output may be corrupted—check your workflow or server logs."
        case .fetchFailed:
            return "Failed to fetch image from server. Ensure the server is responsive and the output node is configured correctly."
        case .invalidViewURL:
            return "Invalid URL for viewing generated image. Check your server configuration."
        case .invalidImageNode:
            return "Invalid image input node in workflow. Select a different image node or ensure your workflow supports image inputs."
        case .noSamplerNode:
            return "No sampler node (e.g., KSampler) found in workflow. Please use a workflow that includes a sampler for generation."
        case .uploadFailed:
            return "Image upload failed."
        case .queueFailed:
            return "Prompt queue failed."
        case .workflowNotConverted:
            return "Workflow is not in API format — it was likely imported without conversion. Re-import it via Workflow ▸ Browse (GenStation converts it automatically), or export from ComfyUI using Save (API Format)."
        case .missingWorkflowInputs:
            return "Workflow is missing required node inputs and can't be queued. Check the listed nodes in ComfyUI (or ComfyUI Advanced Settings) and re-save the workflow."
        }
    }
    var details: String? {
        switch self {
        case .encodingFailed(let d),
             .apiError(let d),
             .fetchFailed(let d),
             .uploadFailed(let d),
             .queueFailed(let d),
             .workflowNotConverted(let d),
             .missingWorkflowInputs(let d):
            return d
        default:
            return nil
        }
    }
}

enum PowerPanelType: String, CaseIterable, Identifiable {
    case none  // Dummy for compact reset/initial
    // Creation tools (workflow order: styles → model options → batch)
    case styles = "Style Browser"
    case advanced = "Model Options"  // Renamed from "Advanced Config" to differentiate from General Options
    case batch = "Batch Editor"
    // Viewing tools (recency: session → history)
    case response = "Session Gallery"
    case history = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: return ""  // Not used in UI
        case .styles: return "paintpalette"
        case .advanced: return "gearshape"
        case .batch: return "doc.text"
        case .response: return "photo.on.rectangle.angled"
        case .history: return "clock.arrow.circlepath"
        }
    }

    var shortLabel: String {
        switch self {
        case .none: return ""
        case .styles: return "Styles"
        case .advanced: return "Model"  // Short for "Model Options"
        case .batch: return "Batch"
        case .response: return "Session"
        case .history: return "History"
        }
    }

    static var allVisibleCases: [PowerPanelType] {
        allCases.filter { $0 != .none }
    }

    var keyboardShortcut: KeyEquivalent? {
        switch self {
        case .none:
            return nil  // Not visible, no shortcut needed
        case .styles:
            return "1"
        case .advanced:
            return "2"
        case .batch:
            return "3"
        case .response:
            return "4"
        case .history:
            return "5"
        }
    }
}


// MARK: - Liquid Glass Power Panel Sidebar
struct PowerPanelSelectorView: View {
    @Binding var selected: PowerPanelType
    @EnvironmentObject var appState: AppState

    private var modeAccent: Color {
        appState.settings.provider.liquidAccent
    }

    var body: some View {
        VStack(spacing: 20) {
            ForEach(PowerPanelType.allVisibleCases) { panel in
                button(for: panel)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .padding(6)
    }

    private func button(for panel: PowerPanelType) -> some View {
        let isSelected = selected == panel

        return Button {
            withAnimation(DS.Anim.springDefault) {
                selected = panel
            }
        } label: {
            Image(systemName: panel.icon)
                .font(.system(size: 24, weight: .medium))
                .frame(width: 48, height: 48)
                .foregroundColor(isSelected ? modeAccent : .secondary)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(modeAccent.opacity(0.4), lineWidth: 1)
                                )
                                .shadow(color: modeAccent.opacity(0.3), radius: 8, y: 2)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(panel.rawValue)
        .accessibilityLabel(panel.rawValue)
    }
}

// MARK: - Compact Floating Power Panel Bar (iPhone Portrait)
#if os(iOS)
struct CompactPowerPanelBar: View {
    @Binding var selectedPanel: PowerPanelType?
    @EnvironmentObject var appState: AppState

    private var modeAccent: Color {
        appState.settings.provider.liquidAccent
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PowerPanelType.allVisibleCases) { panel in
                Button {
                    withAnimation(DS.Anim.springFast) {
                        selectedPanel = panel
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: panel.icon)
                            .font(.system(size: 22, weight: .medium))
                        Text(panel.shortLabel)
                            .font(DS.captionFont.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(selectedPanel == panel ? modeAccent : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(panel.rawValue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 12, y: -4)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
#endif


// MARK: - Power Panel Content
struct PowerPanelContentView: View {
    let selected: PowerPanelType
    var isInSheet: Bool = false  // When true, sheet provides its own title
    var onDescribeImage: ((HistoryItem) async -> Void)? = nil  // Callback for image-to-prompt
    @EnvironmentObject var appState: AppState
    @State private var responsePanelScale: CGFloat = 1.8

#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    var body: some View {
        Group {
            switch selected {

            case .none:
                        // Initial/closed state on compact – show nothing (or a placeholder if desired)
                        EmptyView()  // Or Text("Select a panel") for debugging
            case .history:
                VStack(spacing: 0) {
                    #if os(macOS)
                    // Header with popout button
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2.weight(.medium))
                            .foregroundColor(appState.settings.provider.liquidAccent)
                        Text("History")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(appState.settings.provider.liquidAccent)
                        Spacer()
                        Button {
                            openWindow(id: "history-panel-window")
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open History in separate window")
                        .accessibilityLabel("Open History in separate window")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    Divider()
                    #endif

                    HistoryView(columnVisibility: .constant(.all), showTitle: !isInSheet, onDescribeImage: onDescribeImage)
                        .environmentObject(appState)
                }

            case .advanced:
                ScrollView {
                    VStack(spacing: 24) {
                        // Inline header with liquid glass styling
                        HStack(spacing: 12) {
                            Image(systemName: "gearshape.2")
                                .font(.title2.weight(.medium))
                                .foregroundColor(appState.settings.provider.liquidAccent)
                                .frame(width: 32)

                            Text(advancedSettingsTitle)
                                .font(.title2.weight(.semibold))
                                .foregroundColor(appState.settings.provider.liquidAccent)

                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                        // Mode-specific content
                        switch appState.settings.provider {
                        case .comfyUI:
                            comfyUIAdvancedContent

                        case .aimlapi:
                            aimlAdvancedContent

                        case .gemini:
                            geminiAdvancedContent

                        case .grok:
                            grokAdvancedContent
                        }
                    }
                    .padding(.vertical)
                }

            case .batch:
                // Pass empty bookmark when new file mode is active so onAppear won't resolve old file
                let currentBookmark = appState.ui.batchNewFilePrompts != nil
                    ? Data()
                    : (AppStorageContext.defaults.data(forKey: "batchFileBookmark") ?? Data())
                TextEditorView(bookmarkData: currentBookmark, isSheet: isInSheet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .styles:
                #if os(iOS)
                // iOS: NavigationStack provides its own chrome; skip CardView to avoid double padding
                TabFilterStyleBrowser()
                    .environmentObject(appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                #else
                CardView(title: "Style Browser") {
                    TabFilterStyleBrowser()
                        .environmentObject(appState)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                #endif

            case .response:
                CardView(title: "") {
                    SessionGalleryView()
                        .environmentObject(appState)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DS.Anim.standard, value: selected) // Smooth panel transitions
        .background(
            ZStack {
                Color.clear.background(.ultraThickMaterial)
                if selected != .history {
                    appState.settings.provider.liquidAccent.opacity(0.07)  // Slightly subtler for content panels
                }
            }
        )
    }

    // MARK: - Advanced Settings Helpers

    private var advancedSettingsTitle: String {
        switch appState.settings.provider {
        case .comfyUI:
            return "ComfyUI Settings"
        case .aimlapi:
            return "AI/ML API Settings"
        case .gemini:
            return "Gemini Settings"
        case .grok:
            return "Grok Settings"
        }
    }

    @ViewBuilder
    private var comfyUIAdvancedContent: some View {
        PanelCard(title: "Generation Settings", icon: "slider.horizontal.3") {
            AdvancedComfyUISettingsView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var geminiAdvancedContent: some View {
        PanelCard(title: "Image Settings", icon: "photo.artframe") {
            GeminiAdvancedSettingsView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var grokAdvancedContent: some View {
        if appState.settings.isVideoMode {
            PanelCard(title: "Video Settings", icon: "video") {
                VStack(alignment: .leading, spacing: 16) {
                    Stepper("Duration: \(appState.settings.grokVideoDuration) seconds",
                            value: $appState.settings.grokVideoDuration, in: 1...15)
                    Picker("Aspect Ratio", selection: $appState.settings.grokVideoAspectRatio) {
                        ForEach(GrokVideoClient.aspectRatios, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Resolution", selection: $appState.settings.grokVideoResolution) {
                        ForEach(GrokVideoClient.resolutions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Generate audio", isOn: $appState.settings.grokVideoAudio)
                    Text("Describe a video, or add one image to animate. Aspect ratio applies to the image too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            PanelCard(title: "Image Settings", icon: "photo.artframe") {
                if appState.settings.selectedGrokModel.hasPrefix("grok-imagine") {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Aspect Ratio", selection: $appState.settings.grokAspectRatio) {
                            ForEach(["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3", "2:1", "1:2",
                                     "19.5:9", "9:19.5", "20:9", "9:20", "auto"], id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("Resolution", selection: $appState.settings.grokResolution) {
                            Text("1K").tag("1k")
                            Text("2K").tag("2k")
                        }
                        .pickerStyle(.segmented)
                        Text("These settings are sent with your Grok image generation requests.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("This model does not support adjustable aspect ratio or resolution. Select a Grok Imagine image model to use these settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var aimlAdvancedContent: some View {
        let model = appState.currentAIMLModel
        if model.maxInputImages > 0 {
            PanelCard(title: "Image Submission Method", icon: "photo.on.rectangle") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose how input images are sent to the model.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    methodRow(
                        method: .base64,
                        title: "Base64 Payload (Private)",
                        disabled: !model.acceptsBase64
                    )
                    methodRow(
                        method: .imgBB,
                        title: "ImgBB Links (Public URLs)",
                        disabled: !model.acceptsPublicURL || appState.settings.imgbbApiKey.isEmpty
                    )
                    methodRow(
                        method: .binary,
                        title: "Binary Payload (Private)",
                        disabled: !model.acceptsBinary
                    )

                    Text("Base64 is private but increases request size. Binary is efficient where supported. ImgBB uses public URLs.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if appState.settings.imageSubmissionMethod == .base64 {
                        Divider().padding(.vertical, 8)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Base64 Optimizations")
                                .font(.subheadline.bold())

                            Toggle("Convert to JPEG (lossy compression)", isOn: $appState.settings.base64ConvertToJPG)
                            Toggle("Scale Down by 50% (halves dimensions)", isOn: $appState.settings.base64Scale50Percent)

                            Text("Reduce payload size for large images.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(DS.Anim.smooth, value: appState.settings.imageSubmissionMethod)
            }
        }

        PanelCard(title: "Model Parameters", icon: "slider.horizontal.3") {
            AdvancedAIMLSettingsView(
                model: appState.currentAIMLModel,
                params: $appState.settings.aimlAdvancedParams,
                isVideo: appState.settings.isVideoMode,
                showDoneButton: false  // Embedded in power panel, no dismiss action
            )
        }

        PanelCard(title: "Model Discovery", icon: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Only supported image and video models are available in this release. Specialized and unverified operations are disabled; existing history remains available.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }
        }
    }
}

struct PanelCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String = "rectangle", @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                
                Text(title)
                    .font(.title3.bold())
                
                Spacer()
            }
            
            content
        }
        .padding()
        .background(Color.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

private struct MethodRow: View {
    let method: ImageSubmissionMethod
    let title: String
    let disabled: Bool
    
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Button(action: {
            if !disabled {
                appState.settings.imageSubmissionMethod = method
            }
        }) {
            HStack {
                Image(systemName: appState.settings.imageSubmissionMethod == method ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(disabled ? .secondary : .accentColor)
                
                Text(title)
                    .foregroundColor(disabled ? .secondary : .primary)
                
                Spacer()
            }
            .contentShape(Rectangle())  // Full-row tap
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.5 : 1.0)
        .disabled(disabled)
    }
}



// Convenience for calling
@ViewBuilder
private func methodRow(method: ImageSubmissionMethod, title: String, disabled: Bool) -> some View {
    MethodRow(method: method, title: title, disabled: disabled)
}

extension View {
    func nonAPIFormatAlert(appState: AppState) -> some View {
        alert("Non-API Workflow Detected", isPresented: Binding<Bool>(
            get: { appState.generation.showNonAPIFormatWarning },
            set: { appState.generation.showNonAPIFormatWarning = $0 }
        )) {
            Button("OK") {}
        } message: {
            Text("This workflow is in ComfyUI's standard format rather than API format. Some features may not work correctly.\n\nFor best results, export your workflow in API format: in ComfyUI, go to Settings, enable \"Dev Mode Options,\" then use \"Save (API Format).\"")
        }
    }
    func workflowErrorAlert(appState: AppState) -> some View {
        alert("Workflow Error", isPresented: Binding<Bool>(
            get: { appState.generation.workflowError != nil },
            set: { _ in appState.generation.workflowError = nil }
        )) {
            Button("OK") {}
        } message: {
            Text(appState.generation.workflowError ?? "Unknown error")
        }
    }
    func successAlert(showSuccessAlert: Binding<Bool>, successMessage: String) -> some View {
        alert("Success", isPresented: showSuccessAlert) {
            Button("OK") {}
        } message: {
            Text(successMessage)
        }
    }
    /// Forwards `appState.errorItem` (written by background work, e.g. JobQueue)
    /// into the view-local `errorItem` that `.errorAlert` actually presents.
    /// `AlertError` isn't `Equatable`, so this keys off the `Equatable` `UUID?` id.
    func mirrorAppStateErrorItem(appState: AppState, errorItem: Binding<AlertError?>) -> some View {
        onChange(of: appState.errorItem?.id) { _, newID in
            guard newID != nil, let forwarded = appState.errorItem else { return }
            errorItem.wrappedValue = forwarded
            appState.errorItem = nil
        }
    }
    func selectFolderAlert(isPresented: Binding<Bool>, selectHandler: @escaping () -> Void) -> some View {
        alert("Select Output Folder", isPresented: isPresented) {
            Button("Select Folder") {
                selectHandler()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please select an output folder before submitting the prompt.")
        }
    }
}
struct AlertError: Identifiable {
    let id = UUID()
    let message: String
    let fullMessage: String?
    init(message: String, fullMessage: String?) {
        self.message = ProviderFailure.redact(message)
        self.fullMessage = fullMessage.map(ProviderFailure.redact)
    }
}
struct DetailedError: Identifiable {
    let id = UUID()
    let message: String
}
struct ContentView: View {
    @EnvironmentObject var appState: AppState
        @Environment(\.colorScheme) var colorScheme
        @Environment(\.horizontalSizeClass) private var sizeClass
        @Environment(\.undoManager) var undoManager: UndoManager?
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.scenePhase) private var scenePhase
        @State var isLoading: Bool = false
        @State var progress: Double = 0.0
        @State var progressStep: Int = 0
        @State var progressMax: Int = 0
        @State var currentNodeName: String? = nil
        @State var webSocketTask: URLSessionWebSocketTask? = nil
        @State var isCancelled: Bool = false
        @State var errorItem: AlertError? = nil
        @State var showApiKey: Bool = false
        @State var imageScale: CGFloat = 1.0
        @State var isTestingApi: Bool = false
        @State var batchStartIndex: Int = 1
        @State var batchEndIndex: Int = 1
        @State var successMessage: String = ""
        @State var showSuccessAlert: Bool = false
        @State var showSelectFolderAlert: Bool = false
        @State var pendingAction: (() -> Void)? = nil
        @State var generationTask: Task<Void, Error>? = nil
        @State var promptTextView: (any PlatformTextView)? = nil
        @State var privacyServiceToShow: PrivacyService? = nil
        @State var onPrivacyComplete: ((Bool, Bool) -> Void)? = nil
        @State private var showGeneralOptions = false
        @State private var detailedError: DetailedError? = nil
    @State var aimlBalance: Double? = nil
    @State var balanceFetchTask: Task<Void, Never>?

    // Timeout alert state for ComfyUI generation
    @State var showTimeoutAlert: Bool = false
    @State var timeoutContinuation: CheckedContinuation<Bool, Never>? = nil

    // Retry alert state for ComfyUI network errors
    @State var showRetryAlert: Bool = false
    @State var retryAlertMessage: String = ""
    @State var retryContinuation: CheckedContinuation<Bool, Never>? = nil

    // Pending video job resume (silent auto-check)
    @State var videoResumeTask: Task<Void, Never>? = nil

    @State private var selectedPowerPanel: PowerPanelType = .none
    @State private var compactSheetPanel: PowerPanelType? = nil // For compact sheets
    @State private var detailVisible: Bool = true
    @State private var sidebarVisible: Bool = true
    @State private var splitColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var columnVisibility: NavigationSplitViewVisibility = .all   // ← new state
    
    private var platformMainFormView: some View {
        MainFormView(
            prompt: $appState.prompt,
            showApiKey: $showApiKey,
            isTestingApi: $isTestingApi,
            errorItem: $errorItem,
            imageScale: $imageScale,
            promptTextView: $promptTextView,
            isLoading: isLoading,
            progress: progress,
            progressStep: progressStep,
            progressMax: progressMax,
            currentNodeName: currentNodeName,
            isCancelled: $isCancelled,
            aimlBalance: $aimlBalance,
            balanceFetchTask: $balanceFetchTask,
            onSubmit: submitPrompt,
            onStop: stopGeneration,
            onPopOut: {
                #if os(macOS)
                openWindow(id: "response-window")
                #else
                appState.presentedModal = .responseSheet
                #endif
            },
            onAnnotate: { slotId in
                #if os(macOS)
                openWindow(value: slotId)
                #else
                appState.presentedModal = .markupSlot(slotId)
                #endif
            },
            onDescribeImage: { slot in
                Task { await self.describeImage(slot: slot) }
            },
            onComfyJSONSelected: handleComfyJSONSelection,
            onBatchFileSelected: handleBatchFileSelection,
            onBatchSubmit: batchSubmit,
            onEditBatchFile: handleEditBatchFile,
            onClearBatchFile: clearBatchFile,
            onReloadBatchFile: { reloadBatchFile() },
            batchFilePath: $appState.batchFilePath,
            batchStartIndex: $batchStartIndex,
            batchEndIndex: $batchEndIndex
        )
        .environmentObject(appState)
        .padding(.horizontal, 20)
    }
    
    private var powerPanelPicker: some View {
        Group {  // ← Type-erasing wrapper fixes opaque type mismatch
            #if os(iOS)
            if horizontalSizeClass == .compact {
                // Compact/iPhone: Icon-only buttons in a horizontal stack
                HStack(spacing: 24) {
                    ForEach(PowerPanelType.allVisibleCases) { panel in
                        Button {
                            selectedPowerPanel = panel
                        } label: {
                            Image(systemName: panel.icon)
                                .font(.system(size: 24))
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .help(panel.rawValue)
                    }
                }
                .padding(.horizontal)
            } else {
                // Regular (iPad): Segmented with icons + labels
                Picker("", selection: $selectedPowerPanel) {
                    ForEach(PowerPanelType.allVisibleCases) { panel in
                        Label(panel.rawValue, systemImage: panel.icon)
                            .tag(panel)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 600)
            }
            #else
            // macOS: Segmented (toolbar has space)
            Picker("", selection: $selectedPowerPanel) {
                ForEach(PowerPanelType.allVisibleCases) { panel in
                    Label(panel.rawValue, systemImage: panel.icon)
                        .tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 500)
            #endif
        }
    }
   
        #if os(macOS)
        @State var fileMonitor: DispatchSourceFileSystemObject? // Monitor for batch file saves
        #endif
    @AppStorage("hasLaunchedBefore", store: AppStorageContext.defaults) var hasLaunchedBefore: Bool = false
    @State private var showTextEditorBookmark: IdentifiableData? = nil
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    private var topColor: Color {
        colorScheme == .light ? Color(white: 0.98) : Color(white: 0.1)
    }
    private var bottomColor: Color {
        colorScheme == .light ? Color(white: 0.95) : Color(white: 0.15)
    }
    #if os (iOS)

// Extracted toolbar content for compact mode
    private var compactToolbarContent: some View {
            HStack(spacing: 22) {
                Button(action: { showGeneralOptions = true }) {
                    Image(systemName: "gear")  // Use "gear" to differentiate from power panel "gearshape" Config
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("General Options")
                .accessibilityLabel("General Options")
                .accessibilityHint("Opens the general settings page.")
                // Undo/Redo kept on iOS (no Edit menu available)
                Button(action: { undoManager?.undo() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(!(undoManager?.canUndo ?? false))
                .help("Undo")
                .accessibilityLabel("Undo")
                .accessibilityHint("Undoes the last action.")
                Button(action: { undoManager?.redo() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(!(undoManager?.canRedo ?? false))
                .help("Redo")
                .accessibilityLabel("Redo")
                .accessibilityHint("Redoes the last undone action.")
                // Unified Help menu (replaces separate Help and Info buttons)
                compactHelpMenuButton
                jobsButton
                billingButton
            }
        }

    /// Unified Help menu for iOS compact mode
    @ViewBuilder
    private var compactHelpMenuButton: some View {
        Menu {
            Button {
                appState.presentedModal = .help(appState.settings.provider)
            } label: {
                Label("\(appState.settings.provider.rawValue) Guide", systemImage: "book")
            }

            Divider()

            Button {
                appState.presentedModal = .onboarding
            } label: {
                Label("App Tour", systemImage: "play.circle")
            }
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
        }
        .help("Help & Guides")
        .accessibilityLabel("Help Menu")
        .accessibilityHint("Opens help options including mode guide and app tour.")
    }

#endif

#if os(iOS)
    private var useCompactLayout: Bool {
        if UIDevice.current.userInterfaceIdiom == .phone { return true }
        let shortSide = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        return shortSide < 820
    }
#endif

    var body: some View {
        Group {
                #if os(iOS)
                // Compact layout (iPhone + narrow iPads): sheets for power panels
                // Wide iPads: three-column split view
                if useCompactLayout {
                    ZStack(alignment: .bottom) {
                        NavigationStack {
                            mainGenerationView
                                .toolbar {
                                    ToolbarItemGroup(placement: toolbarPlacement) { compactToolbarContent }
                                }
                                .keyboardDoneButton()
                                .safeAreaInset(edge: .bottom) {
                                    // Reserve space for the floating bar
                                    Color.clear.frame(height: 70)
                                }
                        }

                        // Floating power panel bar
                        CompactPowerPanelBar(selectedPanel: $compactSheetPanel)
                            .environmentObject(appState)
                    }
                } else {
                    regularThreeColumnLayout
                }
                #else // macOS – always regular
                regularThreeColumnLayout
                #endif
            }
        // ALL THE SAME MODIFIERS FOR BOTH PLATFORMS
        .nonAPIFormatAlert(appState: appState)
        .workflowErrorAlert(appState: appState)
        .errorAlert(errorItem: $errorItem, detailedError: $detailedError)
        .mirrorAppStateErrorItem(appState: appState, errorItem: $errorItem)
        .successAlert(showSuccessAlert: $showSuccessAlert, successMessage: successMessage)
        .alert("Output Folder Unavailable", isPresented: Binding<Bool>(
            get: { appState.ui.outputFolderFallbackMessage != nil },
            set: { if !$0 { appState.ui.outputFolderFallbackMessage = nil } }
        )) {
            Button("Select Folder") {
                appState.ui.outputFolderFallbackMessage = nil
                showSelectFolderAlert = true
            }
            Button("OK", role: .cancel) {
                appState.ui.outputFolderFallbackMessage = nil
            }
        } message: {
            Text((appState.ui.outputFolderFallbackMessage ?? "") + "\n\nFiles were saved to Downloads instead.")
        }

        #if os(iOS)
        .fullScreenCover(item: $privacyServiceToShow) { service in
            ZStack {
                // Dimmed background
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Dismiss on background tap = cancel
                        self.onPrivacyComplete?(false, false)
                    }

                // The actual notice card
                PrivacyNoticeSheet(service: service) { consented, dontShow in
                    self.onPrivacyComplete?(consented, dontShow)
                }
            }
            .background(ClearBackgroundView())
        }
        #else
        .sheet(item: $privacyServiceToShow) { service in
            PrivacyNoticeSheet(service: service) { consented, dontShow in
                self.onPrivacyComplete?(consented, dontShow)
            }
        }
        #endif

        .selectFolderAlert(isPresented: $showSelectFolderAlert) {
            Log.debug("Showing output folder picker from alert")
            PlatformFilePicker.presentOpenPanel(allowedTypes: [.folder], allowsMultiple: false, canChooseDirectories: true) { result in
                handleOutputFolderSelection(result)
                if !appState.settings.outputPath.isEmpty {
                    pendingAction?()
                    pendingAction = nil
                }
            }
        }

        .sheet(item: $showTextEditorBookmark) { identifiable in
            NavigationStack {
                TextEditorView(bookmarkData: identifiable.data, isSheet: true)
                    .keyboardDoneButton()
                    .environmentObject(appState)
            }
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }

        .onReceive(NotificationCenter.default.publisher(for: .batchFileUpdated)) { _ in
            appState.loadBatchPrompts()
        }

        .onAppear {
            performOnAppear()
            
            // Load/validate implicitly via actual read – handles resolution, stale refresh, and real failures
            appState.loadBatchPrompts()
            
            // Unified first-launch flow — works on both platforms
            if !appState.settings.hasCompletedMandatory {
                appState.presentedModal = .mandatory
            } else if !appState.settings.hasSeenAPIKeySetup {
                appState.presentedModal = .apiKeySetup
            } else if !appState.settings.hasSeenPrettyOnboarding {
                appState.presentedModal = .onboarding
            } else if !appState.settings.hasSeenOutputFolderSetup {
                appState.settings.hasSeenOutputFolderSetup = true
                appState.presentedModal = .outputFolderSetup
            }
            // DEBUG: Uncomment to force show output folder setup on launch
//             appState.presentedModal = .outputFolderSetup
            
        }

        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                checkPendingVideoJobs()
            }
        }

        .onChange(of: appState.ui.outputImages) { _ in imageScale = 1.0 }

        .onChange(of: appState.generation.selectedImageNodeIDs) { _ in
            let maxSlots = appState.maxImageSlots
            let currentCount = appState.ui.imageSlots.count
            if currentCount > maxSlots {
                // Move excess slots to lastImageSlots instead of discarding
                let excessCount = currentCount - maxSlots
                let excess = Array(appState.ui.imageSlots.suffix(excessCount))
                appState.ui.imageSlots.removeLast(excessCount)
                appState.ui.lastImageSlots = excess + appState.ui.lastImageSlots
            }
        }
        .onChange(of: selectedPowerPanel) { newPanel in
            // Track batch editor visibility for menu commands
            appState.ui.isBatchEditorVisible = (newPanel == .batch)

            if newPanel != .none {
                #if os(iOS)
                if useCompactLayout {
                    compactSheetPanel = newPanel
                } else {
                    // iPad: ensure detail panel is visible when selecting a power panel
                    withAnimation(DS.Anim.standard) {
                        detailVisible = true
                    }
                }
                #else
                // macOS: ensure detail panel is visible when selecting a power panel
                withAnimation(DS.Anim.standard) {
                    detailVisible = true
                }
                #endif
            }
        }

        .onChange(of: appState.presentedModal) { newModal in
            #if os(iOS)
            guard !useCompactLayout else { return }  // Only intercept on wide iPad
            #endif
            
            // Intercept Advanced Settings modal → redirect to Power Panel
            if newModal == .advancedSettings && appState.settings.provider == .aimlapi {
                withAnimation(DS.Anim.standard) {
                    selectedPowerPanel = .advanced
                }
                appState.presentedModal = nil
                return
            }
            
            if case .textEditor = newModal {
                withAnimation(DS.Anim.standard) {
                    selectedPowerPanel = .batch
                }
                appState.presentedModal = nil
                return
            }
        }
        // Auto-present generated image
        .onChange(of: appState.ui.shouldPresentGeneratedImage) { shouldPresent in
            guard shouldPresent else { return }
            appState.ui.shouldPresentGeneratedImage = false  // Reset immediately

            #if os(macOS)
            openWindow(id: "response-window")
            #else
            appState.presentedModal = .responseSheet
            #endif
        }
        // Open Style Browser when requested from PromptSection
        .onChange(of: appState.ui.requestOpenStyleBrowser) { requested in
            guard requested else { return }
            appState.ui.requestOpenStyleBrowser = false  // Reset immediately

            #if os(iOS)
            if useCompactLayout {
                compactSheetPanel = .styles
            } else {
                selectedPowerPanel = .styles
            }
            #else
            selectedPowerPanel = .styles
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: openGeneralSettingsNotification)) { _ in
            showGeneralOptions = true
        }

        // MARK: - Menu Command Handlers (macOS)
        #if os(macOS)
        .menuCommandHandlers(
            appState: appState,
            selectedPowerPanel: $selectedPowerPanel,
            detailVisible: $detailVisible,
            isLoading: isLoading,
            onSubmit: submitPrompt,
            onStop: stopGeneration,
            onBatch: batchSubmit
        )
        #endif

        .sheet(isPresented: $showGeneralOptions) {
            GeneralOptionsView(isPresented: $showGeneralOptions)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
                .environmentObject(appState)
        }

        .sheet(item: $detailedError) { detail in
            DetailedErrorView(message: detail.message) { detailedError = nil }
        }
    
        // Phase 1 Addition: Apply ModalManager modifier
        .modalManager(presentedModal: $appState.presentedModal)

        // ComfyUI generation timeout alert
        .alert("Generation Taking Longer Than Expected", isPresented: $showTimeoutAlert) {
            Button("Cancel Generation", role: .destructive) {
                timeoutContinuation?.resume(returning: false)
                timeoutContinuation = nil
            }
            Button("Keep Waiting") {
                timeoutContinuation?.resume(returning: true)
                timeoutContinuation = nil
            }
        } message: {
            let minutes = appState.settings.comfyGenerationTimeout / 60
            Text("The generation has been running for \(minutes) minute\(minutes == 1 ? "" : "s"). This may indicate a problem with the ComfyUI server or workflow.\n\nWould you like to keep waiting or cancel?")
        }

        // ComfyUI network error retry alert
        .alert("Connection Error", isPresented: $showRetryAlert) {
            Button("Cancel", role: .cancel) {
                retryContinuation?.resume(returning: false)
                retryContinuation = nil
            }
            Button("Retry") {
                retryContinuation?.resume(returning: true)
                retryContinuation = nil
            }
        } message: {
            Text(retryAlertMessage)
        }

        // Add this sheet for compact mode (place it on the compact layout or main body)
        .onChange(of: compactSheetPanel) { newPanel in
            appState.ui.isBatchEditorVisible = (newPanel == .batch)
        }
        .sheet(item: $compactSheetPanel) { panel in
            NavigationStack {
                PowerPanelContentView(selected: panel, isInSheet: true, onDescribeImage: { item in await self.describeImage(item: item) })
                    .navigationTitle(panel.rawValue)
                    .keyboardDoneButton()
                    .toolbar {
                        if panel != .batch {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    compactSheetPanel = nil
                                    #if os(iOS)
                                    if useCompactLayout {
                                        selectedPowerPanel = .none  // Allows re-opening the same panel
                                    }
                                    #endif
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(panel == .history ? .blue : nil)
                            }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
    
    // New unified main generation view (used in both regular middle column and compact)

    private var mainGenerationView: some View {
        ScrollView {
            VStack(spacing: 16) {
                platformMainFormView
            }
        }
        .background(LinearGradient(gradient: Gradient(colors: [topColor, bottomColor]), startPoint: .top, endPoint: .bottom))
        // Toast overlay for batch completion
        .overlay(alignment: .top) {
            if appState.ui.showGenerationToast, let message = appState.ui.generationToastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                    Text(message)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.8))
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 60)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            appState.ui.showGenerationToast = false
                            appState.ui.generationToastMessage = nil
                        }
                    }
                }
            }
        }
        .animation(DS.Anim.smooth, value: appState.ui.showGenerationToast)
    }
    private var detailPaneToggleButton: some View {
        Button {
            withAnimation(DS.Anim.standard) {
                detailVisible.toggle()
            }
        } label: {
            Image(systemName: detailVisible ? "sidebar.right" : "sidebar.trailing")
                .font(.system(size: 20))
        }
        .help(detailVisible ? "Hide Detail Pane" : "Show Detail Pane")
        .accessibilityLabel(detailVisible ? "Hide Detail Pane" : "Show Detail Pane")
        .keyboardShortcut("d", modifiers: [.command])  // Cmd+D on macOS only (safe – iOS ignores)
    }

    // Cross-platform placement – trailing on iOS, primary (right-side) on macOS
    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarTrailing
        #else
        return .primaryAction  // Places items on the right in the window toolbar on macOS
        #endif
    }
    
    @ViewBuilder
    private var regularThreeColumnLayout: some View {
        #if os(macOS)
        // macOS: Custom stable HStack layout (avoids NavigationSplitView constraint issues).
        // Whether this can become NavigationSplitView is tracked by the Stage 0 macOS spike.
        stableThreeColumnLayout
        #else
        modernInspectorLayout
        #endif
    }

    #if os(macOS)
    // MARK: - macOS Stable Three-Column Layout (Native HSplitView)
    private let sidebarWidth: CGFloat = 85

    private var stableThreeColumnLayout: some View {
        HStack(spacing: 0) {
            // Left sidebar - fixed width
            if sidebarVisible {
                PowerPanelSelectorView(selected: $selectedPowerPanel)
                    .frame(width: sidebarWidth)
                    .background(Color(NSColor.windowBackgroundColor))

                Divider()
            }

            // Main content + Inspector using native split view
            if detailVisible {
                NativeSplitView(
                    leading: {
                        mainGenerationView
                            .frame(minWidth: 300)
                            .toolbar {
                                ToolbarItemGroup(placement: toolbarPlacement) { toolbarContent }
                            }
                    },
                    trailing: {
                        PowerPanelContentView(selected: selectedPowerPanel == .none ? .styles : selectedPowerPanel, onDescribeImage: { item in await self.describeImage(item: item) })
                            .frame(minWidth: 300, maxWidth: 900)
                    }
                )
            } else {
                mainGenerationView
                    .frame(minWidth: 400)
                    .frame(maxWidth: .infinity)
                    .toolbar {
                        ToolbarItemGroup(placement: toolbarPlacement) { toolbarContent }
                    }
            }
        }
        .animation(DS.Anim.quick, value: sidebarVisible)
        .animation(DS.Anim.quick, value: detailVisible)
    }
    #endif

    // MARK: - iOS 17+ (True Inspector)
    private var modernInspectorLayout: some View {
        NavigationSplitView(columnVisibility: $splitColumnVisibility) {
            // Left sidebar - fixed width, visibility controlled by columnVisibility
            PowerPanelSelectorView(selected: $selectedPowerPanel)
                .frame(width: 80)
                .background(Color.systemBackground)
                .navigationSplitViewColumnWidth(85)
        } detail: {
            mainGenerationView
                .toolbar {
                    ToolbarItemGroup(placement: toolbarPlacement) { toolbarContent }
                }
                .keyboardDoneButton()
                .inspector(isPresented: $detailVisible) {
                    PowerPanelContentView(selected: selectedPowerPanel == .none ? .styles : selectedPowerPanel, onDescribeImage: { item in await self.describeImage(item: item) })
                        .inspectorColumnWidth(min: 300, ideal: 600, max: 900)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { updateSplitVisibilityForInspector() }
        .onChange(of: detailVisible) { _ in updateSplitVisibilityForInspector() }
        .onChange(of: sidebarVisible) { _ in updateSplitVisibilityForInspector() }
    }

    private func updateSplitVisibilityForInspector() {
        withAnimation(DS.Anim.smooth) {
            splitColumnVisibility = sidebarVisible ? .doubleColumn : .detailOnly
        }
    }

   #if os(iOS)
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            toolbarContent
        }
    }
    #endif
    private var toolbarContent: some View {
        Group {
            jobsButton  // Always visible so the queue is reachable when idle (finding #10)
            billingButton
            // Undo/Redo removed from macOS toolbar - use Edit menu (Cmd+Z / Shift+Cmd+Z)
            helpMenuButton
            Button(action: { showGeneralOptions = true }) {
                Image(systemName: "gear")
            }
            .help("General Options")
            .accessibilityLabel("General Options")
            .accessibilityHint("Opens the general settings page.")
            detailPaneToggleButton
        }
    }

    /// Unified Help menu combining mode guide and app tour
    @ViewBuilder
    private var helpMenuButton: some View {
        Menu {
            Button {
                appState.presentedModal = .help(appState.settings.provider)
            } label: {
                Label("\(appState.settings.provider.rawValue) Guide", systemImage: "book")
            }

            Divider()

            Button {
                appState.presentedModal = .onboarding
            } label: {
                Label("App Tour", systemImage: "play.circle")
            }
        } label: {
            Image(systemName: "questionmark.circle")
                .symbolRenderingMode(.hierarchical)
        }
        .help("Help & Guides")
        .accessibilityLabel("Help Menu")
        .accessibilityHint("Opens help options including mode guide and app tour.")
    }

    /// Count of video jobs in progress or needing download (badge source).
    /// Terminal rows the user dismissed from the Jobs panel ("Remove" / "Clear
    /// Finished") don't count — only in-progress work always does.
    private var activeJobCount: Int {
        let dismissed = appState.ui.dismissedJobsPanelIDs
        return appState.historyState.history.flatMap { $0.allItems }.filter {
            let needsDownload = $0.videoUrl != nil && ($0.imagePath?.isEmpty ?? true)
            if $0.status?.isInProgress == true { return true }
            return needsDownload && !dismissed.contains($0.id.uuidString)
        }.count
    }

    @ViewBuilder
    private var jobsButton: some View {
        let count = activeJobCount
        Button {
            appState.presentedModal = .jobs
        } label: {
            Image(systemName: "film.stack")
                .symbolRenderingMode(.hierarchical)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.red, in: Circle())
                            .offset(x: 8, y: -8)
                    }
                }
        }
        .help(count > 0 ? "\(count) job(s) in progress; review pending approvals in Jobs" : "Jobs and pending approvals")
        .accessibilityLabel("Jobs and pending approvals")
    }

    @ViewBuilder
    private var billingButton: some View {
        if appState.settings.provider == .gemini {
            Button(action: openBillingConsole) {
                Image(systemName: "dollarsign.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Open Gemini Billing Console")
            .accessibilityLabel("Billing")
            .accessibilityHint("Opens the Gemini billing console in a browser.")
           
        } else if appState.settings.provider == .grok {
            Button(action: openGrokBillingConsole) {
                Image(systemName: "dollarsign.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .help("Open Grok Billing Console")
            .accessibilityLabel("Billing")
            .accessibilityHint("Opens the Grok billing console in a browser.")
           
        } else if appState.settings.provider == .aimlapi {
            Button(action: {
                openAIMLBillingConsole()
               
                // Silently refresh balance on click
                balanceFetchTask?.cancel()
                balanceFetchTask = Task {
                    do {
                        let balanceData = try await fetchBalance(apiKey: appState.settings.aimlapiKey)
                        if let balanceNum = balanceData["balance"] as? Double {
                            await MainActor.run {
                                aimlBalance = balanceNum
                            }
                        }
                    } catch {
                        Log.debug("AIMLAPI: Balance fetch failed (silent): \(error.localizedDescription)")
                        await MainActor.run { aimlBalance = nil }
                    }
                }
            }) {
                Text((aimlBalance != nil ? formatBalance(aimlBalance!) : "$") + (appState.ui.sessionSpendUSD > 0 ? String(format: "  ·  −$%.2f", appState.ui.sessionSpendUSD) : ""))
                    .font(DS.footnoteFont)
                    .kerning(-0.5)
                    .foregroundColor(colorScheme == .light ? .blue : .white)
                    .opacity(aimlBalance == nil ? 0.7 : 1.0) // Slightly dimmed $ for subtle feedback
            }
            .help(appState.ui.sessionSpendUSD > 0
                  ? String(format: "AI/ML API credits • $%.2f spent this session • Click to open billing console", appState.ui.sessionSpendUSD)
                  : "AI/ML API credits • Click to open billing console")
            .accessibilityLabel("AIML API Balance")
            .accessibilityHint("Shows credit balance. Opens billing console in browser.")
           
        } else {
            // ComfyUI and other local modes - no billing, hide button entirely
            EmptyView()
        }
    }
   
    // Add helper function to format balance with 3 significant figures and M/K suffix
    private func formatBalance(_ credits: Double) -> String {
// Log.debug("formatBalance input credits: \(credits)") // Debug print to verify input
        let formatter = NumberFormatter()
        formatter.minimumSignificantDigits = 3
        formatter.maximumSignificantDigits = 3
        formatter.roundingMode = .halfUp // Ensure consistent rounding
        formatter.usesSignificantDigits = true // Strictly enforce significant digits
       
        if credits >= 1_000_000 {
            let millions = credits / 1_000_000
            formatter.maximumFractionDigits = 1 // Limit to 1 decimal for M
            let result = formatter.string(from: NSNumber(value: millions)) ?? String(format: "%.1f", millions)
            return "\(result)M"
        } else if credits >= 1_000 {
            let thousands = credits / 1_000
            formatter.maximumFractionDigits = 1 // Limit to 1 decimal for K
            let result = formatter.string(from: NSNumber(value: thousands)) ?? String(format: "%.1f", thousands)
            return "\(result)K"
        } else {
            formatter.maximumFractionDigits = 0 // No decimals for small numbers
            let result = formatter.string(from: NSNumber(value: credits)) ?? String(format: "%.0f", credits)
            return result
        }
    }
    private func openBillingConsole() {
        if let url = URL(string: "https://console.cloud.google.com/billing") {
            PlatformBrowser.open(url: url)
        }
    }
    private func openGrokBillingConsole() {
        if let url = URL(string: "https://console.x.ai") {
            PlatformBrowser.open(url: url)
        }
    }
    private func openAIMLBillingConsole() {
        // The same billing console the credit-exhaustion copy and the MCP insufficient_credits
        // payload link to; one spelling, in AIMLEndpoints.
        if let url = URL(string: AIMLEndpoints.billingConsoleURLString) {
            PlatformBrowser.open(url: url)
        }
    }
    private func validateBatchFileBookmark() {
        guard let bookmarkData = AppStorageContext.defaults.data(forKey: "batchFileBookmark") else {
            Log.debug("VALIDATE: No bookmark found – clearing state silently")
            // Do NOT clear here if no bookmark – this is normal for unsaved/new editors
            return
        }
        
        do {
            var isStale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: options, bookmarkDataIsStale: &isStale)
            
            let accessing = resolvedURL.startAccessingSecurityScopedResource()
            defer { if accessing { resolvedURL.stopAccessingSecurityScopedResource() } }
            
            #if os(macOS)
            // macOS: Strict existence check (reliable)
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                appState.batchFilePath = resolvedURL.path
                Log.debug("VALIDATE: File exists on macOS – path updated")
            } else {
                Log.debug("VALIDATE: File missing on macOS – clearing bookmark/state")
                clearBatchFile()
            }
            #else
            // iOS: Skip unreliable existence check – trust bookmark resolution + actual loads
            appState.batchFilePath = resolvedURL.path
            Log.debug("VALIDATE: Path updated on iOS (skipped existence check)")
            #endif
            
            // Refresh stale bookmark if needed
            if isStale {
                Log.debug("VALIDATE: Bookmark stale – refreshing")
                #if os(macOS)
                let refreshOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                #else
                let refreshOptions: URL.BookmarkCreationOptions = .minimalBookmark
                #endif
                
                if let freshBookmark = try? resolvedURL.bookmarkData(options: refreshOptions) {
                    AppStorageContext.defaults.set(freshBookmark, forKey: "batchFileBookmark")
                    Log.debug("VALIDATE: Stale bookmark refreshed")
                }
            }
        } catch {
            Log.debug("VALIDATE: Bookmark resolution failed – clearing: \(error.localizedDescription)")
            clearBatchFile()
        }
    }
    func clearBatchFile() {
        // Stop any active file monitoring (macOS only)
        #if os(macOS)
        fileMonitor?.cancel()
        fileMonitor = nil
        #endif
        
        // Remove persistent bookmark
        AppStorageContext.defaults.removeObject(forKey: "batchFileBookmark")
        
        // Clear shared state
        appState.batchFilePath = ""
        appState.batchFileURL = nil
        appState.batchPrompts = []
    
        
        // Trigger editor reload/clear (even if power panel is open)
        appState.batchFileVersion += 1

        
        // Reset range pickers in main view
        batchStartIndex = 1
        batchEndIndex = 1
    }
   
    private func prettyPrintJSON(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return String(data: prettyData, encoding: .utf8)
        } catch {
            return nil
        }
    }
    // In ContentView.swift
    private func handleEditBatchFile() {
        withAnimation(DS.Anim.standard) {
            selectedPowerPanel = .batch
        }
    }
    
#if os(macOS)
    // Helper function to open a file in TextEdit
    private func openInTextEdit(url: URL) {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
                Log.debug("TextEdit not found")
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { runningApp, error in
                if let error = error {
                    Log.debug("Error opening file: \(error.localizedDescription)")
                }
            }
        }
    // Helper function to create a new file and open it in TextEdit
    private func createAndOpenNewFileInTextEdit() {
            PlatformFileSaver.presentSavePanel(
                suggestedName: "batch.txt",
                allowedTypes: [UTType.text],
                callback: { result in
                    switch result {
                    case .success(let url):
                        do {
                            // Write an empty file to the chosen location
                            try "".write(to: url, atomically: true, encoding: .utf8)
                            // Create and store bookmark
                            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope])
                            AppStorageContext.defaults.set(bookmarkData, forKey: "batchFileBookmark")
                            appState.batchFilePath = url.path
                            appState.batchFileURL = url
                            appState.batchPrompts = []
                            // Open the new file in TextEdit
                            openInTextEdit(url: url)
                            // Monitor file for changes
                            monitorFileChanges(at: url)
                        } catch {
                            errorItem = AlertError(message: "Failed to create new batch file: \(error.localizedDescription)", fullMessage: nil)
                        }
                    case .failure(let error):
                        let nsError = error as NSError
                        if nsError.code == NSUserCancelledError {
                            return  // User cancelled — perfect, do nothing
                        }
                       
                        Log.debug("Batch file selection failed: \(error)")
                        errorItem = AlertError(message: "Failed to select batch file: \(error.localizedDescription)", fullMessage: nil)
                    }
                }
            )
        }
        // Helper function to monitor file changes
    internal func monitorFileChanges(at url: URL) {
            // Cancel any existing monitor
            fileMonitor?.cancel()
            fileMonitor = nil
            guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
                errorItem = AlertError(message: "Failed to monitor batch file for changes.", fullMessage: nil)
                return
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileHandle.fileDescriptor,
                eventMask: [.write, .delete, .rename],
                queue: .main
            )
            source.setEventHandler {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        if !FileManager.default.fileExists(atPath: url.path) {
                            // File was deleted or moved; stop monitoring and clear batch file
                            self.fileMonitor?.cancel()
                            self.fileMonitor = nil
                            self.clearBatchFile()
                            NotificationCenter.default.post(name: .batchFileUpdated, object: nil)
                            return
                        }
                        let content = try String(contentsOf: url, encoding: .utf8)
                        appState.batchPrompts = content.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        NotificationCenter.default.post(name: .batchFileUpdated, object: nil)
                    } catch {
                        errorItem = AlertError(message: "Failed to reload batch file: \(error.localizedDescription)", fullMessage: nil)
                    }
                }
            }
            source.setCancelHandler {
                try? fileHandle.close()
            }
            source.resume()
            fileMonitor = source // Store the source to keep it alive
            AppStorageContext.defaults.set(url.path, forKey: "monitoredBatchFilePath")
        }
        #endif

    struct ComfyUIResponsibilityWarning: View {
        @AppStorage("comfyUIWarningAccepted", store: AppStorageContext.defaults) private var accepted = false
        @AppStorage("comfyUIWarningDeclined", store: AppStorageContext.defaults) private var declined = false
        @State private var hasAcceptedTerms = false
       
        var onComplete: () -> Void
       
        var body: some View {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 24) {
                    // MARK: - Icon
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                   
                    // MARK: - Title
                    VStack(spacing: 12) {
                        Text("ComfyUI Mode – Important Warning")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                       
                        Text("ComfyUI runs entirely on your own server with models you control.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                   
                    // MARK: - Warning Text
                    Text(warningText)
                        .font(DS.prominentFont)
                        .lineSpacing(4)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                   
                    // MARK: - Checkbox
                    HStack {
                        Image(systemName: hasAcceptedTerms ? "checkmark.square.fill" : "square")
                            .foregroundColor(hasAcceptedTerms ? .accentColor : .secondary)
                            .font(.title2)
                            .onTapGesture { hasAcceptedTerms.toggle() }
                       
                        Text("I accept responsibility for all content")
                            .font(.system(size: 15, weight: .medium))
                            .onTapGesture { hasAcceptedTerms.toggle() }
                       
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .contentShape(Rectangle())
                    .onTapGesture { hasAcceptedTerms.toggle() }
                   
                    // MARK: - Buttons Side-by-Side
                    HStack(spacing: 16) {
                        Button("Decline") {
                            declined = true
                            onComplete()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.red)
                        .keyboardShortcut(.cancelAction)
                       
                        Button("Enable ComfyUI") {
                            if hasAcceptedTerms {
                                accepted = true
                                onComplete()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(hasAcceptedTerms ? .blue : .gray)  // ← Dynamic tint!
                        .disabled(!hasAcceptedTerms)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity)
            .background(Color.systemBackground)
            .cornerRadius(DS.Radius.modal)
            .shadow(radius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.modal)
                    .stroke(Color.separator.opacity(0.3), lineWidth: 1)
            )
            .interactiveDismissDisabled()
            .zIndex(11)
        }
       
        private var warningText: AttributedString {
            let raw = """
            Apple requires apps to prevent harmful content, including:
            • **Nudity / sexually explicit material**
            • **Violence, gore, hate symbols**
            • **Child sexual abuse material** (zero tolerance)
            
            A prompt filter is active, but advanced workflows or custom models may bypass it.
            
            **You are solely responsible for all content generated in ComfyUI mode.**
            """
            return (try? AttributedString(markdown: raw, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(raw)
        }
    }


}
//DEBUG Reset Privacy notices
extension ContentView {
    func resetPrivacyNoticesForTesting() {
        let services: [PrivacyService] = [.gemini, .grok, .aimlapi, .imgbb]
        for service in services {
                let key = "dontShow\(service.rawValue.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: " ", with: ""))Privacy"
                Log.debug("Resetting UserDefaults key: \(key)")
                AppStorageContext.defaults.set(false, forKey: key)
                // Synchronize to ensure changes are written
                AppStorageContext.defaults.synchronize()
        }
        Log.debug("Privacy notice flags reset for testing.")
       
       
    }
}
