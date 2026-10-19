//ResponseSection.swift
import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif
import GenStationCore

struct ResponseSection: View {
    @EnvironmentObject var appState: AppState
    @Binding var imageScale: CGFloat
    @Binding var errorItem: AlertError?
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.undoManager) private var undoManager
    
    @Binding var showUndoButton: Bool
    
    @State private var finalScale: CGFloat = 1.0
    @State private var showCopiedOverlay: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0 // Default aspect ratio
    @State private var player: AVPlayer? = nil // State for AVPlayer
    @State private var isVideoPlayable: Bool = false // Track video playability
    @State private var videoHasAudio: Bool = false // Track if video has audio track
    @State private var showSavedToPhotosToast: Bool = false
    @State private var savedToPhotosToastTimer: Timer? = nil
    @State private var showGIFExportSheet: Bool = false
    @State private var showAddedToInputToast: Bool = false

    let onPopOut: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            imageContent
            statusContent
            textContent
        }
        .frame(minHeight: 250)
        .padding(16)
        .cornerRadius(16)
        .onChange(of: appState.ui.outputImages) { _ in
            finalScale = 1.0
            imageScale = 1.0
        }
        .onChange(of: appState.ui.outputPaths) { _ in
            // Load aspect ratio and player for the current video when outputPaths changes
            Task {
                await loadVideoAspectRatioAndPlayer()
            }
        }
        .onAppear {
            // Initial load of aspect ratio and player for the current video
            Task {
                await loadVideoAspectRatioAndPlayer()
            }
        }
        .sheet(isPresented: $showDeleteAlert) {
            DeleteConfirmationView(
                title: "Delete Response",
                message: deleteMessage,
                hasDeletableFiles: hasFile && fileExists,
                deleteAction: { deleteFiles in
                    deleteCurrentImage(deleteFile: deleteFiles)
                },
                cancelAction: {}
            )
            #if os(iOS)
            .presentationDetents([.height(260)])
            #endif
        }
        .sheet(isPresented: $showGIFExportSheet) {
            if let videoURL = currentVideoURL {
                GIFExportSheet(videoURL: videoURL)
                    .environmentObject(appState)
            }
        }
        #if os(macOS)
        .overlay(
            Group {
                if fileExists {
                    Color.clear.dialogSeverity(.critical)
                }
            }
            .dialogIcon(Image(systemName: "trash"))
        )
        #endif
    }
    
    private var backgroundColor: Color {
        #if os(iOS)
        Color(.systemGray6)
        #else
        Color.gray
        #endif
    }
    
    private var secondaryBackgroundColor: Color {
        #if os(iOS)
        Color(.systemGray6)
        #else
        Color.gray
        #endif
    }
    
    private var secondarySystemBackgroundColor: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    // Video generation progress display
    @ViewBuilder
    private var statusContent: some View {
        // Live remote video jobs: elapsed + typical range + provider status
        // (replaces the fabricated percent bar; WS-3 stage 3)
        VideoJobProgressView(queue: appState.jobQueue)

        // Status badge for completed/failed videos
        let index = appState.ui.currentOutputIndex
        if let optionalPath = appState.ui.outputPaths[safe: index], let path = optionalPath, path.hasSuffix(".mp4") {
            if let historyItem = appState.historyState.history.first(where: { item in
                if case .item(let hItem) = item, hItem.imagePath == path {
                    return true
                }
                return false
            }), case .item(let hItem) = historyItem, let status = hItem.status, status != .completed {
                HStack {
                    Text(status.displayLabel)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundColor(status == .failed ? .red : .orange)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(secondarySystemBackgroundColor)
                        .cornerRadius(DS.Radius.standard)
                        .help("Video generation status: \(status.wireValue)")
                        .accessibilityLabel("Video status: \(status.wireValue)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    @ViewBuilder
    private var imageContent: some View {
        let count = appState.ui.outputImages.count
        let index = appState.ui.currentOutputIndex
        if let optionalPath = appState.ui.outputPaths[safe: index], let path = optionalPath, !path.isEmpty, path.hasSuffix(".mp4") {
            let scopedExists = scopedFileExists(path: path)
            if scopedExists {
                if isVideoPlayable, let player = player {
                    ResponseVideoPlayerView(player: player, aspectRatio: videoAspectRatio)
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        .overlay(alignment: .topTrailing) {
                            if videoHasAudio {
                                Label("Audio", systemImage: "speaker.wave.2.fill")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(DS.Radius.small)
                                    .padding(12)
                            }
                        }
                        .help("Generated video. Use playback controls to play, pause, seek, and step through frames.")
                        .accessibilityLabel("Generated video with full playback controls\(videoHasAudio ? ", includes audio" : "")")
                } else {
                    Text("Video file is corrupted or unplayable.")
                        .font(.system(.body, weight: .medium))
                        .foregroundColor(.secondary)
                        .help("Video file is invalid or corrupted")
                        .accessibilityLabel("Corrupted video")
                }
            } else {
                Text("Video file not found.")
                    .font(.system(.body, weight: .medium))
                    .foregroundColor(.secondary)
                    .help("Video file is missing or inaccessible")
                    .accessibilityLabel("Video not found")
            }
            
            // Warn if multiple videos (unexpected for AIML API)
            if count > 1 && appState.ui.outputPaths.contains(where: { $0?.hasSuffix(".mp4") ?? false }) {
                Text("Warning: Multiple videos detected. AIML API typically returns one video.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
                    .help("Unexpected multiple video outputs")
                    .accessibilityLabel("Multiple video warning")
            }
            
            // Navigation controls for multiple outputs
            if count > 1 {
                HStack(spacing: 12) {
                    Button {
                        if index > 0 { appState.ui.currentOutputIndex -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(index == 0)
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .accessibilityLabel("Previous output")

                    Text("\(index + 1) of \(count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button {
                        if index < count - 1 { appState.ui.currentOutputIndex += 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(index == count - 1)
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .accessibilityLabel("Next output")
                }
                .help("Navigate between generated outputs")
                .accessibilityLabel("Output navigation")
            }
            

            // Action buttons for video
            HStack(spacing: 12) {
                // 1. Pop-out button (NEW – comes first)
                Button(action: onPopOut) {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .cornerRadius(DS.Radius.card)
                .shadow(radius: 2)
                .help("Open video in full-screen viewer")
                .accessibilityLabel("Open video in full-screen viewer")
                .keyboardShortcut("p", modifiers: [.command])

                // 2. Save video button (was first → now second)
                Button {
                    saveMediaAs(path: path)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .cornerRadius(DS.Radius.card)
                .shadow(radius: 2)
                .help("Save the video to a file")
                .accessibilityLabel("Save video as")

                // 3. Export as GIF button
                Button {
                    showGIFExportSheet = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .cornerRadius(DS.Radius.card)
                .shadow(radius: 2)
                .help("Export video as animated GIF")
                .accessibilityLabel("Export as GIF")

                // 4. Delete button
                Button {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .cornerRadius(DS.Radius.card)
                .shadow(radius: 2)
                .help("Delete the response")
                .accessibilityLabel("Delete response")
            }
        } else if count > 0, let optionalImage = appState.ui.outputImages[safe: index], let platformImage = optionalImage {
            // Image case
            VStack(spacing: 12) {
                Image(platformImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 600)
                    .scaleEffect(imageScale)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    .gesture(MagnificationGesture()
                        .onChanged { value in
                            imageScale = finalScale * value
                        }
                        .onEnded { value in
                            finalScale *= value
                            imageScale = finalScale
                        }
                    )
                    .help("Generated image. Pinch to zoom.")
                    .accessibilityLabel("Generated image")
                    .overlay(
                        Group {
                            if showCopiedOverlay {
                                LiquidGlassToast(message: "Copied to Clipboard")
                                    .transition(.toastTransition)
                                    .help("Confirmation that the image was copied to the clipboard")
                                    .accessibilityLabel("Image copied to clipboard")
                            }
                        }
                    )
                // Toast overlay
                .overlay(alignment: .top) {
                    if showSavedToPhotosToast {
                        LiquidGlassToast(message: "Saved to Photos")
                            .transition(.toastTransition)
                            .padding(.top, 20)
                            .zIndex(1)
                    }
                    if showAddedToInputToast {
                        LiquidGlassToast(message: "Added to Input")
                            .transition(.toastTransition)
                            .padding(.top, 20)
                            .zIndex(1)
                    }
                }
                
                // Navigation controls for multiple outputs
                if count > 1 {
                    HStack(spacing: 12) {
                        Button {
                            if index > 0 { appState.ui.currentOutputIndex -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(index == 0)
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        .accessibilityLabel("Previous image")

                        Text("\(index + 1) of \(count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button {
                            if index < count - 1 { appState.ui.currentOutputIndex += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(index == count - 1)
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        .accessibilityLabel("Next image")
                    }
                    .help("Navigate between generated images")
                    .accessibilityLabel("Image navigation")
                }
                
                // Action buttons for image/video
                HStack(spacing: 12) {
                    Button(action: onPopOut) {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .cornerRadius(DS.Radius.card)
                    .shadow(radius: 2)
                    .help("Open in full viewer")
                    .accessibilityLabel("Open in full viewer")
                    .keyboardShortcut("p", modifiers: [.command])

                    Button {
                        PlatformPasteboard.clearContents()
                        PlatformPasteboard.writeImage(platformImage)
                        withAnimation {
                            showCopiedOverlay = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showCopiedOverlay = false
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .cornerRadius(DS.Radius.card)
                    .shadow(radius: 2)
                    .help("Copy the image to the clipboard")
                    .accessibilityLabel("Copy image")
 
                    // Only show "Save to Photos" on iOS and only for images (not videos)
                    #if os(iOS)
                    if !(appState.ui.outputPaths[safe: appState.ui.currentOutputIndex]??.hasSuffix(".mp4") ?? false) {
                        Button {
                            saveCurrentImageToPhotos()
                        } label: {
                            Image(systemName: "photo.on.rectangle")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .cornerRadius(DS.Radius.card)
                        .shadow(radius: 2)
                        .help("Save image to Photos library")
                        .accessibilityLabel("Save to Photos")
                    }
                    #else
                    // macOS: Always show "Save As…" for images
                    Button {
                        saveImageAs(image: platformImage)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .cornerRadius(DS.Radius.card)
                    .shadow(radius: 2)
                    .help("Save the image to a file")
                    .accessibilityLabel("Save image as")
                    #endif

                    // Use as input image
                    if appState.maxImageSlots > 0 {
                        Button {
                            addOutputToInputSlot(image: platformImage)
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .cornerRadius(DS.Radius.card)
                        .shadow(radius: 2)
                        .help("Use as input image")
                        .accessibilityLabel("Use as input image")
                    }

                    Button {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .cornerRadius(DS.Radius.card)
                    .shadow(radius: 2)
                    .help("Delete the response")
                    .accessibilityLabel("Delete response")
                }
                
            }
            .frame(maxWidth: .infinity)
            .padding(12)
        } else {
            // No media case
            VStack {
                Text("No media generated.")
                    .font(.system(.body, weight: .medium))
                    .foregroundColor(.secondary)
                    .help("No image or video has been generated yet")
                    .accessibilityLabel("No media generated")
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    @ViewBuilder
    private var textContent: some View {
        let index = appState.ui.currentOutputIndex
        let text = appState.ui.outputTexts[safe: index] ?? ""
        if text.isEmpty {
            Rectangle()
                .fill(secondarySystemBackgroundColor)
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60)
                .cornerRadius(DS.Radius.panel)
                .shadow(radius: 2)
                .help("Placeholder for response text")
                .accessibilityLabel("No response text")
        } else {
            Text(text)
                .font(.system(.body))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(secondarySystemBackgroundColor)
                .cornerRadius(DS.Radius.panel)
                .shadow(radius: 2)
                .help("Generated text response")
                .accessibilityLabel("Response text: \(text)")
        }
    }
    
    private var hasFile: Bool {
        let index = appState.ui.currentOutputIndex
        return appState.ui.outputPaths[safe: index] != nil
    }

    private var currentVideoURL: URL? {
        let index = appState.ui.currentOutputIndex
        guard let optionalPath = appState.ui.outputPaths[safe: index],
              let path = optionalPath,
              !path.isEmpty,
              path.lowercased().hasSuffix(".mp4") else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
    
    private var fileExists: Bool {
        let index = appState.ui.currentOutputIndex
        guard let optionalPath = appState.ui.outputPaths[safe: index], let path = optionalPath, !path.isEmpty else {
            return false
        }
        return scopedFileExists(path: path)
    }
    
    private var deleteMessage: String {
        var msg = "Are you sure you want to delete this response from history?"
        if hasFile && !fileExists {
            msg += "\nNote: File is missing or inaccessible."
        }
        return msg
    }
    
    // MARK: - Video Loading – Fixed for iOS Security-Scoped Access
    
    private func loadVideoAspectRatioAndPlayer() async {
        let index = appState.ui.currentOutputIndex
        
        guard let path = appState.ui.outputPaths[safe: index],
              let path = path,
              !path.isEmpty,
              path.lowercased().hasSuffix(".mp4"),
              scopedFileExists(path: path) else {
            resetVideoPlayer()  // ← No await needed
            return
        }
        
        let url = URL(fileURLWithPath: path)
        await loadAspectRatioAndPlayer(from: url)
    }
    
    private func loadAspectRatioAndPlayer(from url: URL) async {
        var securityScopeStarted = false
        if let outputDir = appState.settings.outputDirectory,
           url.path.hasPrefix(outputDir.path) {
            securityScopeStarted = outputDir.startAccessingSecurityScopedResource()
        }
        
        defer {
            if securityScopeStarted {
                appState.settings.outputDirectory?.stopAccessingSecurityScopedResource()
            }
        }
        
        guard securityScopeStarted || appState.settings.outputDirectory == nil else {
            resetVideoPlayer()  // ← No await
            return
        }
        
        let asset = AVAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                resetVideoPlayer()
                return
            }
            
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let renderedSize = size.applying(transform)
            let aspect = abs(renderedSize.width / renderedSize.height)

            // Check for audio tracks
            let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
            let hasAudio = !(audioTracks?.isEmpty ?? true)

            await MainActor.run {
                videoAspectRatio = aspect.isFinite && aspect > 0 ? aspect : 16/9
                player = AVPlayer(url: url)
                isVideoPlayable = true
                videoHasAudio = hasAudio
            }
        } catch {
            Log.debug("Failed to load video metadata: \(error)")
            resetVideoPlayer()
        }
    }
    
    private func resetVideoPlayer() {
        Task { @MainActor in
            videoAspectRatio = 16.0 / 9.0
            player = nil
            isVideoPlayable = false
            videoHasAudio = false
        }
    }
    
    // Helper for scoped file exists check
    private func scopedFileExists(path: String) -> Bool {
        var exists = false
        if let dir = appState.settings.outputDirectory {
            if dir.startAccessingSecurityScopedResource() {
                exists = FileManager.default.fileExists(atPath: path)
                dir.stopAccessingSecurityScopedResource()
            }
        } else {
            exists = FileManager.default.fileExists(atPath: path)
        }
        return exists
    }
    
    private func addOutputToInputSlot(image: PlatformImage) {
        let atMaxCapacity = appState.ui.imageSlots.count >= appState.maxImageSlots
        let emptySlotIndex = atMaxCapacity ? appState.ui.imageSlots.firstIndex(where: { $0.path.isEmpty }) : nil

        if atMaxCapacity && emptySlotIndex == nil {
            // All slots full — show feedback
            withAnimation { showAddedToInputToast = true }
            // Reuse toast but with a different message would be complex;
            // for now just don't add if truly full
            return
        }

        let thumbnail = image.downscaled(toMaxPixels: 512)
        let pngData = image.pngData()
        let tempURL = AppStorageContext.current.temporaryDirectory
            .appendingPathComponent("reuse_\(UUID().uuidString).png")
        try? pngData?.write(to: tempURL)

        let newSlot = UIState.ImageSlot(
            thumbnail: thumbnail,
            fullResolutionURL: tempURL,
            originalData: pngData
        )

        if let index = emptySlotIndex {
            appState.ui.imageSlots[index] = newSlot
        } else {
            appState.ui.imageSlots.append(newSlot)
        }

        withAnimation { showAddedToInputToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showAddedToInputToast = false }
        }
    }

    private func saveImageAs(image: PlatformImage) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "generated_image.png"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let data = image.platformTiffRepresentation(), let bitmap = NSBitmapImageRep(data: data), let pngData = bitmap.representation(using: .png, properties: [:]) {
                do {
                    try pngData.write(to: url)
                } catch {
                    errorItem = AlertError(message: "Failed to save image: \(error.localizedDescription)", fullMessage: nil)
                }
            }
        }
        #elseif os(iOS)
        guard let pngData = image.pngData() else {
            errorItem = AlertError(message: "Failed to prepare image for saving.", fullMessage: nil)
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [pngData], applicationActivities: nil)
        
        let keyWindow = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first { $0.isKeyWindow }
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            activityVC.popoverPresentationController?.sourceView = keyWindow?.rootViewController?.view
            if let view = keyWindow?.rootViewController?.view {
                activityVC.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
            activityVC.popoverPresentationController?.permittedArrowDirections = []
        }
        
        if let topVC = keyWindow?.rootViewController {
            topVC.present(activityVC, animated: true)
        } else {
            errorItem = AlertError(message: "Unable to present save dialog.", fullMessage: nil)
        }
        #endif
    }
    
    
    private func saveMediaAs(path: String) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "generated_video.mp4"
        
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        
        let sourceURL = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        
        do {
            // Determine if source is in security-scoped directory
            if let outputDir = appState.settings.outputDirectory,
               sourceURL.path.hasPrefix(outputDir.path) {
                
                Log.debug("Saving video from security-scoped directory: \(outputDir.path)")
                try withSecureAccess(to: outputDir) {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }
                
            } else {
                // CASE 2: Source is in Downloads or temporary directory (no scope needed)
                Log.debug("Saving video from non-scoped directory: \(sourceURL.path)")
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
            
            Log.debug("Video saved successfully to: \(destinationURL.path)")
            
        } catch {
            let errorMessage = "Failed to save video: \(error.localizedDescription)"
            Log.debug("❌ \(errorMessage)")
            Log.debug("Source: \(sourceURL.path)")
            Log.debug("Destination: \(destinationURL.path)")
            Log.debug("Output Directory: \(appState.settings.outputDirectory?.path ?? "none")")
            
            errorItem = AlertError(
                message: errorMessage,
                fullMessage: "Source: \(sourceURL.path)\nDestination: \(destinationURL.path)"
            )
        }
        
        
        #elseif os(iOS)
        let sourceURL = URL(fileURLWithPath: path)
        
        do {
            // Determine if source is in security-scoped directory
            if let outputDir = appState.settings.outputDirectory,
               sourceURL.path.hasPrefix(outputDir.path) {
                
                // CASE 1: Source is in security-scoped output directory
                Log.debug("Sharing video from security-scoped directory")
                try withSecureAccess(to: outputDir) {
                    try shareVideo(url: sourceURL)
                }
                
            } else {
                // CASE 2: Source is in app sandbox
                Log.debug("Sharing video from app sandbox")
                try shareVideo(url: sourceURL)
            }
            
        } catch {
            let errorMessage = "Failed to share video: \(error.localizedDescription)"
            Log.debug("❌ \(errorMessage)")
            errorItem = AlertError(message: errorMessage, fullMessage: nil)
        }
        #endif
    }
 
    // MARK: - iOS Helper
    private func saveCurrentImageToPhotos() {
        guard let currentPath = appState.ui.outputPaths[safe: appState.ui.currentOutputIndex],
              let path = currentPath,
              let historyItem = appState.historyState.history.compactMap({ $0.asItem }).first(where: { $0.imagePath == path })
        else {
            errorItem = AlertError(message: "Could not locate image for saving.", fullMessage: nil)
            return
        }
 
        Task {
            let (success, _) = await PhotosLibraryHelper.saveToPhotosLibrary(items: [historyItem], appState: appState)
            await MainActor.run {
                if success > 0 {
                    // Cancel any existing timer
                    savedToPhotosToastTimer?.invalidate()
                    
                    withAnimation(DS.Anim.smooth) {
                        showSavedToPhotosToast = true
                    }
                    
                    // Auto-hide after 2 seconds
                    savedToPhotosToastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showSavedToPhotosToast = false
                        }
                    }
                } else {
                    errorItem = AlertError(message: "Failed to save image to Photos.", fullMessage: nil)
                }
            }
        }
    }
    
    #if os(iOS)
    private func shareVideo(url: URL) throws {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        let keyWindow = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first { $0.isKeyWindow }
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            activityVC.popoverPresentationController?.sourceView = keyWindow?.rootViewController?.view
            if let view = keyWindow?.rootViewController?.view {
                activityVC.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
            activityVC.popoverPresentationController?.permittedArrowDirections = []
        }
        
        guard let topVC = keyWindow?.rootViewController
        else {
            throw NSError(domain: "ShareError", code: 1, userInfo:
                [NSLocalizedDescriptionKey: "Unable to present share sheet"])
        }
        
        topVC.present(activityVC, animated: true)
    }
    #endif
    
    
    private func deleteCurrentImage(deleteFile: Bool) {
        let index = appState.ui.currentOutputIndex
        if index < appState.ui.outputImages.count, let optionalPath = appState.ui.outputPaths[safe: index], let path = optionalPath {
            // Remove from session gallery before deleting from history
            if let itemId = appState.historyState.history.flatMap({ $0.allItems }).first(where: { $0.imagePath == path })?.id {
                appState.ui.sessionGeneratedIDs.removeAll { $0 == itemId }
            }

            // Store state for undo
            let oldHistory = appState.historyState.history
            let historyEntryRemoved = appState.historyState.findAndRemoveEntry(matching: { $0.imagePath == path })
            
            Log.debug("Deleting image at index \(index), path: \(path), history entry removed: \(historyEntryRemoved)")
            Log.debug("History before deletion: \(appState.historyState.history.map { $0.id })")
            
            // Register undo action
            if let undoManager = undoManager {
                let oldImages = appState.ui.outputImages
                let oldTexts = appState.ui.outputTexts
                let oldPaths = appState.ui.outputPaths
                let oldIndex = appState.ui.currentOutputIndex
                
                undoManager.registerUndo(withTarget: appState) { target in
                    Log.debug("Undoing delete: Restoring history with \(oldHistory.count) entries: \(oldHistory.map { $0.id })")
                    // Restore UI state
                    target.ui.outputImages = oldImages
                    target.ui.outputTexts = oldTexts
                    target.ui.outputPaths = oldPaths
                    target.ui.currentOutputIndex = oldIndex
                    
                    // Restore history state
                    target.historyState.history = oldHistory
                    target.historyState.saveHistory()
                    target.historyState.objectWillChange.send()
                    target.ui.objectWillChange.send()
                    
                    Log.debug("History after undo: \(target.historyState.history.map { $0.id })")
                    
                    // Register redo action
                    undoManager.registerUndo(withTarget: target) { redoTarget in
                        let redoIndex = redoTarget.ui.currentOutputIndex
                        if redoIndex < redoTarget.ui.outputImages.count, let redoOptionalPath = redoTarget.ui.outputPaths[safe: redoIndex], let redoPath = redoOptionalPath {
                            // Redo file deletion if applicable
                            if deleteFile {
                                let fileURL = URL(fileURLWithPath: redoPath)
                                let fileManager = FileManager.default
                                if let dir = redoTarget.settings.outputDirectory {
                                    do {
                                        try withSecureAccess(to: dir) {
                                            try fileManager.removeItem(at: fileURL)
                                        }
                                    } catch {
                                        Log.debug("Redo: Failed to delete file: \(error)")
                                    }
                                }
                            }
                            
                            // Redo history entry removal
                            _ = redoTarget.historyState.findAndRemoveEntry(matching: { $0.imagePath == redoPath })
                            
                            // Redo UI array removals
                            redoTarget.ui.outputImages.remove(at: redoIndex)
                            redoTarget.ui.outputTexts.remove(at: redoIndex)
                            redoTarget.ui.outputPaths.remove(at: redoIndex)
                            
                            // Adjust index for redo
                            if !redoTarget.ui.outputImages.isEmpty {
                                redoTarget.ui.currentOutputIndex = min(redoIndex, redoTarget.ui.outputImages.count - 1)
                            } else {
                                redoTarget.ui.currentOutputIndex = 0
                            }
                            
                            redoTarget.ui.objectWillChange.send()
                            redoTarget.historyState.saveHistory()
                            redoTarget.historyState.objectWillChange.send()
                            Log.debug("Redo: History after deletion: \(redoTarget.historyState.history.map { $0.id })")
                        }
                    }
                    undoManager.setActionName("Delete Response")
                }
            }
            
            // Delete file if chosen
            if deleteFile {
                let fileURL = URL(fileURLWithPath: path)
                let fileManager = FileManager.default
                if let dir = appState.settings.outputDirectory {
                    do {
                        try withSecureAccess(to: dir) {
                            try fileManager.removeItem(at: fileURL)
                        }
                    } catch {
                        Log.debug("Failed to delete file: \(error)")
                    }
                }
            }
            
            // Remove from UI arrays
            appState.ui.outputImages.remove(at: index)
            appState.ui.outputTexts.remove(at: index)
            appState.ui.outputPaths.remove(at: index)
            
            // Adjust index
            if !appState.ui.outputImages.isEmpty {
                appState.ui.currentOutputIndex = min(index, appState.ui.outputImages.count - 1)
            } else {
                appState.ui.currentOutputIndex = 0
            }
            
            // Show undo button
            withAnimation {
                showUndoButton = true
            }
            
            appState.ui.objectWillChange.send()
            appState.historyState.saveHistory()
            appState.historyState.objectWillChange.send()
            Log.debug("History after deletion: \(appState.historyState.history.map { $0.id })")
        }
    }
}

// MARK: - Native Video Player Views

#if os(macOS)
/// Native macOS video player with full controls, frame stepping, and timecodes
struct ResponseVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let aspectRatio: CGFloat

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFrameSteppingButtons = true
        playerView.showsTimecodes = true
        playerView.videoGravity = .resizeAspect
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
#endif

#if os(iOS)
import UIKit

/// Native iOS video player with full controls and Picture-in-Picture support
struct ResponseVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let aspectRatio: CGFloat

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        vc.videoGravity = .resizeAspect
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
    }
}
#endif
