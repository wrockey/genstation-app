// HistoryItemFullView.swift
import SwiftUI
import AVKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit  // For UIDevice on iOS
import CoreMotion
#endif
import GenStationCore

#if os(iOS)


struct ZoomPanGestureHandler: UIViewRepresentable {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var isZoomed: Bool
    let minScale: CGFloat
    let maxScale: CGFloat
    let containerSize: CGSize

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = true
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePinch))
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePan))
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        pinchGesture.delegate = context.coordinator
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(pinchGesture)
        view.addGestureRecognizer(panGesture)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.containerSize = containerSize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ZoomPanGestureHandler
        var lastScale: CGFloat = 1.0
        var lastOffset: CGSize = .zero
        var containerSize: CGSize
        var isCurrentlyZooming: Bool = false

        init(_ parent: ZoomPanGestureHandler) {
            self.parent = parent
            self.containerSize = parent.containerSize
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if isCurrentlyZooming || parent.scale > 1.01 {
                // Block TabView's UIScrollView paging
                return !(otherGestureRecognizer.view is UIScrollView)
            }
            return true
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            
            let location = gesture.location(in: gesture.view)
            let containerSize = parent.containerSize
            
            withAnimation(DS.Anim.springDefault) {
                if parent.scale > 1.05 {
                    // Zoom out fully
                    parent.scale = 1.0
                    parent.offset = .zero
                    parent.isZoomed = false
                } else {
                    // Zoom to 2.5× centered on tap point
                    let targetScale: CGFloat = 2.5
                    parent.scale = targetScale
                    parent.isZoomed = true

                    // Center the tapped point perfectly
                    let zoomCenterX = (location.x - containerSize.width / 2) * (targetScale - 1) / targetScale
                    let zoomCenterY = (location.y - containerSize.height / 2) * (targetScale - 1) / targetScale
                    parent.offset = CGSize(width: zoomCenterX, height: zoomCenterY)
                }
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastScale = parent.scale
                isCurrentlyZooming = true
                parent.isZoomed = gesture.scale > 1.0
            case .changed:
                parent.scale = min(max(lastScale * gesture.scale, parent.minScale), parent.maxScale)
                parent.isZoomed = parent.scale > 1.01
            default:
                isCurrentlyZooming = false
                if parent.scale < 1.2 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        parent.scale = 1.0
                        parent.offset = .zero
                        parent.isZoomed = false
                    }
                }
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard parent.scale > 1.01 else { return }
            switch gesture.state {
            case .began:
                lastOffset = parent.offset
                isCurrentlyZooming = true
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let maxOffsetX = max(0, (containerSize.width * parent.scale - containerSize.width) / 2)
                let maxOffsetY = max(0, (containerSize.height * parent.scale - containerSize.height) / 2)
                parent.offset = CGSize(
                    width: min(maxOffsetX, max(-maxOffsetX, lastOffset.width + translation.x)),
                    height: min(maxOffsetY, max(-maxOffsetY, lastOffset.height + translation.y))
                )
            default:
                isCurrentlyZooming = false
            }
        }
    }
}
#endif


// MARK: - Capsule Button Group
private struct ButtonGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 16) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary.opacity(0.2), lineWidth: 0.5))
    }
}

// MARK: - Glass Navigation Button
private struct GlassNavButton: View {
    let icon: String
    let size: CGFloat
    let isDisabled: Bool
    let action: () -> Void

    @State private var isPressed: Bool = false
    @State private var isHovered: Bool = false

    init(icon: String, size: CGFloat = 32, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.isDisabled = isDisabled
        self.action = action
    }

    private var iconColor: Color {
        if isDisabled {
            return Color.secondary.opacity(0.4)
        } else if isPressed {
            return Color.primary
        } else if isHovered {
            return Color.primary.opacity(0.9)
        } else {
            return Color.secondary
        }
    }

    var body: some View {
        Button {
            if !isDisabled {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                action()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(isPressed ? 0.15 : 0.08), radius: isPressed ? 4 : 8, y: isPressed ? 1 : 3)
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(isHovered ? 0.4 : 0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Simple Loading Placeholder
private struct LoadingPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.secondary.opacity(0.1))
            .aspectRatio(16/9, contentMode: .fit)
            .frame(maxWidth: 600, maxHeight: 400)
            .overlay(
                ProgressView()
                    .scaleEffect(1.5)
            )
    }
}

// MARK: - Glass Close Button
private struct GlassCloseButtonStyle: ButtonStyle {
    let size: CGFloat
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        Image(systemName: "xmark")
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundColor(isPressed ? Color.primary : (isHovered ? Color.red.opacity(0.8) : Color.secondary))
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(isPressed ? 0.18 : 0.1), radius: isPressed ? 4 : 10, y: isPressed ? 1 : 4)
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                isHovered ? Color.red.opacity(0.3) : Color.white.opacity(0.3),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

private struct GlassCloseButton: View {
    let size: CGFloat
    let action: () -> Void

    @State private var isHovered: Bool = false

    init(size: CGFloat = 36, action: @escaping () -> Void) {
        self.size = size
        self.action = action
    }

    var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            // Label is provided by ButtonStyle
            EmptyView()
        }
        .buttonStyle(GlassCloseButtonStyle(size: size, isHovered: isHovered))
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
}

struct FullHistoryItemView: View {
    let initialId: UUID
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var colorScheme
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif
    @State private var selectedId: UUID? = nil
    @State private var previousSelectedId: UUID? = nil
    @State private var showCopiedMessage: Bool = false
    @State private var showAddedMessage: Bool = false
    @State private var previousHistory: [HistoryItem] = []
    @State private var isFullScreen: Bool = false
    @State private var recentlyDeletedId: UUID? = nil
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0 // Default for videos
    @State private var isVideoPlayable: Bool = false
    @State private var videoHasAudio: Bool = false // Track if video has audio track
    @State private var player: AVPlayer? = nil // State for AVPlayer
    @State private var scrollTarget: UUID? = nil   // forces re-scroll on geometry change or lazy load
    @State private var toastMessage: String? = nil
    @State private var showToast: Bool = false
    @State private var toastAction: (() -> Void)? = nil
    @State private var showPromptBox: Bool = true
    @State private var promptBoxDragOffset: CGFloat = 0
    @State private var isCurrentVideo = false
    @State private var forceReselectTrigger: Bool = false
    @State private var deleteConfirmation: DeleteConfirmationInfo? = nil
    @State private var showGIFExportSheet: Bool = false
    @State private var isUpscaling: Bool = false
    @State private var upscaleProgress: Double = 0
    @State private var upscalingItemId: UUID? = nil
    @State private var imageDimensions: String? = nil
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
    
    private var history: [HistoryItem] {
        flattenHistory(appState.historyState.history)
    }
    
    private var currentItem: HistoryItem? {
        history.first { $0.id == selectedId }
    }
    
    private var currentIndex: Int? {
        history.firstIndex { $0.id == selectedId }
    }
        
    var body: some View {
        ZStack {
            mainContent
                .ignoresSafeArea(.all, edges: .top) // Ignore top safe area for content
            closeButton
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .zIndex(2) // Ensure close button is above content
            copiedMessageOverlay
                .zIndex(3)
            addedMessageOverlay
                .zIndex(3)
            if let message = toastMessage, showToast {
                Group {
                    if let action = toastAction {
                        LiquidGlassToast(message: message, actionLabel: "Undo", action: {
                            action()
                            withAnimation { showToast = false }
                            toastAction = nil
                        })
                    } else {
                        LiquidGlassToast(message: message)
                    }
                }
                .transition(.toastTransition)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 80)
                .zIndex(4)
                .onAppear {
                    hideToastAfterDelay()
                }
            }
        }
        .onAppear(perform: onAppear)
        .onChange(of: history, perform: onHistoryChange)
        .onChange(of: selectedId, perform: onSelectedIdChange)
        .onChange(of: currentItem) { newItem in
            Task {
                await loadVideoMetadataAndPlayer()
                isCurrentVideo = (newItem?.imagePath?.hasSuffix(".mp4") == true) && isVideoPlayable
            }
        }
        
        .sheet(item: $deleteConfirmation) { info in
                DeleteConfirmationView(
                    title: info.title,
                    message: info.message,
                    hasDeletableFiles: info.hasDeletableFiles,
                    deleteAction: { deleteFiles in
                        info.onConfirm(deleteFiles)
                    },
                    cancelAction: {
                        deleteConfirmation = nil
                    }
                )
                #if os(iOS)
                .presentationDetents([.height(260)])
                #endif
            }
        .sheet(isPresented: $showGIFExportSheet) {
            if let item = currentItem, let path = item.imagePath, path.hasSuffix(".mp4") {
                GIFExportSheet(videoURL: URL(fileURLWithPath: path))
                    .environmentObject(appState)
            }
        }
        
    }
    
    //local sheet presentation instead of modal to prevent popping back to history view
    private func presentDeleteConfirmation() {
        guard let item = currentItem else { return }
        
        let info = DeleteConfirmationInfo(
            title: "Delete Item",
            message: item.fileExists(appState: appState)
                ? "Are you sure you want to delete this item from history?"
                : "Are you sure you want to delete this item from history?\nNote: File is missing or inaccessible.",
            hasDeletableFiles: item.fileExists(appState: appState),
            onConfirm: { deleteFiles in
                self.recentlyDeletedId = item.id
                self.deleteHistoryItem(item: item, deleteFile: deleteFiles)
                self.deleteConfirmation = nil
            }
        )
        
        deleteConfirmation = info
    }
    
    private var mainContent: some View {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    pagingView(for: geometry)
                        .contextMenu {
                            if let item = currentItem {
                                HistoryCopyImageButton(item: item)
                            }
                        }
                        #if os(macOS)
                        .padding(.bottom, isCurrentVideo ? 120 : 0)   // only needed on macOS
                        #else
                        .padding(.bottom, 0)                          // iOS handles controls itself
                        #endif

                    if let item = currentItem {
                        bottomOverlay(for: item)
                    }
                }
                // Retain geometry change handler for re-centering
                .onChange(of: geometry.size) { _ in
                    // Don't set scrollTarget = nil first - just re-center directly
                    DispatchQueue.main.async {
                        scrollTarget = selectedId
                    }
                }
            }
        }
    
    @ViewBuilder private var bottomOverlay: some View {
        if let item = currentItem {
            bottomOverlay(for: item)
        } else {
            Color.clear.frame(height: 0)
        }
    }
    
    
    
    @ViewBuilder private var closeButton: some View {
#if os(iOS)
        if !isCurrentVideo {
            GlassCloseButton(size: 38) {
                dismiss()
            }
            .help("Close full view")
            .accessibilityLabel("Close")
        }
#elseif os(macOS)
        if isFullScreen {
            GlassCloseButton(size: 34) {
                dismiss()
            }
            .help("Close full view")
            .accessibilityLabel("Close")
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
#endif
    }
    
    @ViewBuilder private var copiedMessageOverlay: some View {
        if showCopiedMessage {
            LiquidGlassToast(message: "Copied to Clipboard")
                .transition(.toastTransition)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 50)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showCopiedMessage = false }
                    }
                }
        } else {
            Color.clear.frame(height: 0)
        }
    }

    @ViewBuilder private var addedMessageOverlay: some View {
        if showAddedMessage {
            LiquidGlassToast(message: "Added to Input")
                .transition(.toastTransition)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 50)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showAddedMessage = false }
                    }
                }
        } else {
            Color.clear.frame(height: 0)
        }
    }
    
    // MARK: - macOS Paging View (extracted)
    #if os(macOS)
    private struct MacPagingView: View {
        let history: [HistoryItem]
        @Binding var selectedId: UUID?
        @Binding var scrollTarget: UUID?
        let isVideoPlayable: Binding<Bool>
        @Binding var videoHasAudio: Bool
        let videoAspectRatio: Binding<CGFloat>
        let player: Binding<AVPlayer?>
        let geometry: GeometryProxy
        let isFullScreen: Bool
        
        var body: some View {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        // *** THIS IS THE FIX – use indices instead of Identifiable ***
                        ForEach(history.indices, id: \.self) { index in
                            let item = history[index]
                            HistoryImageDisplay(item: item,
                                                isVideoPlayable: isVideoPlayable,
                                                videoHasAudio: $videoHasAudio,
                                                videoAspectRatio: videoAspectRatio,
                                                player: player)
                                .frame(width: geometry.size.width,
                                       height: max(100, geometry.size.height - 100))
                                .id(item.id)                     // still needed for scrollTarget
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrollTarget, anchor: .center)
                .focusable()

                .onKeyPress { press in
                    guard press.phase == .down,
                          let idx = history.firstIndex(where: { $0.id == selectedId }),
                          !history.isEmpty else { return .ignored }
                    
                    var newIdx: Int
                    if press.key == .leftArrow {
                        newIdx = idx == 0 ? history.count - 1 : idx - 1
                    } else if press.key == .rightArrow {
                        newIdx = idx == history.count - 1 ? 0 : idx + 1
                    } else {
                        return .ignored
                    }
                    
                    let newId = history[newIdx].id
                    withAnimation {
                        selectedId = newId
                        scrollTarget = nil
                        scrollTarget = newId
                    }
                    return .handled
                }
                .id(isFullScreen)
            }
        }
    }
    #endif
    
    @ViewBuilder
    private func pagingView(for geometry: GeometryProxy) -> some View {
    #if os(iOS)
        TabView(selection: $selectedId) {
            ForEach(history) { item in
                HistoryImageDisplay(item: item,
                                    isVideoPlayable: $isVideoPlayable,
                                    videoHasAudio: $videoHasAudio,
                                    videoAspectRatio: $videoAspectRatio,
                                    player: $player)
                    .frame(width: geometry.size.width,
                           height: geometry.size.height)
                    .tag(item.id)
                    .id(item.id) // ← Critical: forces SwiftUI to re-render on ID change
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.all, edges: .top)
        .ignoresSafeArea(.container, edges: .horizontal)
        .id(forceReselectTrigger)
        .onChange(of: selectedId) { newId in
            // This forces TabView to snap to the correct page immediately
            // Without this, it lags or stays on old page
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                // No-op — just triggers re-evaluation
            }
            forceReselectTrigger.toggle()
        }
        .onChange(of: geometry.size) { _ in
            // Existing macOS scrollTarget reset...

            // Add for iOS: Force TabView rebuild and reselect
            let current = selectedId
            selectedId = nil  // Momentarily deselect
            forceReselectTrigger.toggle()  // Rebuild TabView
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    selectedId = current  // Reselect with animation
                }
            }
        }

    #else // macOS
        MacPagingView(history: history,
                      selectedId: $selectedId,
                      scrollTarget: $scrollTarget,
                      isVideoPlayable: $isVideoPlayable,
                      videoHasAudio: $videoHasAudio,
                      videoAspectRatio: $videoAspectRatio,
                      player: $player,
                      geometry: geometry,
                      isFullScreen: isFullScreen)
    #endif
    }
    private func onAppear() {
        selectedId = initialId
        scrollTarget = nil
        DispatchQueue.main.async {
            scrollTarget = initialId   // force initial centering even with lazy loading
        }
        previousHistory = history
        previousSelectedId = nil
        if let item = history.first(where: { $0.id == initialId }) {
            imageDimensions = readImageDimensions(for: item)
        }

        // Note: Don't set showPromptBox here for videos - onSelectedIdChange handles it
        // with proper animation to avoid race condition with the transition

#if os(macOS)
        updateWindowSize() // Size the window once based on initial item
        if let window = NSApp.windows.last {
            isFullScreen = window.styleMask.contains(.fullScreen)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { _ in
            isFullScreen = true
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { _ in
            isFullScreen = false
        }
#endif
    }
    
    private func onHistoryChange(newHistory: [HistoryItem]) {
        if let sid = selectedId, !newHistory.contains(where: { $0.id == sid }) {
            if newHistory.isEmpty {
                withAnimation {
                    selectedId = nil
                }
                dismiss()
            } else {
                let oldSorted = previousHistory
                if let oldIdx = oldSorted.firstIndex(where: { $0.id == sid }) {
                    let newIdx = min(oldIdx, newHistory.count - 1)
                    withAnimation {
                        selectedId = newHistory[newIdx].id
                    }
                } else {
                    withAnimation {
                        selectedId = newHistory.first?.id
                    }
                }
            }
        } else if let deletedId = recentlyDeletedId, newHistory.contains(where: { $0.id == deletedId }) {
            withAnimation {
                selectedId = deletedId
            }
            recentlyDeletedId = nil
        }
        previousHistory = newHistory
    }
    
    private func onSelectedIdChange(newValue: UUID?) {
        _ = previousSelectedId
        withAnimation {
                    scrollTarget = nil
                    scrollTarget = newValue
                }
        if let item = history.first(where: { $0.id == newValue }) {
            // Auto-hide prompt box for videos so playback controls are visible
            if item.imagePath?.hasSuffix(".mp4") == true {
                showPromptBox = false
            }

            if let mode = item.mode {
                let _ : String = mode == .gemini ? "Gemini" : mode == .grok ? item.modelUsed ?? appState.settings.selectedGrokModel : mode == .aimlapi ? item.modelUsed ?? appState.settings.selectedAIMLModel : item.workflowName ?? "ComfyUI"
            }
            imageDimensions = readImageDimensions(for: item)
        }
        previousSelectedId = newValue
        // Removed: No window resize on selectedId change
    }
    
    private struct HistoryImageDisplay: View {
        let item: HistoryItem
        @EnvironmentObject var appState: AppState
        @Binding var isVideoPlayable: Bool
        @Binding var videoHasAudio: Bool
        @Binding var videoAspectRatio: CGFloat
        @Binding var player: AVPlayer?
        @State private var thumbnail: PlatformImage?
        @State private var loadedImage: PlatformImage?
        @State private var isLoadingImage: Bool = true
        @State private var imageScale: CGFloat = 1.0
        @State private var imageOffset: CGSize = .zero
        @State private var isZoomed: Bool = false
        @State private var hasPlayedOnce = false
        private let minScale: CGFloat = 1.0
        private let maxScale: CGFloat = 5.0

        var body: some View {
            GeometryReader { geometry in
                Group {
                    // ─── VIDEO ───
                    if let path = item.imagePath, path.hasSuffix(".mp4") {
                        if isVideoPlayable, let player = player {
                            // Audio badge not needed here - AVPlayerView shows volume control for videos with audio
                            FullScreenVideoPlayer(player: player, aspectRatio: videoAspectRatio)
                                #if os(macOS)
                                .padding(.top, 38)  // Push below traffic light buttons
                                #endif
                                .ignoresSafeArea(.container, edges: .all)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.clear)
                                .clipped()
                                .onAppear {
                                        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                                        player.pause()           // ← ensures no auto-play
                                        hasPlayedOnce = true
                                    }
                                .onDisappear { player.pause() }
                        } else {
                            // Video loading state - show shimmer or thumbnail
                            if let img = thumbnail {
                                Image(platformImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(imageScale)
                                    .offset(imageOffset)
                                    .shadow(radius: 5)
                                    .transition(.opacity.animation(.easeOut(duration: 0.3)))
                            } else {
                                // Shimmer skeleton while video loads
                                LoadingPlaceholder()
                                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
                            }
                        }
                    }
                    // ─── IMAGE ───
                    else if let img = loadedImage {
                        Image(platformImage: img)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(imageScale)
                            .offset(imageOffset)
                            .shadow(radius: 5)
                            .help("Full view of generated image")
                            .accessibilityLabel("Image generated with prompt: \(item.prompt)")
                            .transition(.opacity.animation(.easeOut(duration: 0.3)))
                    }
                    else if isLoadingImage {
                        // Shimmer skeleton while image loads
                        LoadingPlaceholder()
                            .transition(.opacity.animation(.easeOut(duration: 0.2)))
                    }
                    else {
                        Text("No media available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                // ─── ZOOM/PAN GESTURES: only when we're showing an image or thumbnail (never on playable video) ───
                .overlay {
                    if item.imagePath?.hasSuffix(".mp4") == false || !isVideoPlayable {
                        #if os(iOS)
                        ZoomPanGestureHandler(
                            scale: $imageScale,
                            offset: $imageOffset,
                            isZoomed: $isZoomed,
                            minScale: minScale,
                            maxScale: maxScale,
                            containerSize: geometry.size
                        )
                        #endif
                    }
                }
                // ──── CONTENT LOADING ───
                .onAppear {
                    loadContent()
                }
                // ─── RESET ZOOM AND RELOAD WHEN SWITCHING ITEMS ───
                .onChange(of: item.id) { _ in
                    // Reset zoom state without animation to avoid potential loops
                    imageScale = 1.0
                    imageOffset = .zero
                    isZoomed = false
                    hasPlayedOnce = false
                    // Reset and reload content for new item
                    loadedImage = nil
                    thumbnail = nil
                    isLoadingImage = true
                    loadContent()
                }
                .onChange(of: player) { newPlayer in

                }
            }
        }

        private func loadContent() {
            Task {
                if let path = item.imagePath {
                    if path.hasSuffix(".mp4") {
                        // Load video thumbnail
                        thumbnail = await loadThumbnail(for: item)
                    } else {
                        // Load image asynchronously
                        let img = await loadHistoryImageAsync(for: item)
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.3)) {
                                loadedImage = img
                                isLoadingImage = false
                            }
                        }
                    }
                } else {
                    await MainActor.run {
                        isLoadingImage = false
                    }
                }
            }
        }

        private func loadHistoryImageAsync(for item: HistoryItem) async -> PlatformImage? {
            guard let path = item.imagePath, !path.hasSuffix(".mp4") else { return nil }
            let fileURL = URL(fileURLWithPath: path)

            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var image: PlatformImage? = nil
                    if let dir = appState.settings.outputDirectory {
                        let didStart = dir.startAccessingSecurityScopedResource()
                        image = PlatformImage(contentsOfFile: fileURL.path)
                        if didStart {
                            dir.stopAccessingSecurityScopedResource()
                        }
                    } else {
                        image = PlatformImage(contentsOfFile: fileURL.path)
                    }
                    continuation.resume(returning: image)
                }
            }
        }

        private func loadThumbnail(for item: HistoryItem) async -> PlatformImage? {
            guard let path = item.imagePath, path.hasSuffix(".mp4") else { return nil }
            return await LazyThumbnailView.loadFullImage(for: item, appState: appState)
        }
        
        private func fileExists(item: HistoryItem) -> Bool {
            item.fileExists(appState: appState)
        }
    }
   
    private func loadVideoMetadataAndPlayer() async {
        guard let item = currentItem, let path = item.imagePath, path.hasSuffix(".mp4") else {
            isVideoPlayable = false
            videoAspectRatio = 16.0 / 9.0
            player = nil
            return
        }
        let fileURL = URL(fileURLWithPath: path)
        guard fileExists(item: item) else {
            isVideoPlayable = false
            videoAspectRatio = 16.0 / 9.0
            player = nil
            return
        }
       
        if let dir = appState.settings.outputDirectory {
            let didStart = dir.startAccessingSecurityScopedResource()
            if didStart {
                defer { dir.stopAccessingSecurityScopedResource() }
                await loadMetadataAndPlayer(from: fileURL)
            } else {
                Log.debug("Failed to start security scope for dir: \(dir.path)")
                isVideoPlayable = false
                videoAspectRatio = 16.0 / 9.0
                player = nil
            }
        } else {
            await loadMetadataAndPlayer(from: fileURL)
        }
        // Removed: No window resize after video metadata load
    }
   
    private func loadMetadataAndPlayer(from fileURL: URL) async {
        let asset = AVAsset(url: fileURL)
        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                isVideoPlayable = false
                videoAspectRatio = 16.0 / 9.0
                videoHasAudio = false
                player = nil
                return
            }
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let naturalSize = try await tracks.first?.load(.naturalSize) ?? CGSize(width: 16, height: 9)

            // Check for audio tracks
            let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
            let hasAudio = !(audioTracks?.isEmpty ?? true)

            isVideoPlayable = true
            videoAspectRatio = naturalSize.width / naturalSize.height
            videoHasAudio = hasAudio
            player = AVPlayer(url: fileURL)
            DispatchQueue.main.async {
                self.updateWindowSize()
            }
        } catch {
            isVideoPlayable = false
            videoAspectRatio = 16.0 / 9.0
            videoHasAudio = false
            player = nil
            DispatchQueue.main.async {
                self.updateWindowSize()
            }
        }
    }
   
    private func bottomOverlay(for item: HistoryItem) -> some View {
        var creator: String? = nil
        if let mode = item.mode {
            switch mode {
            case .gemini:    creator = item.modelUsed ?? appState.settings.selectedGeminiModel
            case .grok:      creator = item.modelUsed ?? appState.settings.selectedGrokModel
            case .aimlapi:   creator = "AIML: \(item.modelUsed ?? appState.settings.selectedAIMLModel)"
            case .comfyUI:   creator = item.workflowName ?? "ComfyUI"
            }
            if let idx = item.indexInBatch, let tot = item.totalInBatch, creator != nil {
                creator! += " #\(idx + 1) of \(tot)"
            }
        }

        #if os(iOS)
        let isCompact = horizontalSizeClass == .compact
        #else
        let isCompact = false
        #endif

        return ZStack(alignment: .bottom) {
            Color.clear

            VStack(spacing: 12) {
                // Prompt Box (your beautiful version – unchanged)
                if showPromptBox {
                    VStack(spacing: 10) {
                        // Drag handle indicator (iOS only)
                        #if os(iOS)
                        Capsule()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 36, height: 5)
                            .padding(.top, 8)
                        #endif

                        HStack {
                            Spacer()
                            Button {
                                copyPromptToClipboard(item.prompt)
                                toastMessage = "Prompt copied!"
                                toastAction = nil
                                showToast = true
                                hideToastAfterDelay()
                            } label: {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, 8)
                        .padding(.top, 6)

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if item.imagePath?.hasSuffix(".mp4") == true {
                                Image(systemName: "film.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black.opacity(0.8), in: Circle())
                                    .shadow(radius: 2)
                            }

                            Text(item.prompt)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(5)
                        }
                        .padding(.horizontal, 12)

                        if let creator = creator {
                            Text("\(dateFormatter.string(from: item.date)) • \(creator)\(imageDimensions.map { " • \($0)" } ?? "")\((item.hasVideoContent ? nil : item.costUSD).map { String(format: " • $%.4f", $0) } ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .opacity(0.9)
                        }

                        HistoryRecoveryActions(item: item)

                        // Source URL — fallback retrieval for generated videos (e.g. if the
                        // automatic download failed). Persisted as soon as the URL is known.
                        if let videoUrl = item.videoUrl, !videoUrl.isEmpty {
                            HStack(spacing: 14) {
                                Image(systemName: "link")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text("Source URL")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    copyPromptToClipboard(videoUrl)
                                    toastMessage = "Video URL copied!"
                                    toastAction = nil
                                    showToast = true
                                    hideToastAfterDelay()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .help("Copy the video's source URL")
                                if let u = URL(string: videoUrl) {
                                    Button { openURLExternally(u) } label: {
                                        Image(systemName: "safari")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open the video in your browser")
                                }
                                Button {
                                    Task { await retryVideoDownload(item) }
                                } label: {
                                    Image(systemName: "arrow.down.circle")
                                }
                                .buttonStyle(.plain)
                                .help("Download the video into your library")
                            }
                            .font(.system(size: 15))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 12)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .clear, .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
                    .padding(.horizontal, 20)
                    .offset(y: promptBoxDragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Only track downward drags
                                if value.translation.height > 0 {
                                    promptBoxDragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                // Dismiss if dragged down more than 50 points
                                if value.translation.height > 50 {
                                    withAnimation(DS.Anim.springFast) {
                                        showPromptBox = false
                                        promptBoxDragOffset = 0
                                    }
                                } else {
                                    // Snap back
                                    withAnimation(DS.Anim.springFast) {
                                        promptBoxDragOffset = 0
                                    }
                                }
                            }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Video playback hides the prompt panel; billing stays visible independently.
                if item.hasVideoContent {
                    HistoryCostLabel(item: item)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }

                // ——————— SMART ACTION BAR – No scrolling in iPhone landscape ———————
                HStack(spacing: 0) {
                    #if os(iOS)
                    let isCompact = horizontalSizeClass == .compact
                    // Detect true landscape on iPhone (both size classes compact)
                    let isLandscape = verticalSizeClass == .compact && horizontalSizeClass == .compact
                    #else
                    let isCompact = false
                    let isLandscape = false
                    #endif

                    // Dynamic sizing – smaller in iPhone landscape so it fits without scrolling
                    let iconSize: CGFloat      = isLandscape ? 28 : 34
                    let smallIconSize: CGFloat = isLandscape ? 24 : 28
                    let coreSpacing: CGFloat   = isLandscape ? 18 : 22
                    let outerSpacing: CGFloat  = isLandscape ? 14 : 20          // ← this was missing!
                    let vPadding: CGFloat      = isLandscape ? 10 : 12

                    if isCompact && !isLandscape {
                        // iPhone portrait → scrollable compact bar
                        ScrollView(.horizontal, showsIndicators: false) {
                            actionButtonsRow(
                                iconSize: iconSize,
                                smallIconSize: smallIconSize,
                                coreSpacing: coreSpacing,
                                outerSpacing: outerSpacing,   // ← now passed correctly
                                item: item
                            )
                            .padding(.horizontal, outerSpacing)
                        }
                        .padding(.vertical, vPadding)
                    } else {
                        // iPhone landscape, iPad, macOS → full width, no scroll
                        actionButtonsRow(
                            iconSize: iconSize,
                            smallIconSize: smallIconSize,
                            coreSpacing: coreSpacing,
                            outerSpacing: outerSpacing,       // ← passed here too
                            item: item
                        )
                        .padding(.horizontal, isLandscape ? 20 : 28)
                        .padding(.vertical, isLandscape ? 12 : 16)
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            }
            .padding(.bottom, 20)
            .ignoresSafeArea(edges: .bottom)
        }
    }
    
    @ViewBuilder
    private func actionButtonsRow(
        iconSize: CGFloat,
        smallIconSize: CGFloat,
        coreSpacing: CGFloat,
        outerSpacing: CGFloat,
        item: HistoryItem
    ) -> some View {
        HStack(spacing: outerSpacing) {
            // First / Prev
            #if os(macOS)
            GlassNavButton(icon: "chevron.left", size: smallIconSize + 8) {
                guard let idx = currentIndex, !history.isEmpty else { return }
                let newIdx = idx == 0 ? history.count - 1 : idx - 1
                withAnimation { selectedId = history[newIdx].id }
            }
            .help("Previous item")
            .accessibilityLabel("Scroll to previous item")
            #else
            GlassNavButton(icon: "chevron.left.2", size: 36, isDisabled: currentIndex == 0) {
                guard let first = history.first else { return }
                withAnimation { selectedId = first.id }
            }
            .accessibilityLabel("Jump to first")
            #endif

            // Prompt Toggle
            Button {
                withAnimation(DS.Anim.springDefault) { showPromptBox.toggle() }
            } label: {
                Image(systemName: showPromptBox ? "rectangle.bottomhalf.inset.filled" : "rectangle")
                    .font(.system(size: iconSize + 2, weight: .medium))
                    .foregroundStyle(showPromptBox ? Color.accentColor : .secondary.opacity(0.65))
            }
            .help("Show/hide prompt overlay")
            .accessibilityLabel("Display prompt overlay")

            Spacer(minLength: 12)

            Menu("Media actions") { HistoryDraftActions(item: item) }

            // Core Actions - Grouped in capsule for visual hierarchy
            ButtonGroup {
                Button {
                    if item.imagePath?.hasSuffix(".mp4") == true, isVideoPlayable, let player = player {
                        Task { await addVideoFrameToInput(item: item, at: player.currentTime()) }
                    } else {
                        addToInputImages(item: item)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: iconSize))
                        .foregroundStyle(
                            appState.canAddImages && appState.ui.imageSlots.count < appState.maxImageSlots
                                ? .blue : .gray
                        )
                }
                .disabled(!appState.canAddImages || appState.ui.imageSlots.count >= appState.maxImageSlots)
                .help(
                    item.imagePath?.hasSuffix(".mp4") == true && isVideoPlayable
                        ? "Add current video frame to input images"
                        : "Add to input images"
                )
                .accessibilityLabel(
                    item.imagePath?.hasSuffix(".mp4") == true && isVideoPlayable
                        ? "Add current video frame to input images"
                        : "Add to input images"
                )

                // Select button (checkmark)
                Button {
                    if appState.historyState.multiSelection.contains(item.id) {
                        appState.historyState.multiSelection.remove(item.id)
                        toastMessage = "Removed from selection"
                    } else {
                        appState.historyState.multiSelection.insert(item.id)
                        toastMessage = "Added to selection"
                    }
                    toastAction = nil
                    showToast = true
                    hideToastAfterDelay()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: iconSize))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            appState.historyState.multiSelection.contains(item.id)
                                ? .blue
                                : .secondary.opacity(0.35)
                        )
                }
                .contentShape(Rectangle())
                .help("Select item")
                .accessibilityLabel("Add to selected item list")
            }
            #if os(iOS)
            .haptic()
            #endif

            Spacer(minLength: 12)

            // Last / Next
            #if os(macOS)
            GlassNavButton(icon: "chevron.right", size: smallIconSize + 8) {
                guard let idx = currentIndex, !history.isEmpty else { return }
                let newIdx = idx == history.count - 1 ? 0 : idx + 1
                withAnimation { selectedId = history[newIdx].id }
            }
            .help("Next item")
            .accessibilityLabel("Scroll to next item")
            #else
            GlassNavButton(icon: "chevron.right.2", size: 36, isDisabled: currentIndex == history.count - 1) {
                guard let last = history.last else { return }
                withAnimation { selectedId = last.id }
            }
            .accessibilityLabel("Jump to last")
            #endif

            // Save
#if os(iOS)
            if !(item.imagePath?.hasSuffix(".mp4") == true) {
                let hasSelection = !appState.historyState.multiSelection.isEmpty
                Button {
                    Task {
                        let itemsToSave: [HistoryItem]
                        if hasSelection {
                            itemsToSave = appState.historyState.findEntries(with: appState.historyState.multiSelection).flatMap { $0.allItems }
                        } else {
                            itemsToSave = [item]
                        }
                        let (success, total) = await PhotosLibraryHelper.saveToPhotosLibrary(items: itemsToSave, appState: appState)
                        await MainActor.run {
                            if hasSelection {
                                toastMessage = success == total ? "Saved \(success) items to Photos!" : "Saved \(success)/\(total) to Photos"
                            } else {
                                toastMessage = success == 1 ? "Saved to Photos!" : "Failed to save"
                            }
                            toastAction = nil
                            showToast = true
                            hideToastAfterDelay()
                        }
                    }
                } label: {
                    Image(systemName: hasSelection ? "photo.on.rectangle.angled" : "photo.on.rectangle")
                        .font(.system(size: iconSize - 2))
                        .foregroundStyle(.green)
                }
                .help(hasSelection ? "Save selected items to Photos" : "Save image to Photos")
                .accessibilityLabel(hasSelection ? "Save selected items to Photos" : "Save image to Photos")
            }
            #else
            Button {
                Task { await saveSelectedHistoryItemsToFolder() }
            } label: {
                let hasSelection = !appState.historyState.multiSelection.isEmpty
                Image(systemName: hasSelection ? "square.and.arrow.down.on.square" : "square.and.arrow.down")
                    .font(.system(size: iconSize - 2))
                    .foregroundStyle(.blue)
            }
            .help(!appState.historyState.multiSelection.isEmpty ? "Export selected items" : "Save item")
            .accessibilityLabel(!appState.historyState.multiSelection.isEmpty ? "Export selected items to folder" : "Save to folder")
            #endif

            // Upscale 4x (images only)
            if UpscaleService.isSupported() && !(item.imagePath?.hasSuffix(".mp4") == true) {
                let isUpscalingThisItem = isUpscaling && upscalingItemId == item.id
                Button {
                    guard !isUpscaling else { return }
                    isUpscaling = true
                    upscalingItemId = item.id
                    upscaleProgress = 0
                    toastMessage = "Upscaling 4x..."
                    toastAction = nil
                    showToast = true
                    Task {
                        do {
                            let newItem = try await UpscaleService.upscaleHistoryItem(
                                item,
                                appState: appState,
                                progressHandler: { progress in
                                    Task { @MainActor in
                                        upscaleProgress = progress
                                        toastMessage = "Upscaling... \(Int(progress * 100))%"
                                        showToast = true
                                    }
                                }
                            )
                            isUpscaling = false
                            upscalingItemId = nil
                            toastMessage = "Upscaled image saved!"
                            toastAction = nil
                            showToast = true
                            hideToastAfterDelay()
                            selectedId = newItem.id
                        } catch {
                            isUpscaling = false
                            upscalingItemId = nil
                            toastMessage = error.localizedDescription
                            toastAction = nil
                            showToast = true
                            hideToastAfterDelay()
                        }
                    }
                } label: {
                    if isUpscalingThisItem {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: iconSize - 2))
                            .foregroundStyle(.purple)
                    }
                }
                .disabled(isUpscaling)
                .help("Upscale image 4x with Real-ESRGAN")
                .accessibilityLabel("Upscale 4x")
            }

            // GIF Export (video only)
            if item.imagePath?.hasSuffix(".mp4") == true, isVideoPlayable {
                Button {
                    showGIFExportSheet = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: iconSize - 2))
                        .foregroundStyle(.orange)
                }
                .help("Export video as GIF")
                .accessibilityLabel("Export as GIF")
            }

            // Delete
            Button(role: .destructive) {
                presentDeleteConfirmation()
            } label: {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: smallIconSize))
                    .foregroundStyle(.red.opacity(0.9))
            }
            .help("Delete")
            .accessibilityLabel("Delete item")
        }
    }

    // ——————— EXTRACTED: All Action Buttons (used by both layouts) ———————
    @ViewBuilder
    private func compactActionButtons(item: HistoryItem) -> some View {
        // First / Prev
        #if os(macOS)
        GlassNavButton(icon: "chevron.left", size: 34) {
            guard let idx = currentIndex, !history.isEmpty else { return }
            let newIdx = idx == 0 ? history.count - 1 : idx - 1
            withAnimation { selectedId = history[newIdx].id }
        }
        .accessibilityLabel("Previous item")
        #else
        GlassNavButton(icon: "chevron.left.2", size: 32, isDisabled: currentIndex == 0) {
            guard let first = history.first else { return }
            withAnimation { selectedId = first.id }
        }
        .accessibilityLabel("Jump to first")
        #endif

        // Prompt Toggle
        Button {
            withAnimation(DS.Anim.springDefault) {
                showPromptBox.toggle()
            }
        } label: {
            Image(systemName: showPromptBox ? "rectangle.bottomhalf.inset.filled" : "rectangle")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(showPromptBox ? Color.accentColor : .secondary.opacity(0.65))
        }
        .accessibilityLabel(showPromptBox ? "Hide prompt" : "Show prompt")

        Spacer(minLength: 12)

        // Core Actions
        HStack(spacing: 22) {
            Button {
                if item.imagePath?.hasSuffix(".mp4") == true, isVideoPlayable, let player = player {
                    Task { await addVideoFrameToInput(item: item, at: player.currentTime()) }
                } else {
                    addToInputImages(item: item)
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(
                        appState.canAddImages && appState.ui.imageSlots.count < appState.maxImageSlots
                        ? .blue : .gray
                    )
            }
            .disabled(!appState.canAddImages || appState.ui.imageSlots.count >= appState.maxImageSlots)

            Button {
                if appState.historyState.multiSelection.contains(item.id) {
                    appState.historyState.multiSelection.remove(item.id)
                    toastMessage = "Removed from selection"
                } else {
                    appState.historyState.multiSelection.insert(item.id)
                    toastMessage = "Added to selection"
                }
                toastAction = nil
                showToast = true
                hideToastAfterDelay()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        appState.historyState.multiSelection.contains(item.id)
                            ? .blue
                            : .secondary.opacity(0.35)
                    )
            }
            .contentShape(Rectangle())
        }

        Spacer(minLength: 12)

        // Last / Next
        #if os(macOS)
        GlassNavButton(icon: "chevron.right", size: 34) {
            guard let idx = currentIndex, !history.isEmpty else { return }
            let newIdx = idx == history.count - 1 ? 0 : idx + 1
            withAnimation { selectedId = history[newIdx].id }
        }
        .accessibilityLabel("Next item")
        #else
        GlassNavButton(icon: "chevron.right.2", size: 32, isDisabled: currentIndex == history.count - 1) {
            guard let last = history.last else { return }
            withAnimation { selectedId = last.id }
        }
        .accessibilityLabel("Jump to last")
        #endif

        // Save
        #if os(iOS)
        Button {
            let hasSelection = !appState.historyState.multiSelection.isEmpty
            Task {
                let itemsToSave: [HistoryItem]
                if hasSelection {
                    itemsToSave = appState.historyState.findEntries(with: appState.historyState.multiSelection).flatMap { $0.allItems }
                } else {
                    itemsToSave = [item]
                }
                let (success, total) = await PhotosLibraryHelper.saveToPhotosLibrary(items: itemsToSave, appState: appState)
                await MainActor.run {
                    if hasSelection {
                        toastMessage = success == total ? "Saved \(success) items to Photos!" : "Saved \(success)/\(total) to Photos"
                    } else {
                        toastMessage = success == 1 ? "Saved to Photos!" : "Failed to save"
                    }
                    toastAction = nil
                    showToast = true
                    hideToastAfterDelay()
                }
            }
        } label: {
            let hasSelection = !appState.historyState.multiSelection.isEmpty
            Image(systemName: hasSelection ? "photo.on.rectangle.angled" : "photo.on.rectangle")
                .font(.system(size: 32))
                .foregroundStyle(.green)
        }
        #else
        Button {
            Task { await saveSelectedHistoryItemsToFolder() }
        } label: {
            let hasSelection = !appState.historyState.multiSelection.isEmpty
            Image(systemName: hasSelection ? "square.and.arrow.down.on.square" : "square.and.arrow.down")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
        }
        #endif

        // Delete
        Button(role: .destructive) {
            presentDeleteConfirmation()
        } label: {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.red.opacity(0.9))
        }
    }
    
    
    private func readImageDimensions(for item: HistoryItem) -> String? {
        guard let path = item.imagePath, !path.hasSuffix(".mp4") else { return nil }
        let url = URL(fileURLWithPath: path)

        var didStart = false
        if let dir = appState.settings.outputDirectory {
            didStart = dir.startAccessingSecurityScopedResource()
        }
        defer {
            if didStart { appState.settings.outputDirectory?.stopAccessingSecurityScopedResource() }
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = props[kCGImagePropertyPixelWidth as String] as? Int,
              let h = props[kCGImagePropertyPixelHeight as String] as? Int else {
            return nil
        }
        return "\(w)×\(h)"
    }

    private func hideToastAfterDelay() {
        // Don't auto-hide while upscaling — progress updates drive the toast
        guard !isUpscaling else { return }
        // Longer delay (4s) when toast has undo action, shorter (2s) for simple toasts
        let delay: TimeInterval = toastAction != nil ? 4.0 : 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation {
                showToast = false
                toastAction = nil
            }
        }
    }

    #if os (macOS)
    @MainActor
    private func saveSelectedHistoryItemsToFolder() async {
        let items: [HistoryItem]
        if !appState.historyState.multiSelection.isEmpty {
            items = appState.historyState.findEntries(with: appState.historyState.multiSelection).flatMap { $0.allItems }
        } else if let item = currentItem {
            items = [item]
        } else {
            toastMessage = "No item to save"
            showToast = true
            hideToastAfterDelay()
            return
        }
        // App-owned originals remain exportable without a custom output folder.
        let outputDir = appState.settings.outputDirectory
        let dirAccessStarted = outputDir?.startAccessingSecurityScopedResource() ?? false
        defer { if dirAccessStarted { outputDir?.stopAccessingSecurityScopedResource() } }
        var successCount = 0
        var failedCount = 0
        if items.count == 1 {
            await saveSingleItem(items[0], success: &successCount, failed: &failedCount)
        } else {
            await saveMultipleItems(items, success: &successCount, failed: &failedCount)
        }
        if successCount == 0 && failedCount == 0 {
        return  // Silently ignore cancellation
        }
        let message: String
        if failedCount == 0 {
            message = "Saved successfully!"
        } else if successCount == 0 {
            message = "Failed to save"
        } else {
            message = "Saved \(successCount)/\(items.count) items"
        }
        toastMessage = message
        showToast = true
        hideToastAfterDelay()
    }

    @MainActor
    private func presentExportPanel(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else {
                panel.begin { continuation.resume(returning: $0) }
            }
        }
    }

    // MARK: - Single Item Save (NSSavePanel)
    private func saveSingleItem(_ item: HistoryItem, success: inout Int, failed: inout Int) async {
        guard let srcPath = item.imagePath,
              item.fileExists(appState: appState) else {
            failed += 1
            return
        }

        let srcURL = URL(fileURLWithPath: srcPath)
        let filename = srcURL.lastPathComponent
        let isVideo = srcURL.pathExtension.lowercased() == "mp4"

        let savePanel = NSSavePanel()
        savePanel.title = isVideo ? "Save Video" : "Save Image"
        savePanel.prompt = "Save"
        savePanel.nameFieldStringValue = filename

        // Export preserves original bytes; changing the suffix is not conversion.
        if let originalType = UTType(filenameExtension: srcURL.pathExtension) {
            savePanel.allowedContentTypes = [originalType]
        }
        savePanel.canCreateDirectories = true
        guard await presentExportPanel(savePanel) == .OK, let destURL = savePanel.url else {
            return
        }

        do {
            if srcURL.standardizedFileURL != destURL.standardizedFileURL {
                let data = try Data(contentsOf: srcURL)
                try data.write(to: destURL, options: .atomic)
            }
            success += 1

            // Reveal in Finder
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destURL.deletingLastPathComponent().path)
        } catch {
            Log.debug("Failed to save \(filename): \(error)")
            failed += 1
        }
    }
    // MARK: - Multiple Items Save (NSOpenPanel as Folder Picker)
    private func saveMultipleItems(_ items: [HistoryItem], success: inout Int, failed: inout Int) async {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Folder to Save \(items.count) Images"
        openPanel.prompt = "Select"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = []  // ← Updated: Replaces deprecated allowedFileTypes
        openPanel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        
        guard await presentExportPanel(openPanel) == .OK, let destinationFolder = openPanel.url else {
            return  // User cancelled
        }
        
        let fm = FileManager.default
        for item in items {
            guard let srcPath = item.imagePath,
                  item.fileExists(appState: appState) else {
                failed += 1
                continue
            }
            
            let srcURL = URL(fileURLWithPath: srcPath)
            let filename = srcURL.lastPathComponent
            var destURL = destinationFolder.appendingPathComponent(filename)
            
            // Avoid collisions: append (1), (2), etc.
            var counter = 1
            while fm.fileExists(atPath: destURL.path) {
                let nameWithoutExt = destURL.deletingPathExtension().lastPathComponent
                let ext = destURL.pathExtension
                let newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
                destURL = destinationFolder.appendingPathComponent(newName)
                counter += 1
            }
            
            do {
                let data = try Data(contentsOf: srcURL)
                try data.write(to: destURL, options: .atomic)
                success += 1
            } catch {
                Log.debug("Failed to save \(filename): \(error)")
                failed += 1
            }
        }
        
        // Reveal the folder in Finder
        if success > 0 {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destinationFolder.path)
        }
    }
    #endif
    
    private func deleteHistoryItem(item: HistoryItem, deleteFile: Bool) {
        // Remove from session gallery
        appState.ui.sessionGeneratedIDs.removeAll { $0 == item.id }
        appState.ui.objectWillChange.send()

        let oldHistory = appState.historyState.history
        let currentHistory = flattenHistory(appState.historyState.history)
        guard let oldIdx = currentHistory.firstIndex(where: { $0.id == item.id }) else { return }
       
        if deleteFile, let path = item.imagePath {
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
            } else {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    Log.debug("Failed to delete file: \(error)")
                }
            }
        }
       
        var snapshot = appState.historyState.history
        _ = appState.historyState.findAndRemoveEntry(id: item.id, in: &snapshot)
        appState.historyState.history = snapshot
        appState.historyState.saveHistory()
       
        if let undoManager = undoManager {
            _ = appState.historyState.history
            undoManager.registerUndo(withTarget: appState.historyState) { target in
                let historyBeforeUndo = target.history
                target.history = oldHistory
                target.objectWillChange.send()
                target.saveHistory()
                undoManager.registerUndo(withTarget: target) { redoTarget in
                    redoTarget.history = historyBeforeUndo
                    redoTarget.objectWillChange.send()
                    redoTarget.saveHistory()
                }
            }
            undoManager.setActionName("Delete Item")
        }

        // Show toast with undo action
        toastMessage = "Item deleted"
        toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
            undoManager?.undo()
        } : nil
        showToast = true
        hideToastAfterDelay()

        let newHistory = flattenHistory(appState.historyState.history)
        if newHistory.isEmpty {
            withAnimation {
                selectedId = nil
            }
            dismiss()
        } else {
            let newIdx = min(oldIdx, newHistory.count - 1)
            withAnimation {
                selectedId = newHistory[newIdx].id
            }
        }
    }
   
    private func copyPromptToClipboard(_ prompt: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
#elseif os(iOS)
        UIPasteboard.general.string = prompt
#endif
    }

    private func openURLExternally(_ url: URL) {
#if os(macOS)
        NSWorkspace.shared.open(url)
#elseif os(iOS)
        UIApplication.shared.open(url)
#endif
    }

    /// Re-downloads a generated video from its persisted source URL into the output directory and
    /// links it back to the history item — recovers a video whose automatic download failed.
    private func retryVideoDownload(_ item: HistoryItem) async {
        appState.jobQueue.redownload(item)
    }

    private func withSecureAccess<T>(to url: URL, operation: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }
   
    private func addToInputImages(item: HistoryItem) {
        guard appState.canAddImages, appState.maxImageSlots > 0 else {
            toastMessage = "Input images not supported in this mode or no input nodes available."
            showToast = true
            hideToastAfterDelay()
            return
        }

        // Check if we're at max capacity
        let atMaxCapacity = appState.ui.imageSlots.count >= appState.maxImageSlots

        // Find first empty slot (no image loaded) if at max capacity
        let emptySlotIndex = atMaxCapacity ? appState.ui.imageSlots.firstIndex(where: { $0.path.isEmpty }) : nil

        // If at max capacity and no empty slots to replace, reject
        if atMaxCapacity && emptySlotIndex == nil {
            toastMessage = "Maximum number of image slots reached (\(appState.maxImageSlots))."
            showToast = true
            hideToastAfterDelay()
            return
        }

        guard let path = item.imagePath else { return }
        let fileURL = URL(fileURLWithPath: path)

        Task {
            // Load the full-resolution image from disk
            guard let fullImage = await LazyThumbnailView.loadFullImage(for: item, appState: appState) else {
                await MainActor.run {
                    toastMessage = "Failed to load image"
                    showToast = true
                    hideToastAfterDelay()
                }
                return
            }

            // Create thumbnail immediately (this is the memory-saving step)
            let thumbnail = fullImage.downscaled(toMaxPixels: 512)

            // Save full image to temp folder so we can release it from RAM
            let tempURL = AppStorageContext.current.temporaryDirectory
                .appendingPathComponent("hist_\(UUID().uuidString).\(fileURL.pathExtension)")

            if let pngData = fullImage.pngData() {
                try? pngData.write(to: tempURL)
            } else {
                await MainActor.run {
                    toastMessage = "Failed to save image data"
                    showToast = true
                    hideToastAfterDelay()
                }
                return
            }

            // Create new memory-safe ImageSlot
            let newSlot = UIState.ImageSlot(
                thumbnail: thumbnail,
                fullResolutionURL: tempURL,
                originalData: fullImage.pngData() // Optional: for re-upload
            )

            await MainActor.run {
                if let index = emptySlotIndex {
                    // Replace the empty slot
                    appState.ui.imageSlots[index] = newSlot
                    toastMessage = "Image replaced in input"
                } else {
                    // Add as new slot
                    appState.ui.imageSlots.append(newSlot)
                    toastMessage = "Item added to input"
                }
                showToast = true
                hideToastAfterDelay()
            }
        }
    }

    private func addVideoFrameToInput(item: HistoryItem, at time: CMTime) async {
        guard appState.canAddImages, appState.maxImageSlots > 0 else {
            await MainActor.run {
                showAddedMessage = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showAddedMessage = false
                    }
                }
            }
            return
        }
        guard appState.ui.imageSlots.count < appState.maxImageSlots else {
            await MainActor.run {
                showAddedMessage = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showAddedMessage = false
                    }
                }
            }
            return
        }
       
        guard let path = item.imagePath, path.hasSuffix(".mp4") else { return }
        let fileURL = URL(fileURLWithPath: path)
        if let dir = appState.settings.outputDirectory {
            let didStart = dir.startAccessingSecurityScopedResource()
            if didStart {
                defer { dir.stopAccessingSecurityScopedResource() }
                await extractAndAddFrame(from: fileURL, at: time)
            } else {
                Log.debug("Failed to start security scope for dir: \(dir.path)")
                return
            }
        } else {
            await extractAndAddFrame(from: fileURL, at: time)
        }
    }
   
    private func extractAndAddFrame(from fileURL: URL, at time: CMTime) async {
        let asset = AVAsset(url: fileURL)
        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else { return }
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            generator.maximumSize = CGSize(width: 2048, height: 2048) // Optional: limit size
            
            let value = try await generator.image(at: time)
            let cgImage = value.image
            
            #if os(macOS)
            let fullImage = PlatformImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            #elseif os(iOS)
            let fullImage = PlatformImage(cgImage: cgImage)
            #endif
            
            // Create small thumbnail immediately
            let thumbnail = fullImage.downscaled(toMaxPixels: 512)
            
            // Save full-res frame to temp folder (so we can release the huge image from RAM)
            let tempURL = AppStorageContext.current.temporaryDirectory
                .appendingPathComponent("frame_\(UUID().uuidString).png")
            
            if let pngData = fullImage.pngData() {
                try? pngData.write(to: tempURL)
            } else {
                return
            }
            
            // Use the NEW memory-safe ImageSlot
            let newSlot = UIState.ImageSlot(
                thumbnail: thumbnail,
                fullResolutionURL: tempURL,
                originalData: fullImage.pngData() // Optional: for upload later
            )
            
            await MainActor.run {
                appState.ui.imageSlots.append(newSlot)
                showAddedMessage = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showAddedMessage = false
                    }
                }
            }
            
        } catch {
            Log.debug("Failed to extract video frame: \(error)")
        }
    }
   
    private func updateWindowSize() {
    #if os(macOS)
        // Skip if full-screen (preserves full-screen state)
        if isFullScreen { return }
        
        guard let item = currentItem,
              let window = NSApp.windows.last,   // works reliably for this window
              let screen = NSScreen.main else {
            return
        }
        
        let bottomHeight: CGFloat = 100
        let minWidth: CGFloat = 1000
        let minHeight: CGFloat = 700
        
        var desiredSize: CGSize
        
        if item.imagePath?.hasSuffix(".mp4") ?? false, isVideoPlayable {
            desiredSize = CGSize(width: max(videoAspectRatio * 600, minWidth),
                                 height: 600 + bottomHeight)
        } else {
            var platformImage: PlatformImage? = nil
            if let path = item.imagePath, !path.hasSuffix(".mp4") {
                let fileURL = URL(fileURLWithPath: path)
                if let dir = appState.settings.outputDirectory {
                    let didStart = dir.startAccessingSecurityScopedResource()
                    platformImage = PlatformImage(contentsOfFile: fileURL.path)
                    if didStart { dir.stopAccessingSecurityScopedResource() }
                } else {
                    platformImage = PlatformImage(contentsOfFile: fileURL.path)
                }
            }
            if let platformImage = platformImage {
                let imageSize = platformImage.size
                desiredSize = CGSize(width: max(imageSize.width, minWidth),
                                     height: imageSize.height + bottomHeight)
            } else {
                // Fallback for missing media (rare)
                desiredSize = CGSize(width: 1200, height: 800 + bottomHeight)
            }
        }
        
        let screenSize = screen.visibleFrame.size
        let margin: CGFloat = 100
        let maxSize = CGSize(width: screenSize.width - margin,
                             height: screenSize.height - margin)
        
        let scale = min(1.0, min(maxSize.width / desiredSize.width,
                                maxSize.height / desiredSize.height))
        let finalSize = CGSize(width: desiredSize.width * scale,
                               height: desiredSize.height * scale)
        
        let currentSize = window.frame.size
        if currentSize.width < minWidth || currentSize.height < minHeight {
            window.setContentSize(finalSize)
            window.center()
        } else {
            // Preserve user's larger resize, only grow if needed
            window.setContentSize(CGSize(width: max(currentSize.width, finalSize.width),
                                         height: max(currentSize.height, finalSize.height)))
        }
    #endif
    }
   
    private func flattenHistory(_ entries: [HistoryEntry]) -> [HistoryItem] {
        var result: [HistoryItem] = []
        var seenIDs = Set<UUID>()
        
        func sortedEntries(_ entries: [HistoryEntry]) -> [HistoryEntry] {
            var folders: [Folder] = []
            var items: [HistoryItem] = []
            for entry in entries {
                switch entry {
                case .folder(var folder):
                    folder.children = sortedEntries(folder.children)
                    folders.append(folder)
                case .item(let item):
                    items.append(item)
                }
            }
            folders.sort { $0.name.lowercased() < $1.name.lowercased() }
            items.sort { $0.date > $1.date }
            return folders.map { .folder($0) } + items.map { .item($0) }
        }

        func walk(_ entry: HistoryEntry) {
            switch entry {
            case .item(let item):
                if seenIDs.insert(item.id).inserted {
                    result.append(item)
                }
            case .folder(let folder):
                let sortedChildren = sortedEntries(folder.children)
                for child in sortedChildren {
                    walk(child)
                }
            }
        }

        let sortedTop = sortedEntries(entries)
        for entry in sortedTop {
            walk(entry)
        }
        
        return result
    }
   
    private func fileExists(item: HistoryItem) -> Bool {
        item.fileExists(appState: appState)
    }
}

private struct FullScreenVideoPlayer: View {
    let player: AVPlayer
    let aspectRatio: CGFloat
    
    var body: some View {
#if os(iOS)
        IOSFullScreenVideoPlayer(player: player, aspectRatio: aspectRatio)
#else // macOS
        AVPlayerViewRepresentable(player: player, aspectRatio: aspectRatio)
#endif
    }
}

#if os(iOS)
private struct IOSFullScreenVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let aspectRatio: CGFloat

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.updatesNowPlayingInfoCenter = false
        vc.view.backgroundColor = .clear
        vc.videoGravity = .resizeAspect
        vc.allowsPictureInPicturePlayback = true
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
    }
}
#endif

#if os(macOS)
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer
    let aspectRatio: CGFloat

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline  // Shows controls at bottom
        playerView.showsFullScreenToggleButton = false
        playerView.showsFrameSteppingButtons = true
        playerView.videoGravity = AVLayerVideoGravity.resizeAspect
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
#endif

    extension View {
        /// Makes tiny buttons easy to tap
        func hitTestingPadding(_ padding: CGFloat = 12) -> some View {
            self.contentShape(Rectangle().inset(by: -padding))
        }
    }

#if os (iOS)
private extension View {
    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) -> some View {
        self.onTapGesture {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: style).impactOccurred()
            #endif
        }
    }
}
#endif
