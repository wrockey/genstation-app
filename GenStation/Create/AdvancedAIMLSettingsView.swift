// AdvancedAIMLSettingsView.swift
import SwiftUI
 
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import GenStationCore
 
struct CardView<Content: View>: View {
    let title: String
    let content: Content
 
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content()
    }
 
    var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .padding(.bottom, 4)
                }
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.systemBackground)
            .cornerRadius(DS.Radius.standard)
            .shadow(radius: 2)
        }
    }
 
 
struct AdvancedAIMLSettingsView: View {
    let model: CatalogModel
    @Binding var params: ModelParameters
    let isVideo: Bool
    var showDoneButton: Bool = true  // Set to false when embedded in power panel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    // State for custom payload and endpoint
    @State private var customPayload: String = """
    {
        "model": "",
        "prompt": "[prompt]"
    }
    """
    @State private var customEndpoint: String = ""
    @State private var localError: AlertError? // For local alert handling
    @State private var initialPayload: String? // Track initial payload for unsaved changes
    @State private var initialEndpoint: String? // Track initial endpoint for unsaved changes
    @State private var showSaveWarning: Bool = false // For unsaved changes alert
 
    init(model: CatalogModel, params: Binding<ModelParameters>, isVideo: Bool, showDoneButton: Bool = true) {
        self.model = model
        self._params = params
        self.isVideo = isVideo
        self.showDoneButton = showDoneButton
    }
   
    var body: some View {
#if os(iOS)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Model Parameters Card (with Done button inside)
                    modelSpecificParamsSectionWithDone

                    // Show all models toggle (only when standalone, not embedded in power panel)
                    if showDoneButton {
                        showAllModelsSection
                    }

                    // Custom Request Configuration
                    customPayloadSection
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("Advanced Settings")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .background(Color(.systemGroupedBackground))
            .alert(item: $localError) { error in
                Alert(
                    title: Text("Operation Failed"),
                    message: error.message.isEmpty ? nil : Text(error.message),
                    primaryButton: .default(Text("OK")) { localError = nil },
                    secondaryButton: .default(Text("Reset")) {
                        resetToDefault()
                        localError = nil
                    }
                )
            }
            .alert("Save changes to custom request payload?", isPresented: $showSaveWarning) {
                Button("Save") {
                    saveCustomPayload()
                    dismiss()
                }
                Button("Discard", role: .cancel) {
                    dismiss()
                }
            }
            .onAppear {
                updatePayloadAndEndpoint()
                initialPayload = appState.settings.customAIMLPayload
                initialEndpoint = appState.settings.customAIMLEndpoint
            }
            .onChange(of: appState.settings.selectedAIMLModel) { _ in
                updatePayloadAndEndpoint()
            }
            .onChange(of: appState.settings.task) { _ in
                updatePayloadAndEndpoint()
            }
            .onChange(of: appState.ui.imageSlots) { _ in
                updatePayloadAndEndpoint()
            }
            .onChange(of: params) { _ in
                updatePayloadAndEndpoint()  // Update JSON on param changes from model view
            }
            .onDisappear {
                appState.errorItem = nil
            }
        }
#elseif os(macOS)
        VStack(spacing: 0) {
            Text("Advanced Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 16)
                .padding(.bottom, 8)
           
            ScrollView {
                VStack(spacing: 16) {
                    // Model Parameters Card (with Done button inside)
                    modelSpecificParamsSectionWithDone

                    // Show all models toggle (only when standalone, not embedded in power panel)
                    if showDoneButton {
                        showAllModelsSection
                    }

                    // Custom Request Configuration
                    customPayloadSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
//        .frame(minWidth: 550, idealWidth: 650, maxWidth: 650, minHeight: 400, idealHeight: 600)
        .alert(item: $localError) { error in
            Alert(
                title: Text("Operation Failed"),
                message: error.message.isEmpty ? nil : Text(error.message),
                primaryButton: .default(Text("OK")) { localError = nil },
                secondaryButton: .default(Text("Reset")) {
                    resetToDefault()
                    localError = nil
                }
            )
        }
        .alert("Save changes to custom request payload? This will override all other generation settings", isPresented: $showSaveWarning) {
            Button("Save") {
                saveCustomPayload()
                dismiss()
            }
            Button("Discard", role: .cancel) {
                dismiss()
            }
        }
        .onAppear {
            updatePayloadAndEndpoint()
            initialPayload = appState.settings.customAIMLPayload
            initialEndpoint = appState.settings.customAIMLEndpoint
        }
        .onChange(of: appState.settings.selectedAIMLModel) { _ in
            updatePayloadAndEndpoint()
        }
        .onChange(of: appState.settings.task) { _ in
            updatePayloadAndEndpoint()
        }
        .onChange(of: appState.ui.imageSlots) { _ in
            updatePayloadAndEndpoint()
        }
        .onChange(of: params) { _ in
            updatePayloadAndEndpoint()  // Update JSON on param changes from model view
        }
        .onDisappear {
            appState.errorItem = nil
        }
#endif
    }
 
    // MARK: - Model Parameters + Done Button
    @ViewBuilder
    private var modelSpecificParamsSectionWithDone: some View {
        CardView(title: "") {
            VStack(alignment: .leading, spacing: 12) {
                if let model = Catalog.model(for: appState.settings.selectedAIMLModel) {
                    if isVideo, let guide = VideoWorkflowGuide.guide(for: model.id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(guide.title).font(.headline)
                            Text(guide.summary).font(.subheadline).foregroundStyle(.secondary)
                            Text(model.maxInputImages > 1 ? "Image 1: first frame · Image 2: optional last frame" : model.requiresInputImage ? "Image 1: required first frame" : "Text prompt only")
                                .font(.caption).foregroundStyle(.secondary)
                            if let issue = VideoRequestPolicy.parameterIssue(model: model, params: params, imageCount: appState.ui.imageSlots.count) {
                                Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                    // The only parameter UI there is, since Stage 2 Task 11 deleted `Params View/`.
                    // An id the catalog does not know now falls to the `else` below and is told so,
                    // instead of rendering an empty table as a blank card.
                    ParamDescriptorView(
                        descriptors: ParamCatalog.descriptors(for: model),
                        params: $params,
                        context: ParamCatalog.context(for: model, hasInputImages: !appState.ui.imageSlots.isEmpty)
                    )
                } else {
                    Text("No advanced parameters for this model")
                        .foregroundColor(.secondary)
                }
 
                // Done button placed at the bottom of the card (only when shown as sheet)
                if showDoneButton {
                    HStack {
                        Spacer()
                        Button("Done") {
                            if hasUnsavedChanges() {
                                showSaveWarning = true
                            } else {
                                dismiss()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
#if os(iOS)
                        .tint(.blue)
#endif
                    }
                }
            }
        }
    }
 
    private var showAllModelsSection: some View {
        CardView(title: "") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Only supported image and video models are available in this release. Specialized and unverified operations are disabled; existing history remains available.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }
        }
    }

    @ViewBuilder
    private var customPayloadSection: some View {
        CardView(title: "Custom Request Configuration") {
            ParameterRow(title: "Endpoint URL", help: "Override the API endpoint URL (e.g., https://api.aimlapi.com/v1/images/generations)") {  // endpoint-boundary: informational docs link, not a request
                TextField("Enter endpoint URL", text: $customEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .accessibilityLabel("Custom Endpoint URL")
            }
           
            ParameterRow(title: "Request Payload", help: "Edit the JSON payload (images shown as placeholders, e.g., [image_slot_1])") {
                TextEditor(text: $customPayload)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 100, maxHeight: 200)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.standard).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .accessibilityLabel("Custom Request Payload")
            }
           
            HStack {
                Button("Set to Current") {
                    resetToDefault()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Creates a JSON based on the current generation settings in the configuration section")
                .help("Set to current generation settings")
               
                Button("Clear") {
                    customPayload = ""
                    customEndpoint = ""
                    // Do not save to appState.settings yet
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Clears the custom JSON in order to generate based on current configuration section settings")
                .help("Clears the custom JSON")
               
                Button("Save") {
                    saveCustomPayload()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Saves the custom JSON payload and endpoint for use in generation")
                .help("Save custom JSON and endpoint")
            }
        }
    }
   
    private func hasUnsavedChanges() -> Bool {
        let normalizedCurrentPayload = normalizeJSON(customPayload)
        let normalizedInitialPayload = normalizeJSON(initialPayload ?? computeDefaultPayload() ?? """
        {
            "model": "\(appState.settings.selectedAIMLModel)",
            "prompt": "[prompt]"
        }
        """)
        let payloadChanged = normalizedCurrentPayload != normalizedInitialPayload
        let endpointChanged = customEndpoint != (initialEndpoint ?? computeDefaultEndpoint() ?? "")
        return payloadChanged || endpointChanged
    }
   
    private func normalizeJSON(_ json: String?) -> String? {
        guard let json = json, let data = json.data(using: .utf8) else { return nil }
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            let normalizedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
            return String(data: normalizedData, encoding: .utf8)
        } catch {
            Log.debug("normalizeJSON: Failed to normalize JSON: \(error.localizedDescription), input: \(json)")
            return json
        }
    }
   
    private func computeDefaultEndpoint() -> String? {
        let id = appState.settings.selectedAIMLModel

        // The empty selection is the ONLY input the fallback below `if let enhanced` ever received,
        // and it is not equivalent to `Catalog.resolve("")`: the synthesized row for "" reports
        // `isVideo == false`, so `resolve` would prefill the image URL even in video mode. Both
        // branches of the old fallback collapse to a named constant for an empty id —
        // `videoEndpoint(modelID: "")` returns `videoGenerationsURL` (AIMLEndpoints.swift:75, the
        // `parts.count >= 2` guard), and `imageEndpoint(supportsMask: false, ...)` returns
        // `imagesGenerationsURL` for either value of `hasInputImages` (`:62`). So this preserves
        // the mode-shaped prefill exactly, in two lines instead of twelve.
        guard !id.isEmpty else {
            return isVideo ? AIMLEndpoints.videoGeneration : AIMLEndpoints.imageGeneration
        }

        // For every non-empty id, `resolve` reproduces the old `if let enhanced` branch: a catalog
        // row carries its own generationEndpoint, and an id the catalog does not know synthesizes
        // the same per-provider video URL / imageGeneration URL the registry's fallback did.
        return Catalog.resolve(id).generationEndpoint
    }
   
    private func computeDefaultPayload() -> String? {
        // Unreachable fallback deleted: `enhancedModelFor` only returned nil for an empty id, and
        // `resolve("")` synthesizes a row whose empty table encodes to the same model+prompt body.
        // Only the formatting differs — JSONSerialization sorted+pretty-printed instead of the
        // hand-indented literal.
        let model = Catalog.resolve(appState.settings.selectedAIMLModel)

        var bodyDict: [String: Any] = [
            "model": appState.settings.selectedAIMLModel,
            "prompt": "[prompt]"
        ]
        
        // Add image placeholders only for I2I or I2V models AND not in binary mode
        if model.isI2I && !appState.ui.imageSlots.isEmpty && appState.settings.imageSubmissionMethod != .binary {
            if model.acceptsMultiImages {
                bodyDict[model.imageInputParam] = appState.ui.imageSlots.enumerated().map { "[image_slot_\($0.offset + 1)]" }
            } else {
                bodyDict[model.imageInputParam] = "[image_slot_1]"
            }
        }
        
        // Add model-specific parameters from the model's descriptor table
        let modelParams = ParamEncoder.encode(
            ParamCatalog.descriptors(for: model),
            params: params,
            context: ParamCatalog.context(for: model, hasInputImages: !appState.ui.imageSlots.isEmpty)
        )
        bodyDict.merge(modelParams) { (_, new) in new }
        
        if let newData = try? JSONSerialization.data(withJSONObject: bodyDict, options: [.prettyPrinted, .sortedKeys]),
           let newPayload = String(data: newData, encoding: .utf8) {
            return newPayload
        }
        return nil
    }
   
    private func updatePayloadAndEndpoint() {
        customPayload = appState.settings.customAIMLPayload ?? computeDefaultPayload() ?? """
        {
            "model": "\(appState.settings.selectedAIMLModel)",
            "prompt": "[prompt]"
        }
        """
        customEndpoint = appState.settings.customAIMLEndpoint ?? computeDefaultEndpoint() ?? ""
        if !isVideo {
            updateImagePlaceholders()
        }
    }
   
    private func updateImagePlaceholders() {
        // Skip if in binary mode, as images are handled as form files, not placeholders
        if appState.settings.imageSubmissionMethod == .binary {
            // NEW: Actively remove any existing image placeholders in binary mode
            guard let data = customPayload.data(using: .utf8) else { return }
            var bodyDict: [String: Any]
            do {
                bodyDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            } catch {
                return
            }
            
            let imageKey = model.imageInputParam.isEmpty ? "image" : model.imageInputParam
            bodyDict.removeValue(forKey: imageKey)
            
            do {
                let newData = try JSONSerialization.data(withJSONObject: bodyDict, options: [.prettyPrinted, .sortedKeys])
                if let newPayload = String(data: newData, encoding: .utf8) {
                    customPayload = newPayload
                }
            } catch {
                // Silent fail, as it's cleanup
            }
            return
        }

        // Rest unchanged: add/remove placeholders for non-binary
        guard let data = customPayload.data(using: .utf8) else {
            localError = AlertError(
                message: "Failed to encode payload as UTF-8.",
                fullMessage: "Please check the text in the JSON payload."
            )
            return
        }

        var bodyDict: [String: Any]
        do {
            bodyDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            localError = AlertError(
                message: "Invalid JSON format.",
                fullMessage: "JSON parsing error: \(error.localizedDescription). Please correct the JSON syntax.\nInput: \(customPayload)"
            )
            return
        }
        
        let imageKey = model.imageInputParam.isEmpty ? "image" : model.imageInputParam
        
        if !model.isI2I || appState.ui.imageSlots.isEmpty {
            bodyDict.removeValue(forKey: imageKey)
        } else {
            if model.acceptsMultiImages {
                bodyDict[imageKey] = appState.ui.imageSlots.enumerated().map { "[image_slot_\($0.offset + 1)]" }
            } else {
                bodyDict[imageKey] = "[image_slot_1]"
            }
        }
        
        do {
            let newData = try JSONSerialization.data(withJSONObject: bodyDict, options: [.prettyPrinted, .sortedKeys])
            if let newPayload = String(data: newData, encoding: .utf8) {
                customPayload = newPayload
                localError = nil
                appState.errorItem = nil
            } else {
                localError = AlertError(
                    message: "Failed to encode updated JSON.",
                    fullMessage: "Please check the payload structure."
                )
            }
        } catch {
            localError = AlertError(
                message: "Failed to serialize JSON.",
                fullMessage: "Serialization error: \(error.localizedDescription). Please check the payload structure.\nBody: \(bodyDict)"
            )
        }
    }
   
    private func resetToDefault() {
        appState.settings.customAIMLPayload = nil
        appState.settings.customAIMLEndpoint = nil
        updatePayloadAndEndpoint()
        initialPayload = customPayload
        initialEndpoint = customEndpoint
    }
   
    private func saveCustomPayload() {
        let sanitizedPayload = sanitizeJSON(customPayload)
        if sanitizedPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appState.settings.customAIMLPayload = nil
            appState.settings.customAIMLEndpoint = nil
            customEndpoint = ""
            initialPayload = nil
            initialEndpoint = nil
            localError = nil
            appState.errorItem = nil
            return
        }
        
        guard let data = sanitizedPayload.data(using: .utf8) else {
            localError = AlertError(
                message: "Failed to encode payload as UTF-8.",
                fullMessage: "Please check the text in the JSON payload. Input: \(sanitizedPayload)"
            )
            return
        }
        
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            let defaultPayload = computeDefaultPayload() ?? ""
            let defaultEndpoint = computeDefaultEndpoint() ?? ""
            appState.settings.customAIMLPayload = (sanitizedPayload == defaultPayload) ? nil : sanitizedPayload
            appState.settings.customAIMLEndpoint = (customEndpoint == defaultEndpoint) ? nil : (customEndpoint.isEmpty ? nil : customEndpoint)
            initialPayload = appState.settings.customAIMLPayload
            initialEndpoint = appState.settings.customAIMLEndpoint
            localError = nil
            appState.errorItem = nil
        } catch {
            localError = AlertError(
                message: "Invalid JSON format.",
                fullMessage: "JSON validation error: \(error.localizedDescription). Please correct the JSON syntax.\nInput: \(sanitizedPayload)"
            )
        }
    }
   
    private func sanitizeJSON(_ jsonString: String) -> String {
        var sanitized = jsonString
            .replacingOccurrences(of: "\u{201C}", with: "\"") // Left curly quote
            .replacingOccurrences(of: "\u{201D}", with: "\"") // Right curly quote
        sanitized = sanitized.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = sanitized.data(using: .utf8) {
            do {
                var jsonObject = try JSONSerialization.jsonObject(with: data)
                jsonObject = escapeQuotesInJSON(jsonObject)
                if let newData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
                   let newString = String(data: newData, encoding: .utf8) {
                    return newString
                }
            } catch {
                return sanitized
            }
        }
        return sanitized
    }
   
    private func escapeQuotesInJSON(_ json: Any) -> Any {
        if let dict = json as? [String: Any] {
            var newDict: [String: Any] = [:]
            for (key, value) in dict {
                if let stringValue = value as? String {
                    newDict[key] = stringValue.replacingOccurrences(of: "\"", with: "\\\"")
                } else if let arrayValue = value as? [Any] {
                    newDict[key] = arrayValue.map { escapeQuotesInJSON($0) }
                } else if let dictValue = value as? [String: Any] {
                    newDict[key] = escapeQuotesInJSON(dictValue)
                } else {
                    newDict[key] = value
                }
            }
            return newDict
        } else if let array = json as? [Any] {
            return array.map { escapeQuotesInJSON($0) }
        } else if let string = json as? String {
            return string.replacingOccurrences(of: "\"", with: "\\\"")
        }
        return json
    }
   
    @ViewBuilder
    private func ParameterRow<Content: View>(title: String, help: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                content()
                Spacer()
            }
        }
        .help(help)
    }
}
