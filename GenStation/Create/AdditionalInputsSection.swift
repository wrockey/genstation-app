// AdditionalInputsSection.swift
// Collapsible section for additional ComfyUI input bindings

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import PhotosUI
#endif
import GenStationCore

// MARK: - Additional Inputs Section

struct AdditionalInputsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var isExpanded: Bool = false

    private var modeAccent: Color {
        appState.settings.provider.liquidAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button(action: { withAnimation(DS.Anim.quick) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Image(systemName: "plus.square.dashed")
                        .font(.title3)
                        .foregroundColor(modeAccent)

                    Text("Additional Inputs")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    if !appState.generation.additionalInputs.isEmpty {
                        Text("\(appState.generation.additionalInputs.count)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(modeAccent.opacity(0.2))
                            .foregroundColor(modeAccent)
                            .cornerRadius(DS.Radius.standard)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            // Expandable content
            if isExpanded {
                VStack(spacing: 12) {
                    if appState.generation.additionalInputs.isEmpty {
                        emptyStateView
                    } else {
                        ForEach($appState.generation.additionalInputs) { $input in
                            AdditionalInputCard(input: $input, onDelete: { deleteInput(input) })
                        }
                    }

                    addInputButtons
                }
                .padding(.top, 8)
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No additional inputs configured")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Add extra prompts or images for ControlNet, IPAdapter, negative prompts, etc.")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(DS.Radius.panel)
    }

    // MARK: - Add Input Buttons

    private var addInputButtons: some View {
        let hasAnyNodes = !appState.generation.allNodes.isEmpty
        let showAll = appState.settings.comfyShowAllNodes
        let canAddText = showAll ? hasAnyNodes : !appState.generation.textCompatibleNodes.isEmpty
        let canAddImage = showAll ? hasAnyNodes : !appState.generation.imageCompatibleNodes.isEmpty

        return HStack(spacing: 12) {
            Button(action: addTextInput) {
                Label("Add Text Input", systemImage: "text.alignleft")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .disabled(!canAddText)
            .help(!canAddText
                  ? "No text-compatible nodes found in workflow"
                  : "Add an additional text input (e.g., negative prompt)")

            Button(action: addImageInput) {
                Label("Add Image Input", systemImage: "photo")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .disabled(!canAddImage)
            .help(!canAddImage
                  ? "No image-compatible nodes found in workflow"
                  : "Add an additional image input (e.g., ControlNet)")

            Spacer()
        }
    }

    // MARK: - Actions

    private func addTextInput() {
        let newInput = AdditionalInput(inputType: .text)
        appState.generation.additionalInputs.append(newInput)
    }

    private func addImageInput() {
        let newInput = AdditionalInput(inputType: .image)
        appState.generation.additionalInputs.append(newInput)
    }

    private func deleteInput(_ input: AdditionalInput) {
        // Clean up image data if this was an image input
        if input.inputType == .image {
            appState.generation.additionalInputImages.removeValue(forKey: input.id)
        }
        appState.generation.additionalInputs.removeAll { $0.id == input.id }
    }
}

// MARK: - Additional Input Card

struct AdditionalInputCard: View {
    @Binding var input: AdditionalInput
    let onDelete: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var isEditingName: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var showImagePicker: Bool = false

    private var cardGlassBackground: some View {
        Group {
            Color.clear.background(.thinMaterial)
        }
    }

    private var compatibleNodes: [NodeInfo] {
        // Get base node list - all nodes or filtered by type
        let baseNodes: [NodeInfo]
        if appState.settings.comfyShowAllNodes {
            baseNodes = appState.generation.allNodes
        } else {
            baseNodes = appState.generation.compatibleNodes(for: input.inputType)
        }

        // Filter out nodes already used as primary prompt or output
        let excludedNodeIDs: Set<String> = [
            appState.generation.comfyPromptNodeID,
            appState.generation.comfyOutputNodeID
        ].filter { !$0.isEmpty }.reduce(into: Set<String>()) { $0.insert($1) }

        return baseNodes.filter { !excludedNodeIDs.contains($0.id) }
    }

    private var selectedNode: NodeInfo? {
        // Look in compatible nodes first, then fall back to all nodes
        compatibleNodes.first { $0.id == input.boundNodeID }
            ?? appState.generation.allNodes.first { $0.id == input.boundNodeID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: type badge, name, delete button
            headerRow

            // Node picker
            nodePickerRow

            // Value input (text area or image drop zone)
            if input.inputType == .text {
                textValueInput
            } else {
                imageValueInput
            }
        }
        .padding(14)
        .background(cardGlassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            // Type badge
            Label(input.inputType.rawValue, systemImage: input.inputType.icon)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(input.inputType == .text ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                .foregroundColor(input.inputType == .text ? .blue : .green)
                .cornerRadius(DS.Radius.small)

            // Editable name
            if isEditingName {
                TextField("Name", text: $input.displayName)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: 200)
                    .onSubmit { isEditingName = false }
            } else {
                Text(input.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .onTapGesture { isEditingName = true }
            }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Remove this input")
        }
    }

    // MARK: - Node Picker Row

    private var nodePickerRow: some View {
        HStack(spacing: 8) {
            Text("Node:")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            if compatibleNodes.isEmpty {
                Text("No compatible nodes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                Menu {
                    ForEach(compatibleNodes) { node in
                        Button {
                            input.boundNodeID = node.id
                            // Auto-update display name if still default
                            if input.displayName.hasPrefix("Input ") {
                                input.displayName = node.classType ?? "Node \(node.id)"
                            }
                            // Pre-populate text value with existing node content
                            if input.inputType == .text {
                                input.textValue = extractTextFromNode(nodeID: node.id)
                            }
                        } label: {
                            HStack {
                                Text(node.label)
                                if node.id == input.boundNodeID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedNode?.label ?? "Select node...")
                            .font(.caption)
                            .foregroundColor(selectedNode == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(DS.Radius.small)
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    // MARK: - Text Value Input

    private var textValueInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Value:")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: Binding(
                get: { input.textValue ?? "" },
                set: { input.textValue = $0 }
            ))
            .font(.system(size: 13, design: .monospaced))
            .frame(minHeight: 60, maxHeight: 120)
            .padding(8)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(DS.Radius.standard)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.standard)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .disabled(input.boundNodeID.isEmpty)
        .opacity(input.boundNodeID.isEmpty ? 0.5 : 1.0)
    }

    // MARK: - Image Value Input

    private var currentImage: AdditionalInputImage? {
        appState.generation.additionalInputImages[input.id]
    }

    private var imageValueInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail area with drop zone
            ZStack {
                if let imageData = currentImage, let thumbnail = imageData.thumbnail {
                    Image(platformImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 6, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 120)
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title2)
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("Drop image here")
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                        )
                }

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.1))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isDropTargeted ? Color.green : Color.secondary.opacity(0.2),
                        lineWidth: isDropTargeted ? 2 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
            .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isDropTargeted) { providers in
                handleImageDrop(providers: providers)
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    showImageFilePicker()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .help("Browse for image")

                Button {
                    pasteImageFromClipboard()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .help("Paste from clipboard")

                #if os(iOS)
                Button {
                    showImagePicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
                .help("Choose from Photos")
                #endif

                Spacer()

                if currentImage?.thumbnail != nil {
                    Button {
                        clearImage()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Clear image")
                }
            }
        }
        .disabled(input.boundNodeID.isEmpty)
        .opacity(input.boundNodeID.isEmpty ? 0.5 : 1.0)
        #if os(iOS)
        .sheet(isPresented: $showImagePicker) {
            PHPickerWrapper { result in
                handlePhotosPickerResult(result)
            }
        }
        #endif
    }

    #if os(iOS)
    private func handlePhotosPickerResult(_ result: PHPickerResult?) {
        guard let result = result else { return }
        result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
            guard let data = data, error == nil else { return }
            guard let platformImage = PlatformImage(data: data) else { return }
            DispatchQueue.main.async {
                setImage(platformImage, from: data)
            }
        }
    }
    #endif

    // MARK: - Image Handling

    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, error in
                guard let url = url, error == nil else { return }
                let didStart = url.startAccessingSecurityScopedResource()
                DispatchQueue.main.async {
                    loadImageFromURL(url)
                }
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return true
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                guard let data = data, error == nil else { return }
                guard let platformImage = PlatformImage(data: data) else { return }
                DispatchQueue.main.async {
                    setImage(platformImage, from: data)
                }
            }
            return true
        }
        return false
    }

    private func showImageFilePicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            loadImageFromURL(url)
        }
        #elseif os(iOS)
        PlatformFilePicker.presentOpenPanel(allowedTypes: [.image], allowsMultiple: false, canChooseDirectories: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadImageFromURL(url)
            case .failure:
                break
            }
        }
        #endif
    }

    private func pasteImageFromClipboard() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png), let image = PlatformImage(data: data) {
            setImage(image, from: data)
        } else if let data = pasteboard.data(forType: .tiff), let image = PlatformImage(data: data) {
            setImage(image, from: data)
        } else if let items = pasteboard.pasteboardItems {
            for item in items {
                if let urlString = item.string(forType: .fileURL),
                   let url = URL(string: urlString) {
                    loadImageFromURL(url)
                    return
                }
            }
        }
        #elseif os(iOS)
        let pasteboard = UIPasteboard.general
        if let data = pasteboard.data(forPasteboardType: "public.png"),
           let image = PlatformImage(data: data) {
            setImage(image, from: data)
        } else if let image = pasteboard.image {
            setImage(image, from: image.pngData())
        }
        #endif
    }

    private func loadImageFromURL(_ url: URL) {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            guard let image = PlatformImage(data: data) else { return }
            setImage(image, from: data)
        } catch {
            Log.debug("Failed to load image from URL: \(error)")
        }
    }

    private func setImage(_ image: PlatformImage, from data: Data?) {
        let thumbnail = image.downscaled(toMaxPixels: 512)

        // Save to temp file for upload during generation
        let tempURL = AppStorageContext.current.temporaryDirectory
            .appendingPathComponent("additional_\(input.id.uuidString).png")

        if let pngData = image.pngData() {
            try? pngData.write(to: tempURL)
        }

        appState.generation.additionalInputImages[input.id] = AdditionalInputImage(
            thumbnail: thumbnail,
            fullResolutionURL: tempURL,
            originalData: data
        )
    }

    private func clearImage() {
        appState.generation.additionalInputImages.removeValue(forKey: input.id)
    }

    // MARK: - Helpers

    /// Extracts the existing text value from a workflow node
    private func extractTextFromNode(nodeID: String) -> String {
        guard let workflow = appState.generation.comfyWorkflow,
              let node = workflow[nodeID] as? [String: Any],
              let inputs = node["inputs"] as? [String: Any] else {
            return ""
        }

        // Try common text input keys in order of preference
        let textKeys = ["text", "prompt", "positive", "negative", "string"]
        for key in textKeys {
            if let text = inputs[key] as? String {
                return text
            }
        }

        // Fallback: find any string value in inputs
        for (_, value) in inputs {
            if let text = value as? String, !text.isEmpty {
                return text
            }
        }

        return ""
    }
}

// MARK: - Preview

#if DEBUG
struct AdditionalInputsSection_Previews: PreviewProvider {
    static var previews: some View {
        AdditionalInputsSection()
            .environmentObject(AppState())
            .padding()
    }
}
#endif
