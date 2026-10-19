// InputImagesSection.swift
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PhotosUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import GenStationCore

// MARK: - PNG Prompt Parsing (from Data)
func parsePromptNodes(from data: Data) -> [NodeInfo] {
    Log.debug("DEBUG: Parsing prompts from pasted PNG data, size: \(data.count)")

    var offset: Int = 8  // Skip PNG signature
    let totalLength = data.count
    var workflowStr: String? = nil

    while offset + 11 < totalLength {
        let lengthRange = offset..<(offset + 4)
        let lengthData = data.subdata(in: lengthRange)
        let lengthBytes = [UInt8](lengthData)
        let length = (UInt32(lengthBytes[0]) << 24) | (UInt32(lengthBytes[1]) << 16) |
                    (UInt32(lengthBytes[2]) << 8) | UInt32(lengthBytes[3])

        let fullChunkSize = 12 + Int(length)
        let fullChunkEnd = offset + fullChunkSize
        guard fullChunkEnd <= totalLength else { break }

        let typeStart = offset + 4
        let typeRange = typeStart..<(typeStart + 4)
        let typeData = data.subdata(in: typeRange)
        let typeBytes = [UInt8](typeData)
        let chunkType = String(bytes: typeBytes, encoding: .ascii) ?? ""

        if chunkType == "tEXt" {
            let textStart = typeStart + 4
            let textRange = textStart ..< (textStart + Int(length))
            let textData = data.subdata(in: textRange)
            if let textStr = String(data: textData, encoding: .utf8),
               let nullIndex = textStr.firstIndex(of: "\0") {
                let keyword = String(textStr[..<nullIndex]).trimmingCharacters(in: .whitespaces)
                if ["workflow", "prompt", "Workflow", "Prompt"].contains(keyword) {
                    let valueStart = textStr.index(after: nullIndex)
                    workflowStr = String(textStr[valueStart...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        offset = fullChunkEnd
    }

    // Fallback to ImageIO if manual didn't find it
    if workflowStr == nil {
        let tempURL = AppStorageContext.current.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        do {
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return parsePromptNodes(from: tempURL)
        } catch {
            Log.debug("DEBUG: Temp file for ImageIO failed: \(error)")
            return []
        }
    }

    guard let extractedWorkflowStr = workflowStr else { return [] }

    guard let jsonData = extractedWorkflowStr.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return [] }

    var promptNodes: [NodeInfo] = []

    func isPromptNode(_ classType: String) -> Bool {
        let lower = classType.lowercased()
        if lower.contains("loader") { return false }
        if lower.contains("clip") && lower.contains("encode") { return true }
        if lower.contains("text") && !lower.contains("load") { return true }
        if lower.contains("string") && !lower.contains("load") { return true }
        return false
    }

    func isTextKey(_ key: String) -> Bool {
        let lowerKey = key.lowercased()
        return lowerKey.contains("prompt") || lowerKey.contains("text") ||
               lowerKey.contains("positiv") || lowerKey.contains("negativ") ||
               lowerKey.contains("value")
    }

    if let nodesArray = json["nodes"] as? [[String: Any]] {
        for node in nodesArray {
            guard let nodeID = node["id"] as? Int,
                  let classType = node["type"] as? String else { continue }
            let nodeIDStr = String(nodeID)

            if isPromptNode(classType) {
                let widgetsValues = node["widgets_values"] as? [Any] ?? []
                let text = widgetsValues.compactMap { $0 as? String }.filter { !$0.isEmpty }.first ?? ""
                let uiTitle = node["title"] as? String
                let baseLabel = uiTitle ?? classType
                let label = text.isEmpty ? "Node \(nodeIDStr): \(baseLabel)" : "Node \(nodeIDStr): \(baseLabel) — \(text.prefix(50))\(text.count > 50 ? "..." : "")"
                promptNodes.append(NodeInfo(id: nodeIDStr, label: label, promptText: text.isEmpty ? nil : text))
            }
        }
    } else {
        for (nodeID, node) in json {
            guard let nodeDict = node as? [String: Any],
                  let classType = nodeDict["class_type"] as? String else { continue }

            if isPromptNode(classType) {
                let inputs = nodeDict["inputs"] as? [String: Any] ?? [:]
                var collectedTexts: [String] = []
                for (key, value) in inputs {
                    guard isTextKey(key) else { continue }
                    if let text = value as? String, !text.isEmpty {
                        collectedTexts.append(text)
                    } else if let link = value as? [Any], link.count == 2 {
                        let sourceID: String
                        if let id = link[0] as? String { sourceID = id }
                        else if let id = link[0] as? Int { sourceID = String(id) }
                        else { continue }
                        if let sourceNode = json[sourceID] as? [String: Any],
                           let sourceInputs = sourceNode["inputs"] as? [String: Any] {
                            for (srcKey, srcValue) in sourceInputs {
                                guard isTextKey(srcKey) else { continue }
                                if let text = srcValue as? String, !text.isEmpty {
                                    collectedTexts.append(text)
                                }
                            }
                        }
                    }
                }
                let text = collectedTexts.joined(separator: "\n---\n")
                let metaTitle = (nodeDict["_meta"] as? [String: Any])?["title"] as? String
                let baseLabel = metaTitle ?? classType
                let label = text.isEmpty ? "Node \(nodeID): \(baseLabel)" : "Node \(nodeID): \(baseLabel) — \(text.prefix(50))\(text.count > 50 ? "..." : "")"
                promptNodes.append(NodeInfo(id: nodeID, label: label, promptText: text.isEmpty ? nil : text))
            }
        }
    }

    return promptNodes.sorted { $0.id < $1.id }
}

// MARK: - PNG Prompt Parsing (from URL)
func parsePromptNodes(from url: URL) -> [NodeInfo] {
    Log.debug("DEBUG: Parsing prompts from PNG: \(url.path)")

    guard let data = try? Data(contentsOf: url) else {
        Log.debug("DEBUG: Failed to load PNG binary data")
        return []
    }
    Log.debug("DEBUG: PNG binary loaded, size: \(data.count) bytes")

    var offset: Int = 8
    let totalLength = data.count
    var workflowStr: String? = nil

    while offset + 11 < totalLength {
        let lengthRange = offset..<(offset + 4)
        guard lengthRange.upperBound <= totalLength else {
            Log.debug("DEBUG: Length range exceeds file; breaking at offset \(offset)")
            break
        }
        let lengthData = data.subdata(in: lengthRange)
        let lengthBytes = [UInt8](lengthData)
        let length = (UInt32(lengthBytes[0]) << 24) | (UInt32(lengthBytes[1]) << 16) |
        (UInt32(lengthBytes[2]) << 8) | UInt32(lengthBytes[3])

        Log.debug("DEBUG: Length bytes at offset \(offset): [\(lengthBytes.map { String(format: "%02x", $0) }.joined(separator: " "))], length: \(length)")

        let fullChunkSize = 12 + Int(length)
        let fullChunkEnd = offset + fullChunkSize
        guard fullChunkEnd <= totalLength else {
            Log.debug("DEBUG: Full chunk end \(fullChunkEnd) > total \(totalLength); skipping invalid chunk at offset \(offset)")
            break
        }

        let typeStart = offset + 4
        let typeRange = typeStart..<(typeStart + 4)
        guard typeRange.upperBound <= totalLength else {
            Log.debug("DEBUG: Type range exceeds; breaking")
            break
        }
        let typeData = data.subdata(in: typeRange)
        let typeBytes = [UInt8](typeData)
        let chunkType = String(bytes: typeBytes, encoding: .ascii) ?? ""

        Log.debug("DEBUG: Type bytes: [\(typeBytes.map { String(format: "%02x", $0) }.joined(separator: " "))], chunk: \(chunkType) length: \(length)")

        if chunkType == "tEXt" {
            let textStart = typeStart + 4
            let textRange = textStart ..< (textStart + Int(length))
            guard textRange.lowerBound < textRange.upperBound else {
                offset = fullChunkEnd
                continue
            }
            let textData = data.subdata(in: textRange)
            if let textStr = String(data: textData, encoding: .utf8),
               let nullIndex = textStr.firstIndex(of: "\0") {
                let keyword = String(textStr[..<nullIndex]).trimmingCharacters(in: .whitespaces)
                if ["workflow", "prompt", "Workflow", "Prompt"].contains(keyword) {
                    let valueStart = textStr.index(after: nullIndex)
                    workflowStr = String(textStr[valueStart...]).trimmingCharacters(in: .whitespaces)
                    Log.debug("DEBUG: Found \(keyword) in tEXt chunk: \(workflowStr?.prefix(100) ?? "")...")
                    break
                }
            }
        } else if chunkType == "zTXt" {
            Log.debug("DEBUG: zTXt chunk found at offset \(offset), length \(length); skipping (decompression needed?)")
        }

        offset = fullChunkEnd
        Log.debug("DEBUG: Advanced to next offset: \(offset)")
    }

    // Fallback to ImageIO
    if workflowStr == nil {
        Log.debug("DEBUG: No tEXt chunks found; falling back to ImageIO")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let rawProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil),
              let props = rawProps as? [String: Any],
              let pngDict = props["{PNG}"] as? [String: Any] else {
            Log.debug("DEBUG: ImageIO fallback failed - no {PNG} dict")
            return []
        }
        Log.debug("DEBUG: ImageIO PNG dict keys: \(Array(pngDict.keys))")

        let fallbackStr: String? = pngDict["workflow"] as? String ?? pngDict["prompt"] as? String ?? pngDict["Workflow"] as? String ?? pngDict["Prompt"] as? String ?? nil
        workflowStr = fallbackStr
        if let ws = workflowStr {
            Log.debug("DEBUG: Found via ImageIO: \(ws.prefix(100))...")
        } else {
            Log.debug("DEBUG: No workflow/prompt keys in ImageIO. Available keys: \(Array(pngDict.keys))")
            return []
        }
    }

    guard let extractedWorkflowStr = workflowStr else {
        Log.debug("DEBUG: No workflow string extracted after all methods")
        return []
    }
    Log.debug("DEBUG: Workflow string length: \(extractedWorkflowStr.count)")
    Log.debug("DEBUG: Using workflow str: \(extractedWorkflowStr.prefix(100))...")

    guard let jsonData = extractedWorkflowStr.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        Log.debug("DEBUG: Failed to parse JSON. Raw preview: \(extractedWorkflowStr.prefix(200))")
        return []
    }
    Log.debug("DEBUG: JSON parsed. Top-level keys: \(Array(json.keys).sorted())")

    var promptNodes: [NodeInfo] = []

    func isPromptNode(_ classType: String) -> Bool {
        let lower = classType.lowercased()
        if lower.contains("loader") { return false }
        if lower.contains("clip") && lower.contains("encode") { return true }
        if lower.contains("text") && !lower.contains("load") { return true }
        if lower.contains("string") && !lower.contains("load") { return true }
        return false
    }

    func isTextKey(_ key: String) -> Bool {
        let lowerKey = key.lowercased()
        return lowerKey.contains("prompt") || lowerKey.contains("text") ||
               lowerKey.contains("positiv") || lowerKey.contains("negativ") ||
               lowerKey.contains("value")
    }

    if let nodesArray = json["nodes"] as? [[String: Any]] {
        Log.debug("DEBUG: Full workflow - \(nodesArray.count) nodes")
        for node in nodesArray {
            guard let nodeID = node["id"] as? Int,
                  let classType = node["type"] as? String else { continue }
            let nodeIDStr = String(nodeID)

            if isPromptNode(classType) {
                let widgetsValues = node["widgets_values"] as? [Any] ?? []
                let text = widgetsValues.compactMap { $0 as? String }.filter { !$0.isEmpty }.first ?? ""
                let uiTitle = node["title"] as? String
                let baseLabel = uiTitle ?? classType
                let label = text.isEmpty ? "Node \(nodeIDStr): \(baseLabel)" : "Node \(nodeIDStr): \(baseLabel) — \(text.prefix(50))\(text.count > 50 ? "..." : "")"
                promptNodes.append(NodeInfo(id: nodeIDStr, label: label, promptText: text.isEmpty ? nil : text))
                Log.debug("DEBUG: Added node \(nodeIDStr): \(label)")
            }
        }
    } else {
        Log.debug("DEBUG: Flat prompt dict mode")
        for (nodeID, node) in json {
            guard let nodeDict = node as? [String: Any], let classType = nodeDict["class_type"] as? String else { continue }

            if isPromptNode(classType) {
                let inputs = nodeDict["inputs"] as? [String: Any] ?? [:]
                var collectedTexts: [String] = []
                for (key, value) in inputs {
                    guard isTextKey(key) else { continue }
                    if let text = value as? String, !text.isEmpty {
                        collectedTexts.append(text)
                    } else if let link = value as? [Any], link.count == 2 {
                        let sourceID: String
                        if let id = link[0] as? String { sourceID = id }
                        else if let id = link[0] as? Int { sourceID = String(id) }
                        else { continue }
                        if let sourceNode = json[sourceID] as? [String: Any],
                           let sourceInputs = sourceNode["inputs"] as? [String: Any] {
                            for (srcKey, srcValue) in sourceInputs {
                                guard isTextKey(srcKey) else { continue }
                                if let text = srcValue as? String, !text.isEmpty {
                                    collectedTexts.append(text)
                                }
                            }
                        }
                    }
                }
                let text = collectedTexts.joined(separator: "\n---\n")
                let metaTitle = (nodeDict["_meta"] as? [String: Any])?["title"] as? String
                let baseLabel = metaTitle ?? classType
                let label = text.isEmpty ? "Node \(nodeID): \(baseLabel)" : "Node \(nodeID): \(baseLabel) — \(text.prefix(50))\(text.count > 50 ? "..." : "")"
                promptNodes.append(NodeInfo(id: nodeID, label: label, promptText: text.isEmpty ? nil : text))
            }
        }
    }

    let result = promptNodes.sorted { $0.id < $1.id }
    Log.debug("DEBUG: Total prompt nodes: \(result.count)")
    return result
}

// MARK: - Input Images Section
struct InputImagesSection: View {
    @Binding var errorItem: AlertError?
    let onAnnotate: (UUID) -> Void
    let onDescribeImage: (UIState.ImageSlot) -> Void
    @EnvironmentObject var appState: AppState

    @State private var toastMessage: String?
    @State private var showClearConfirmation: Bool = false

    private var noImagesMessage: String {
        if appState.maxImageSlots == 0 {
            if appState.settings.provider == .comfyUI {
                if appState.generation.imageNodes.isEmpty {
                    return "Input images not supported in this workflow."
                } else {
                    return "Select at least one input image node to enable input images."
                }
            } else if appState.settings.provider == .aimlapi {
                // Model-dependent, not mode-dependent (finding #8)
                return "This model doesn't accept input images."
            } else {
                return "Input images not supported in this mode."
            }
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header - neutral colors
            Label {
                Text("Input Images")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
            } icon: {
                Image(systemName: "photo.on.rectangle")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 32)
            }
            .padding(.horizontal, 4)

            // Content Area - no glass background
            Group {
                if !appState.canAddImages || appState.maxImageSlots == 0 {
                    // Unsupported mode message
                    Text(noImagesMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(40)
                        .frame(maxWidth: .infinity)
                } else if appState.ui.imageSlots.isEmpty {
                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text(emptySlotsMessage)
                            .font(.subheadline)
                            .foregroundColor(emptySlotsMessageIsRequired ? .orange : .secondary)
                            .multilineTextAlignment(.center)

                        Text("Click on + icon to add an image slot")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity)
                } else {
                    // Image slots grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 20)], spacing: 20) {
                        ForEach($appState.ui.imageSlots) { $slot in
                            ImageSlotItemView(
                                slot: $slot,
                                errorItem: $errorItem,
                                onAnnotate: onAnnotate,
                                onDescribeImage: onDescribeImage,
                                onRemove: removeImageSlot,
                                toastMessage: $toastMessage
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            // Floating action pill - neutral colors, functional icons
            HStack(spacing: 16) {
                Button(action: addImageSlot) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .disabled(!appState.canAddImages || appState.ui.imageSlots.count >= appState.maxImageSlots)
                .opacity(!appState.canAddImages || appState.ui.imageSlots.count >= appState.maxImageSlots ? 0.4 : 1.0)
                .help("Add a new image slot")
                .accessibilityLabel("Add image slot")

                Button(action: { showClearConfirmation = true }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .disabled(appState.ui.imageSlots.isEmpty)
                .opacity(appState.ui.imageSlots.isEmpty ? 0.4 : 1.0)
                .help("Remove all image slots")
                .accessibilityLabel("Remove all image slots")
            }
            .padding(16)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.1), radius: 8)
            .padding(.trailing, 20)
            .offset(y: 40)
        }
        .padding(.bottom, 36)
        .overlay {
            if let message = toastMessage {
                LiquidGlassToast(message: message)
                    .transition(.toastTransition)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: toastMessage)
        .alert("Confirm Removal", isPresented: $showClearConfirmation) {
            Button("Yes", role: .destructive) { clearImageSlots() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to remove all input image slots?")
        }
    }

    // MARK: - Computed Properties
    private var emptySlotsMessage: String {
        let isRequired = appState.settings.provider == .aimlapi &&
                         appState.currentAIMLModel.requiresInputImage

        let max = appState.maxImageSlots
        let rangeText = max == 1 ? "1" : "1–\(max)"
        let noun = max == 1 ? "image" : "images"

        if isRequired {
            return "This model requires \(rangeText) input \(noun)"
        } else {
            return "This model accepts \(rangeText) input \(noun) (optional)"
        }
    }

    private var emptySlotsMessageIsRequired: Bool {
        appState.settings.provider == .aimlapi &&
        appState.currentAIMLModel.requiresInputImage
    }

    // MARK: - Actions
    private func addImageSlot() {
        if appState.ui.imageSlots.count < appState.maxImageSlots {
            let emptySlot = UIState.ImageSlot(thumbnail: nil, fullResolutionURL: nil, originalData: nil)
            appState.ui.imageSlots.append(emptySlot)
        } else {
            errorItem = AlertError(message: "Maximum number of image slots reached (\(appState.maxImageSlots)).", fullMessage: nil)
        }
    }

    private func clearImageSlots() {
        appState.ui.imageSlots.removeAll()
    }

    private func removeImageSlot(_ id: UUID) {
        appState.ui.imageSlots.removeAll { $0.id == id }
    }
}

// MARK: - Image Slot Card (Liquid Glass)
struct ImageSlotItemView: View {
    @Binding var slot: UIState.ImageSlot
    @Binding var errorItem: AlertError?
    let onAnnotate: (UUID) -> Void
    let onDescribeImage: (UIState.ImageSlot) -> Void
    let onRemove: (UUID) -> Void
    @Binding var toastMessage: String?

    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var isDropTargeted: Bool = false
    @State private var showPicker: Bool = false

    private var cardGlassBackground: some View {
        Group {
            Color.clear.background(.thinMaterial)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Thumbnail area
            ZStack {
                if let thumb = slot.thumbnail {
                    Image(platformImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 160)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("Drop image here")
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    isDropTargeted ? Color.blue : Color.secondary.opacity(0.2),
                                    lineWidth: isDropTargeted ? 2 : 1
                                )
                        )
                }

                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue.opacity(0.1))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
            .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }

            // Status label (no longer showing ugly UUID filenames)
            Text(slot.path.isEmpty ? "No image selected" : "Image loaded")
                .font(.subheadline.weight(.medium))
                .foregroundColor(slot.path.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons (icon-only for liquid glass aesthetic)
            HStack(spacing: 8) {
                Button {
                    showImageOpenPanel()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .help("Browse for image")
                .accessibilityLabel("Browse for image")

                Button {
                    pasteImage()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .help("Paste from clipboard")
                .accessibilityLabel("Paste from clipboard")

                #if os(iOS)
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
                .help("Choose from Photos")
                .accessibilityLabel("Choose from Photos")
                #endif

                if slot.thumbnail != nil {
                    Button {
                        onAnnotate(slot.id)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .help("Annotate image")
                    .accessibilityLabel("Annotate image")

                    Button {
                        withAnimation { toastMessage = "Analyzing image..." }
                        onDescribeImage(slot)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { toastMessage = nil }
                        }
                    } label: {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.indigo)
                    .help("Describe image with AI")
                    .accessibilityLabel("Describe image with AI")
                }

                Spacer()

                Button(action: { onRemove(slot.id) }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Remove this image slot")
                .accessibilityLabel("Remove image slot")
            }

            // Embedded prompts (if any)
            if !slot.promptNodes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Embedded Workflow Prompts")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        Menu {
                            ForEach(0..<slot.promptNodes.count, id: \.self) { index in
                                Button(slot.promptNodes[index].label) {
                                    slot.selectedPromptIndex = index
                                }
                            }
                        } label: {
                            Text(slot.promptNodes[slot.selectedPromptIndex].label)
                                .font(.caption2)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .menuStyle(.borderlessButton)

                        Button {
                            let text = slot.promptNodes[slot.selectedPromptIndex].promptText ?? ""
                            copyToClipboard(text)
                            withAnimation { toastMessage = "Copied to Clipboard" }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { toastMessage = nil }
                            }
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                        .help("Copy prompt")
                        .accessibilityLabel("Copy prompt")
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(cardGlassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 12, y: 6)
        .sheet(isPresented: $showPicker) {
            #if os(iOS)
            PHPickerWrapper { result in
                handlePickerResult(result)
            }
            #endif
        }
    }

    // MARK: - File Picker
    private func showImageOpenPanel() {
        PlatformFilePicker.presentOpenPanel(allowedTypes: [.image], allowsMultiple: false, canChooseDirectories: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadImageFromURL(url)
            case .failure(let error):
                errorItem = AlertError(message: "Failed to select image: \(error.localizedDescription)", fullMessage: nil)
            }
        }
    }

    // MARK: - Photos Picker (iOS)
    private func handlePickerResult(_ result: PHPickerResult?) {
        guard let result = result else { return }
        result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorItem = AlertError(message: "Failed to load image: \(error.localizedDescription)", fullMessage: nil)
                }
                return
            }
            guard let data = data else { return }
            guard let platformImage = PlatformImage(data: data) else { return }
            DispatchQueue.main.async {
                self.setImage(platformImage, from: data, path: "Selected from Photos")
            }
        }
    }

    // MARK: - Clipboard
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }

    private func pasteImage() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) {
            if let platformImage = PlatformImage(data: data) {
                setImage(platformImage, from: data, path: "Pasted from Clipboard")
            }
        } else if let data = pasteboard.data(forType: .tiff), let nsImg = NSImage(data: data) {
            setImage(nsImg, from: data, path: "Pasted from Clipboard")
        } else if let nsImg = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            setImage(nsImg, from: nsImg.tiffRepresentation, path: "Pasted from Clipboard")
        } else {
            errorItem = AlertError(message: "No image data in clipboard", fullMessage: nil)
        }
        #elseif os(iOS)
        let pasteboard = UIPasteboard.general
        if let data = pasteboard.data(forPasteboardType: "public.png") {
            if let platformImage = PlatformImage(data: data) {
                setImage(platformImage, from: data, path: "Pasted from Clipboard")
            }
        } else if let uiImg = pasteboard.image {
            setImage(uiImg, from: uiImg.pngData(), path: "Pasted from Clipboard")
        } else {
            errorItem = AlertError(message: "No image data in clipboard", fullMessage: nil)
        }
        #endif
    }

    // MARK: - Drop Handling
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorItem = AlertError(message: "Drop error: \(error.localizedDescription)", fullMessage: nil)
                    }
                    return
                }

                guard let url = url else { return }
                let didStart = url.startAccessingSecurityScopedResource()
                DispatchQueue.main.async {
                    self.loadImageFromURL(url)
                }
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorItem = AlertError(message: "Drop error: \(error.localizedDescription)", fullMessage: nil)
                    }
                    return
                }

                guard let data = data else { return }
                guard let platformImage = PlatformImage(data: data) else { return }
                DispatchQueue.main.async {
                    self.setImage(platformImage, from: data, path: "Dropped Image")
                }
            }
        } else {
            return false
        }

        return true
    }

    // MARK: - Image Loading
    private func loadImageFromURL(_ url: URL) {
        do {
            let (image, promptNodes, originalData) = try withSecureAccess(to: url) {
                var img: PlatformImage? = nil
                var nodes: [NodeInfo] = []
                var origData: Data? = nil

                if url.pathExtension.lowercased() == "png" {
                    let data = try Data(contentsOf: url)
                    origData = data
                    nodes = parsePromptNodes(from: data)
                    img = PlatformImage(data: data)
                } else {
                    img = PlatformImage(contentsOf: url)
                }
                return (img, nodes, origData)
            }

            guard let img = image else {
                errorItem = AlertError(message: "Failed to load image.", fullMessage: nil)
                return
            }

            setImage(img, from: originalData, path: url.path, promptNodes: promptNodes)

        } catch {
            errorItem = AlertError(message: "Failed to access image: \(error.localizedDescription)", fullMessage: nil)
        }
    }

    private func withSecureAccess<T>(to url: URL, operation: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    private func setImage(
        _ image: PlatformImage,
        from data: Data?,
        path: String,
        promptNodes: [NodeInfo] = []
    ) {
        let thumbnail = image.downscaled(toMaxPixels: 512)

        let tempURL = AppStorageContext.current.temporaryDirectory
            .appendingPathComponent("slot_\(UUID().uuidString).png")

        if let pngData = image.pngData() {
            try? pngData.write(to: tempURL)
        }

        slot.thumbnail = thumbnail
        slot.fullResolutionURL = tempURL
        slot.originalData = data

        if !promptNodes.isEmpty {
            slot.promptNodes = promptNodes.sorted { $0.id < $1.id }
            slot.selectedPromptIndex = 0
        } else if let data = data, isPNGData(data) {
            let nodes = parsePromptNodes(from: data)
            if !nodes.isEmpty {
                slot.promptNodes = nodes.sorted { $0.id < $1.id }
                slot.selectedPromptIndex = 0
            }
        }
    }
}

// MARK: - Photos Picker Wrapper (iOS)
#if os(iOS)
struct PHPickerWrapper: UIViewControllerRepresentable {
    let onCompletion: (PHPickerResult?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: PHPickerViewControllerDelegate {
        let parent: PHPickerWrapper

        init(_ parent: PHPickerWrapper) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            parent.onCompletion(results.first)
        }
    }
}
#endif
