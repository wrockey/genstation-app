//
// MarkupView.swift
//
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import PencilKit
#endif

// Preference key for image frame
struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// Markup State for undo (macOS)
struct MarkupState {
    let annotations: [Annotation]
    let textBoxes: [TextBox]
    var maskStrokes: [Annotation] = []
}

#if os(iOS)
enum UndoActionType {
    case stroke
    case text
    case clearAll(savedDrawing: PKDrawing, savedTextBoxes: [TextBox])
}
#endif

// Annotation enum
enum Annotation: Identifiable {
    case stroke(Stroke)
    case fill(Fill)
    case erase(EraseStroke)
    
    var id: UUID {
        switch self {
        case .stroke(let s): return s.id
        case .fill(let f): return f.id
        case .erase(let e): return e.id
        }
    }
}

// Add Fill struct
struct Fill: Identifiable {
    let id = UUID()
    let image: PlatformImage
}

struct Stroke: Identifiable {
    let id = UUID()
    var path: Path
    let color: Color
    let lineWidth: CGFloat
}

struct EraseStroke: Identifiable {
    let id = UUID()
    var path: Path
    let lineWidth: CGFloat
}

struct TextBox: Identifiable {
    let id = UUID()
    var text: String
    var position: CGPoint
    var color: Color = .black
}

// Extension for conditional modifier
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#if os(macOS)
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class WindowCloseDelegate: NSObject, NSWindowDelegate {
    var onAttemptClose: (() -> Bool)?
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return onAttemptClose?() ?? true
    }
}
#endif

// Free function for off-main-thread flood fill computation
private func createFilledMaskAsync(
    seed: CGPoint, color: Color,
    annotations: [Annotation],
    imageFrame: CGRect,
    image: PlatformImage
) -> PlatformImage? {
    guard imageFrame.size != .zero else {
        Log.debug("DEBUG: Skipping fill due to zero image frame")
        return nil
    }

    let size = image.platformSize
    let annotationScale = size.width / imageFrame.size.width
    let scaledSeed = CGPoint(x: seed.x * annotationScale, y: seed.y * annotationScale)

    // Create boundary image
    let width = Int(size.width)
    let height = Int(size.height)
    let bytesPerRow = ((4 * width + 15) / 16) * 16
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

    guard let boundaryContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
        Log.debug("DEBUG: Failed to create boundary context")
        return nil
    }

    boundaryContext.setFillColor(red: 0, green: 0, blue: 0, alpha: 0)
    boundaryContext.fill(CGRect(origin: .zero, size: size))
    boundaryContext.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    boundaryContext.setBlendMode(.normal)

    for annotation in annotations {
        switch annotation {
        case .fill(let fill):
            if let cgImage = fill.image.asCGImage {
                boundaryContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
        case .stroke(let stroke):
            boundaryContext.saveGState()
            boundaryContext.translateBy(x: 0, y: size.height)
            boundaryContext.scaleBy(x: 1, y: -1)
            let scaledPath = stroke.path.applying(CGAffineTransform(scaleX: annotationScale, y: annotationScale))
            boundaryContext.addPath(scaledPath.cgPath)
            boundaryContext.setLineWidth(stroke.lineWidth * annotationScale)
            boundaryContext.setLineCap(.round)
            boundaryContext.setLineJoin(.round)
            boundaryContext.strokePath()
            boundaryContext.restoreGState()
        case .erase(let erase):
            boundaryContext.setBlendMode(.clear)
            boundaryContext.saveGState()
            boundaryContext.translateBy(x: 0, y: size.height)
            boundaryContext.scaleBy(x: 1, y: -1)
            let scaledPath = erase.path.applying(CGAffineTransform(scaleX: annotationScale, y: annotationScale))
            boundaryContext.addPath(scaledPath.cgPath)
            boundaryContext.setLineWidth(erase.lineWidth * annotationScale)
            boundaryContext.setLineCap(.round)
            boundaryContext.setLineJoin(.round)
            boundaryContext.strokePath()
            boundaryContext.restoreGState()
            boundaryContext.setBlendMode(.normal)
        }
    }

    guard let boundaryCGImage = boundaryContext.makeImage() else {
        Log.debug("DEBUG: Failed to make boundary CGImage")
        return nil
    }

    // Flood fill
    let seedX = Int(scaledSeed.x)
    let seedY = Int(scaledSeed.y)
    if seedX < 0 || seedX >= width || seedY < 0 || seedY >= height {
        Log.debug("DEBUG: Seed point out of bounds")
        return nil
    }

    let boundaryBytesPerRow = boundaryCGImage.bytesPerRow
    let pixelDataSize = height * boundaryBytesPerRow
    guard let dataProvider = boundaryCGImage.dataProvider,
          let data = dataProvider.data,
          let boundaryPixelData = CFDataGetBytePtr(data) else {
        Log.debug("DEBUG: Failed to get boundary pixel data")
        return nil
    }
    let seedOffset = seedY * boundaryBytesPerRow + seedX * 4
    if boundaryPixelData[seedOffset + 3] != 0 {
        Log.debug("DEBUG: Seed point is on boundary or already filled")
        return nil
    }

    let platformColor = color.platformColor
    let fillCG = platformColor.cgColor
    let comp = fillCG.components ?? [0, 0, 0, 1]
    let fillR = UInt8(comp[0] * 255)
    let fillG = UInt8(comp[1] * 255)
    let fillB = UInt8(comp[2] * 255)
    let fillA = UInt8(255)

    let fillPixelData = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelDataSize)
    memset(fillPixelData, 0, pixelDataSize)

    var stack = [(Int, Int)]()
    stack.append((seedX, seedY))

    while !stack.isEmpty {
        let (x, y) = stack.removeLast()
        if x < 0 || x >= width || y < 0 || y >= height { continue }
        let off = y * boundaryBytesPerRow + x * 4
        if boundaryPixelData[off + 3] != 0 { continue }
        if fillPixelData[off + 3] != 0 { continue }
        fillPixelData[off] = fillR
        fillPixelData[off + 1] = fillG
        fillPixelData[off + 2] = fillB
        fillPixelData[off + 3] = fillA
        stack.append((x - 1, y))
        stack.append((x + 1, y))
        stack.append((x, y - 1))
        stack.append((x, y + 1))
    }

    guard let fillContext = CGContext(data: fillPixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: boundaryBytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
        fillPixelData.deallocate()
        Log.debug("DEBUG: Failed to create fill context")
        return nil
    }
    guard let fillCGImage = fillContext.makeImage() else {
        fillPixelData.deallocate()
        Log.debug("DEBUG: Failed to make fill CGImage")
        return nil
    }

    let filledImage: PlatformImage
    #if os(iOS)
    filledImage = UIImage(cgImage: fillCGImage)
    #else
    filledImage = NSImage(cgImage: fillCGImage, size: size)
    #endif

    fillPixelData.deallocate()
    return filledImage
}

// Markup View with unified implementation (custom drawing for both platforms)
struct MarkupView: View {
    let image: PlatformImage
    let baseFileName: String
    let fileExtension: String
    let onSave: (PlatformImage) -> Void
    // Mask inpainting (macOS only): when true, the editor offers a "Mask" tool. onSaveMask receives the
    // rendered binary mask PNG (transparent = edit region), or nil to clear a previously-stored mask.
    var maskSupported: Bool = false
    var onSaveMask: ((PlatformImage?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    // Display tint for in-editor mask strokes (the exported mask itself is alpha-only, not this color).
    private let maskDisplayColor = Color(red: 1.0, green: 0.18, blue: 0.55).opacity(0.45)

    // Shared states (both platforms)
    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 5.0
    @State private var textBoxes: [TextBox] = []
    @State private var addingText: Bool = false
    @State private var currentText: String = ""
    @State private var textPosition: CGPoint = .zero
    @State private var editingTextID: UUID? = nil
    @FocusState private var textFieldFocused: Bool
    @State private var showingFolderPicker = false
    @State private var pendingSaveImage: PlatformImage? = nil
    @State private var showSaveSuccess: Bool = false
    @State private var savedFilename: String = ""
    @State private var showCancelConfirmation: Bool = false
    @State private var forceClose: Bool = false

#if os(iOS)
    // iOS PencilKit states
    @State private var pkDrawing = PKDrawing()
    @State private var canvasContentOffset: CGPoint = .zero
    @State private var canvasZoomScale: CGFloat = 1.0
    @State private var pkUndoManager: UndoManager? = nil
    @State private var isToolPickerVisible: Bool = true
    @State private var canvasAdjustedInset: UIEdgeInsets = .zero
    @State private var initialFitScale: CGFloat? = nil
    @State private var undoActionOrder: [UndoActionType] = []
    @State private var textUndoSnapshots: [[TextBox]] = []
    @State private var isSuppressingStrokeRecord: Bool = false
#elseif os(macOS)
    // macOS custom drawing states
    @State private var annotations: [Annotation] = []
    @State private var currentPath: Path = Path()
    @State private var fillMode: Bool = false
    @State private var eraseMode: Bool = false
    // Mask-drawing mode: strokes go to maskStrokes (rendered as a translucent overlay) instead of the
    // burned-in annotations, and export to a standalone alpha mask. maskEdited gates whether Done writes
    // the mask back (so merely opening the editor never clears a previously-saved mask).
    @State private var maskMode: Bool = false
    @State private var maskStrokes: [Annotation] = []
    @State private var maskEdited: Bool = false
    @State private var imageFrame: CGRect = .zero
    @State private var history: [MarkupState] = []
    @State private var previousScale: CGFloat? = nil
    @State private var isFilling: Bool = false
    @State private var editorWindow: NSWindow? = nil
    @State private var windowDelegate: WindowCloseDelegate? = nil
    @State private var initialContentSize: CGSize = .zero
#endif

    let colors: [Color] = [.red, .green, .blue, .yellow, .purple, .orange, .black, .white]

    init(image: PlatformImage, baseFileName: String, fileExtension: String,
         onSave: @escaping (PlatformImage) -> Void,
         maskSupported: Bool = false,
         onSaveMask: ((PlatformImage?) -> Void)? = nil) {
        self.image = image
        self.baseFileName = baseFileName
        self.fileExtension = fileExtension
        self.onSave = onSave
        self.maskSupported = maskSupported
        self.onSaveMask = onSaveMask
#if os(macOS)
        let paletteHeight: CGFloat = 80
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let titleBarHeight: CGFloat = 28
            let maxWidth = visibleFrame.width * 0.6
            let maxHeight = visibleFrame.height - titleBarHeight
            let imgW = image.platformSize.width
            let imgH = image.platformSize.height
            let scale = min(maxWidth / imgW, (maxHeight - paletteHeight) / imgH)
            let contentW = imgW * scale
            let contentH = imgH * scale + paletteHeight
            _initialContentSize = State(initialValue: CGSize(width: contentW, height: contentH))
        } else {
            _initialContentSize = State(initialValue: CGSize(width: image.platformSize.width, height: image.platformSize.height + paletteHeight))
        }
#endif
    }

    var body: some View {
        GeometryReader { geo in
            markupContent(geo: geo)
        }
        .background {
#if os(macOS)
            WindowAccessor(window: $editorWindow)
#else
            EmptyView()
#endif
        }
#if os(iOS)
        .navigationBarHidden(true)
        .ignoresSafeArea(.keyboard)
#endif
        .onChange(of: addingText) { newValue in
            #if os(macOS)
            if newValue {
                fillMode = false
                eraseMode = false
                maskMode = false
            }
            #elseif os(iOS)
            if newValue {
                isToolPickerVisible = false
            } else {
                isToolPickerVisible = true
            }
            #endif
            if !newValue {
                textFieldFocused = false
            }
        }
        .onChange(of: editingTextID) { newValue in
            #if os(macOS)
            if newValue != nil {
                saveToHistory()
                DispatchQueue.main.async {
                    textFieldFocused = true
                }
            } else {
                textFieldFocused = false
            }
            #elseif os(iOS)
            if newValue != nil {
                isToolPickerVisible = false
                DispatchQueue.main.async {
                    textFieldFocused = true
                }
            } else {
                isToolPickerVisible = true
                textFieldFocused = false
            }
            #endif
        }
#if os(macOS)
        .onChange(of: fillMode) { newValue in
            if newValue {
                addingText = false
                eraseMode = false
                maskMode = false
                editingTextID = nil
            }
        }
        .onChange(of: eraseMode) { newValue in
            if newValue {
                addingText = false
                fillMode = false
                editingTextID = nil
            }
        }
        .onChange(of: maskMode) { newValue in
            if newValue {
                addingText = false
                fillMode = false
                eraseMode = false
                editingTextID = nil
            }
        }
#endif
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let folderURL) = result, let img = pendingSaveImage {
                saveImage(img, to: folderURL)
            }
            pendingSaveImage = nil
        }
        .alert("Save Successful", isPresented: $showSaveSuccess) {
            Button("OK") {}
        } message: {
            Text("Annotated image successfully saved as \(savedFilename)")
        }
        .alert("Are you sure you want to exit and discard changes?", isPresented: $showCancelConfirmation) {
            Button("Discard Changes", role: .destructive) {
                forceClose = true
                closeEditor()
            }
            Button("Cancel", role: .cancel) {}
        }
#if os(iOS)
        .toolbar {
            if addingText || editingTextID != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        if addingText {
                            commitText()
                        } else {
                            editingTextID = nil
                        }
                    }
                }
            }
        }
#endif
#if os(macOS)
        .onChange(of: editorWindow) { newWindow in
            if let window = newWindow, windowDelegate == nil {
                let del = WindowCloseDelegate()
                del.onAttemptClose = {
                    if forceClose {
                        return true
                    } else if hasChanges {
                        showCancelConfirmation = true
                        return false
                    } else {
                        return true
                    }
                }
                window.delegate = del
                windowDelegate = del
                
                // Set initial content size
                window.setContentSize(initialContentSize)
                window.center()
            }
        }
#endif
    }

    private var hasChanges: Bool {
        #if os(iOS)
        !pkDrawing.strokes.isEmpty || !textBoxes.isEmpty
        #else
        !annotations.isEmpty || !textBoxes.isEmpty || !maskStrokes.isEmpty
        #endif
    }

    private func markupContent(geo: GeometryProxy) -> some View {
#if os(iOS)
        let inset = geo.safeAreaInsets
        let actionBarHeight: CGFloat = 50

        return VStack(spacing: 0) {
            Color.clear.frame(height: inset.top)

            // Action bar at top — outside the canvas so it doesn't obscure the image
            pkActionBar
                .frame(height: actionBarHeight)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))

            ZStack {
                // PencilKit canvas with background image + zoom
                PKCanvasRepresentable(
                    backgroundImage: image,
                    drawing: $pkDrawing,
                    contentOffset: $canvasContentOffset,
                    zoomScale: $canvasZoomScale,
                    undoManagerRef: $pkUndoManager,
                    isToolPickerVisible: $isToolPickerVisible,
                    adjustedInset: $canvasAdjustedInset,
                    initialFitScale: $initialFitScale,
                    onStrokeAdded: {
                        if !isSuppressingStrokeRecord {
                            undoActionOrder.append(.stroke)
                        }
                    }
                )

                // Text overlays (positioned relative to canvas zoom/scroll)
                pkTextOverlayLayer

                // New text input overlay
                pkAddingTextOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Color.clear.frame(height: inset.bottom)
        }
        .background(Color(UIColor.systemBackground))
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if isToolPickerVisible {
                // Force tool picker re-show after app returns to foreground
                isToolPickerVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isToolPickerVisible = true
                }
            }
        }
#else
        let paletteHeight: CGFloat = 60  // Smaller with compact buttons
        let availableW = max(1, geo.size.width)
        let availableH = max(1, geo.size.height - paletteHeight)
        let safeImageWidth = max(1, image.platformSize.width)
        let safeImageHeight = max(1, image.platformSize.height)
        let scale = max(0.01, min(availableW / safeImageWidth, availableH / safeImageHeight))
        let displaySize = CGSize(width: max(1, safeImageWidth * scale), height: max(1, safeImageHeight * scale))
        
        let vPadding = max(0, (availableH - displaySize.height) / 2)
        let hPadding = max(0, (availableW - displaySize.width) / 2)
        
        return VStack(spacing: 0) { // Zero spacing for full height
            if vPadding > 0 {
                Color.clear
                    .frame(height: vPadding)
            }
            HStack {
                if hPadding > 0 {
                    Color.clear
                        .frame(width: hPadding)
                }
                annotationZStack(displaySize: displaySize, geo: geo)
                if hPadding > 0 {
                    Color.clear
                        .frame(width: hPadding)
                }
            }
            .frame(height: displaySize.height)
            // Palette at bottom, full width, no scrolling - vertical layout
            FloatingPaletteView(color: $color, lineWidth: $lineWidth, addingText: $addingText, fillMode: $fillMode, eraseMode: $eraseMode, maskMode: $maskMode, maskSupported: maskSupported, colors: colors, isLandscape: true,
                                onStartAddingText: {
                                    addingText = true
                                },
                                onUndo: undoLastAction,
                                onClear: clearAll,
                                canUndo: canUndo,
                                onCancel: {
                                    if hasChanges {
                                        showCancelConfirmation = true
                                    } else {
                                        closeEditor()
                                    }
                                },
                                onSaveFile: {
                                    if let img = renderAnnotatedImage() {
                                        if let folderURL = appState.settings.outputDirectory {
                                            saveImage(img, to: folderURL)
                                        } else {
                                            pendingSaveImage = img
                                            showingFolderPicker = true
                                        }
                                    }
                                },
                                onDone: {
                                    // Only rewrite the slot image when real annotations exist, so a
                                    // mask-only edit doesn't needlessly re-encode the source image.
                                    if !annotations.isEmpty || !textBoxes.isEmpty {
                                        if let updatedImage = renderAnnotatedImage() {
                                            onSave(updatedImage)
                                        }
                                    }
                                    // Persist (or clear) the mask only if the user actually touched it.
                                    if maskSupported && maskEdited {
                                        onSaveMask?(renderMaskImage())
                                    }
                                    closeEditor()
                                })
            .frame(height: paletteHeight)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
#endif
    }

#if os(macOS)
    private func annotationZStack(displaySize: CGSize, geo: GeometryProxy) -> some View {
        ZStack {
            Color.white
                .allowsHitTesting(false)
            Image(platformImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: displaySize.width, height: displaySize.height)
                .allowsHitTesting(false)
                .background(
                    GeometryReader { bgGeo in
                        Color.clear.preference(key: FramePreferenceKey.self, value: bgGeo.frame(in: .named("markupZStack")))
                    }
                )
            // Unified drawing with Canvas for strokes, fills, and erases
            if !addingText && editingTextID == nil {
                Canvas { context, size in
                    context.blendMode = .normal
                    for annotation in annotations {
                        switch annotation {
                        case .fill(let fill):
                            let fillImage = Image(platformImage: fill.image)
                            context.draw(fillImage, in: CGRect(origin: .zero, size: size))
                        case .stroke(let stroke):
                            context.blendMode = .normal
                            context.stroke(stroke.path, with: .color(stroke.color), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))
                        case .erase(let erase):
                            context.blendMode = .clear
                            context.stroke(erase.path, with: .color(.black), style: StrokeStyle(lineWidth: erase.lineWidth, lineCap: .round, lineJoin: .round))
                        }
                    }
                    if !currentPath.isEmpty && !maskMode {
                        if eraseMode {
                            context.blendMode = .clear
                            context.stroke(currentPath, with: .color(.black), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        } else {
                            context.blendMode = .normal
                            context.stroke(currentPath, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                .frame(width: displaySize.width, height: displaySize.height)
                .allowsHitTesting(false)

                // Mask overlay — separate Canvas layer so mask strokes never blend with the burned-in
                // annotations. Painted (pink) areas = the region the model will edit/inpaint.
                if maskSupported {
                    Canvas { context, size in
                        for ann in maskStrokes {
                            switch ann {
                            case .stroke(let s):
                                context.blendMode = .normal
                                context.stroke(s.path, with: .color(maskDisplayColor), style: StrokeStyle(lineWidth: s.lineWidth, lineCap: .round, lineJoin: .round))
                            case .erase(let e):
                                context.blendMode = .clear
                                context.stroke(e.path, with: .color(.black), style: StrokeStyle(lineWidth: e.lineWidth, lineCap: .round, lineJoin: .round))
                            case .fill:
                                break
                            }
                        }
                        if maskMode && !currentPath.isEmpty {
                            if eraseMode {
                                context.blendMode = .clear
                                context.stroke(currentPath, with: .color(.black), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                            } else {
                                context.blendMode = .normal
                                context.stroke(currentPath, with: .color(maskDisplayColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                            }
                        }
                    }
                    .frame(width: displaySize.width, height: displaySize.height)
                    .allowsHitTesting(false)
                }

                // Eraser preview (dashed line)
                if eraseMode && !currentPath.isEmpty {
                    currentPath
                        .stroke(Color.gray, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: [5]))
                        .allowsHitTesting(false)
                }

                textBoxesOverlay
            } else {
                if editingTextID != nil {
                    ForEach($textBoxes) { $box in
                        if $box.wrappedValue.id == editingTextID {
                            textOverlay(for: $box)
                        }
                    }
                }
            }
            addingTextOverlay
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .coordinateSpace(name: "markupZStack")
        .background(Color.clear.contentShape(Rectangle()))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !addingText && editingTextID == nil && !fillMode {
                        addPoint(to: $currentPath, point: value.location)
                    }
                }
                .onEnded { value in
                    let loc = value.location
                    if addingText {
                        textPosition = loc
                    } else if editingTextID == nil {
                        if maskMode {
                            addPoint(to: $currentPath, point: loc)
                            saveToHistory()
                            if eraseMode {
                                maskStrokes.append(.erase(EraseStroke(path: currentPath, lineWidth: lineWidth)))
                            } else {
                                maskStrokes.append(.stroke(Stroke(path: currentPath, color: maskDisplayColor, lineWidth: lineWidth)))
                            }
                            maskEdited = true
                            currentPath = Path()
                        } else if fillMode {
                            performFill(at: loc)
                        } else if eraseMode {
                            addPoint(to: $currentPath, point: loc)
                            saveToHistory()
                            annotations.append(.erase(EraseStroke(path: currentPath, lineWidth: lineWidth)))
                            currentPath = Path()
                        } else {
                            addPoint(to: $currentPath, point: loc)
                            saveToHistory()
                            annotations.append(.stroke(Stroke(path: currentPath, color: color, lineWidth: lineWidth)))
                            currentPath = Path()
                        }
                    }
                }
        )
        .onTapGesture {
            if editingTextID != nil || addingText {
                textFieldFocused = false
                if addingText {
                    commitText()
                } else {
                    editingTextID = nil
                }
            }
        }
        .onAppear {
            Log.debug("DEBUG: MarkupView appeared with image size: \(image.platformSize)")
        }
        .onPreferenceChange(FramePreferenceKey.self) { frame in
            if frame.size.width > 0 {
                let newScale = frame.size.width / image.platformSize.width
                if let prev = previousScale, prev != newScale, prev > 0, newScale > 0 {
                    let ratio = newScale / prev
                    for i in 0..<annotations.count {
                        switch annotations[i] {
                        case .stroke(var s):
                            s.path = s.path.applying(CGAffineTransform(scaleX: ratio, y: ratio))
                            annotations[i] = .stroke(s)
                        case .erase(var e):
                            e.path = e.path.applying(CGAffineTransform(scaleX: ratio, y: ratio))
                            annotations[i] = .erase(e)
                        case .fill:
                            break
                        }
                    }
                    maskStrokes = rescaleAnnotations(maskStrokes, ratio: ratio)
                    for i in 0..<textBoxes.count {
                        textBoxes[i].position = CGPoint(x: textBoxes[i].position.x * ratio, y: textBoxes[i].position.y * ratio)
                    }
                    if !currentPath.isEmpty {
                        currentPath = currentPath.applying(CGAffineTransform(scaleX: ratio, y: ratio))
                    }
                    if addingText {
                        textPosition = CGPoint(x: textPosition.x * ratio, y: textPosition.y * ratio)
                    }
                    for h in 0..<history.count {
                        var rescaledAnnotations = history[h].annotations
                        for i in 0..<rescaledAnnotations.count {
                            switch rescaledAnnotations[i] {
                            case .stroke(var s):
                                s.path = s.path.applying(CGAffineTransform(scaleX: ratio, y: ratio))
                                rescaledAnnotations[i] = .stroke(s)
                            case .erase(var e):
                                e.path = e.path.applying(CGAffineTransform(scaleX: ratio, y: ratio))
                                rescaledAnnotations[i] = .erase(e)
                            case .fill:
                                break
                            }
                        }
                        var rescaledTextBoxes = history[h].textBoxes
                        for i in 0..<rescaledTextBoxes.count {
                            rescaledTextBoxes[i].position = CGPoint(
                                x: rescaledTextBoxes[i].position.x * ratio,
                                y: rescaledTextBoxes[i].position.y * ratio
                            )
                        }
                        let rescaledMask = rescaleAnnotations(history[h].maskStrokes, ratio: ratio)
                        history[h] = MarkupState(annotations: rescaledAnnotations, textBoxes: rescaledTextBoxes, maskStrokes: rescaledMask)
                    }
                }
                previousScale = newScale
                imageFrame = frame
                Log.debug("DEBUG: Image frame updated: \(imageFrame)")
            }
        }
        .onChange(of: addingText) { newValue in
            if newValue {
                if imageFrame.size != .zero {
                    textPosition = CGPoint(x: imageFrame.midX, y: imageFrame.midY)
                    Log.debug("DEBUG: Initial text position set to screen center: \(textPosition)")
                    DispatchQueue.main.async {
                        textFieldFocused = true
                    }
                }
            } else {
                textFieldFocused = false
            }
        }
        .onChange(of: imageFrame) { newFrame in
            if addingText && newFrame.size != .zero && textPosition == .zero {
                textPosition = CGPoint(x: newFrame.midX, y: newFrame.midY)
                DispatchQueue.main.async {
                    textFieldFocused = true
                }
            }
        }
        .accessibilityLabel("Image annotation area")
        .accessibilityHint("Draw with pen or add text annotations here")
    }
#endif

#if os(macOS)
    @ViewBuilder
    private func textOverlay(for box: Binding<TextBox>) -> some View {
        if editingTextID == box.wrappedValue.id {
            editableTextView(for: box)
        } else {
            draggableTextView(for: box)
        }
    }

    private func editableTextView(for box: Binding<TextBox>) -> some View {
        let boxValue = box.wrappedValue
        let textColor = boxValue.color
        let editPosition = boxValue.position

        let baseTextField = TextField("Edit text", text: box.text, axis: .vertical)
            .font(.system(size: 20))
            .foregroundColor(textColor)
            .focused($textFieldFocused)

        let committedTextField = baseTextField
            .onSubmit {
                editingTextID = nil
            }

        let positionedView = committedTextField
            .position(editPosition)
            .onTapGesture {} // Consume tap to prevent parent onTap from defocusing

        return positionedView
            .accessibilityLabel("Editable text annotation")
            .accessibilityValue(box.text.wrappedValue)
            .accessibilityHint("Edit the text content")
    }

    private func draggableTextView(for box: Binding<TextBox>) -> some View {
        DraggableText(box: box, onTap: {
            editingTextID = box.wrappedValue.id
        })
    }

    private var textBoxesOverlay: some View {
        ForEach($textBoxes) { $box in
            textOverlay(for: $box)
        }
    }

    private var addingTextOverlay: some View {
        Group {
            if addingText {
                let addColor = color

                let baseTextField = TextField("Enter text", text: $currentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 20))
                    .foregroundColor(addColor)
                    .focused($textFieldFocused)

                let committedTextField = baseTextField
                    .onSubmit {
                        commitText()
                    }

                let positionedView = committedTextField
                    .frame(width: 200)
                    .position(textPosition)
                    .onTapGesture {} // Consume tap to prevent parent onTap from defocusing

                positionedView
                    .accessibilityLabel("New text annotation")
                    .accessibilityValue(currentText)
                    .accessibilityHint("Enter new text to annotate the image")
            }
        }
    }
#endif

    // MARK: - iOS PencilKit text overlays and action bar
#if os(iOS)
    private func imagePointToScreen(_ imagePoint: CGPoint) -> CGPoint {
        CGPoint(
            x: imagePoint.x * canvasZoomScale - canvasContentOffset.x + canvasAdjustedInset.left,
            y: imagePoint.y * canvasZoomScale - canvasContentOffset.y + canvasAdjustedInset.top
        )
    }

    private func screenPointToImage(_ screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - canvasAdjustedInset.left + canvasContentOffset.x) / canvasZoomScale,
            y: (screenPoint.y - canvasAdjustedInset.top + canvasContentOffset.y) / canvasZoomScale
        )
    }

    private var pkTextOverlayLayer: some View {
        GeometryReader { geo in
            ZStack {
                ForEach($textBoxes) { $box in
                    let screenPos = imagePointToScreen(box.position)
                    if editingTextID == box.id {
                        TextField("Edit text", text: $box.text, axis: .vertical)
                            .font(.system(size: 20))
                            .foregroundColor(box.color)
                            .focused($textFieldFocused)
                            .onSubmit {
                                editingTextID = nil
                            }
                            .position(screenPos)
                            .onTapGesture {}
                    } else {
                        DraggableText(box: $box, zoomScale: canvasZoomScale, onTap: {
                            // Record text undo snapshot before editing
                            textUndoSnapshots.append(textBoxes)
                            undoActionOrder.append(.text)
                            editingTextID = box.id
                        }, positionTransform: { basePos, translation in
                            let screen = imagePointToScreen(basePos)
                            return CGPoint(
                                x: screen.x + translation.width,
                                y: screen.y + translation.height
                            )
                        }, onDragEnd: { box_binding, translation in
                            // Record text undo snapshot before move
                            textUndoSnapshots.append(textBoxes)
                            undoActionOrder.append(.text)
                            box_binding.wrappedValue.position.x += translation.width / canvasZoomScale
                            box_binding.wrappedValue.position.y += translation.height / canvasZoomScale
                        })
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(addingText || editingTextID != nil || !textBoxes.isEmpty)
    }

    private var pkAddingTextOverlay: some View {
        Group {
            if addingText {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let imagePos = screenPointToImage(location)
                            textPosition = imagePos
                            textFieldFocused = true
                        }

                    if textPosition != .zero {
                        let screenPos = imagePointToScreen(textPosition)
                        TextField("Enter text", text: $currentText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 20))
                            .foregroundColor(color)
                            .focused($textFieldFocused)
                            .onSubmit {
                                commitText()
                            }
                            .frame(width: 200)
                            .position(screenPos)
                            .onTapGesture {}
                    }
                }
            }
        }
    }

    private var pkActionBar: some View {
        HStack(spacing: 12) {
            // Text toggle
            Button {
                if addingText {
                    addingText = false
                } else {
                    addingText = true
                }
            } label: {
                Image(systemName: "textformat.size")
                    .foregroundColor(addingText ? .blue : .primary)
            }
            .buttonStyle(.bordered)

            // Color picker (visible when adding/editing text)
            if addingText || editingTextID != nil {
                HStack(spacing: 4) {
                    ForEach(colors, id: \.self) { col in
                        Button(action: { color = col }) {
                            ColorPickerButton(col: col, isSelected: col == color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            // Undo
            Button {
                pkUndoAction()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.bordered)
            .disabled(!pkCanUndo)

            // Clear
            Button {
                pkClearAll()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.bordered)

            Spacer()

            // Cancel
            Button {
                if hasChanges { showCancelConfirmation = true }
                else { closeEditor() }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderedProminent)

            // Save to file
            Button {
                if let img = renderAnnotatedImagePK() {
                    if let folderURL = appState.settings.outputDirectory {
                        saveImage(img, to: folderURL)
                    } else {
                        pendingSaveImage = img
                        showingFolderPicker = true
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)

            // Done
            Button {
                if let updatedImage = renderAnnotatedImagePK() {
                    onSave(updatedImage)
                }
                closeEditor()
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - iOS Undo System

    private var pkCanUndo: Bool {
        !undoActionOrder.isEmpty
    }

    private func pkUndoAction() {
        guard let lastAction = undoActionOrder.popLast() else { return }
        switch lastAction {
        case .stroke:
            isSuppressingStrokeRecord = true
            pkUndoManager?.undo()
            // Reset suppression after a short delay to allow the drawing change callback to fire
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSuppressingStrokeRecord = false
            }
        case .text:
            if let prev = textUndoSnapshots.popLast() {
                textBoxes = prev
                editingTextID = nil
            }
        case .clearAll(let savedDrawing, let savedTextBoxes):
            isSuppressingStrokeRecord = true
            pkDrawing = savedDrawing
            textBoxes = savedTextBoxes
            editingTextID = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSuppressingStrokeRecord = false
            }
        }
    }

    private func pkClearAll() {
        guard hasChanges else { return }
        undoActionOrder.append(.clearAll(savedDrawing: pkDrawing, savedTextBoxes: textBoxes))
        isSuppressingStrokeRecord = true
        pkDrawing = PKDrawing()
        textBoxes = []
        editingTextID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSuppressingStrokeRecord = false
        }
    }

    // MARK: - iOS Render

    private func renderAnnotatedImagePK() -> PlatformImage? {
        let size = image.platformSize
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            // 1. Source image
            image.draw(in: CGRect(origin: .zero, size: size))

            // 2. PK strokes at 1:1 pixel resolution
            let pkImage = pkDrawing.image(
                from: CGRect(origin: .zero, size: size),
                scale: 1.0
            )
            pkImage.draw(in: CGRect(origin: .zero, size: size))

            // 3. Text at proportional size
            let textScale = 1.0 / (initialFitScale ?? 1.0)
            for box in textBoxes {
                let fontSize = 20.0 * textScale
                let font = UIFont.systemFont(ofSize: fontSize)
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: box.color.platformColor,
                    .font: font
                ]
                let attrStr = NSAttributedString(string: box.text, attributes: attrs)
                let strSize = attrStr.size()
                attrStr.draw(in: CGRect(
                    x: box.position.x - strSize.width / 2,
                    y: box.position.y - strSize.height / 2,
                    width: strSize.width, height: strSize.height
                ))
            }
        }
    }
#endif

    private func commitText() {
        if !currentText.isEmpty {
            #if os(iOS)
            textUndoSnapshots.append(textBoxes)
            undoActionOrder.append(.text)
            #else
            saveToHistory()
            #endif
            let textColor = color
            let finalPosition = textPosition
            textBoxes.append(TextBox(text: currentText, position: finalPosition, color: textColor))
        }
        addingText = false
        currentText = ""
        textFieldFocused = false
    }

#if os(macOS)
    private var canUndo: Bool {
        !history.isEmpty
    }

    private func saveToHistory() {
        history.append(MarkupState(annotations: annotations, textBoxes: textBoxes, maskStrokes: maskStrokes))
    }

    private func undoLastAction() {
        guard !history.isEmpty else { return }
        let previous = history.removeLast()
        annotations = previous.annotations
        textBoxes = previous.textBoxes
        maskStrokes = previous.maskStrokes
        if maskMode { maskEdited = true }
        currentPath = Path()
        editingTextID = nil
    }

    private func clearAll() {
        saveToHistory()
        annotations = []
        currentPath = Path()
        textBoxes = []
        editingTextID = nil
        if !maskStrokes.isEmpty {
            maskStrokes = []
            maskEdited = true   // persist the cleared mask on Done
        }
    }

    // Scale a set of stroke/erase annotation paths by `ratio` (used when the editor window resizes).
    private func rescaleAnnotations(_ anns: [Annotation], ratio: CGFloat) -> [Annotation] {
        anns.map { ann in
            switch ann {
            case .stroke(var s):
                s.path = s.path.applying(CGAffineTransform(scaleX: ratio, y: ratio))
                return .stroke(s)
            case .erase(var e):
                e.path = e.path.applying(CGAffineTransform(scaleX: ratio, y: ratio))
                return .erase(e)
            case .fill:
                return ann
            }
        }
    }

    // Render the mask strokes to a standalone full-resolution PNG for the gpt-image /edits endpoint.
    // OpenAI semantics: TRANSPARENT pixels mark the region to edit; OPAQUE pixels are preserved.
    // Returns nil when no mask has been drawn (treated as "clear the mask").
    private func renderMaskImage() -> PlatformImage? {
        guard !maskStrokes.isEmpty else { return nil }
        guard imageFrame.width > 0 else { return nil }
        // Render at the image's true PIXEL dimensions so the exported mask matches the uploaded image
        // exactly (the /edits endpoint requires identical dimensions). platformSize (points) can differ.
        let width: Int
        let height: Int
        if let cg = image.asCGImage {
            width = cg.width
            height = cg.height
        } else {
            width = Int(image.platformSize.width.rounded())
            height = Int(image.platformSize.height.rounded())
        }
        guard width > 0, height > 0 else { return nil }
        let pixelSize = CGSize(width: width, height: height)
        // Strokes are in display-frame coordinates; map them to pixel space.
        let scale = CGFloat(width) / imageFrame.width

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }

        // Start fully opaque (preserve everywhere).
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: pixelSize))

        // Paths are in top-left display coordinates; flip to CG's bottom-left space.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for ann in maskStrokes {
            switch ann {
            case .stroke(let s):
                // Painted region -> transparent (the area to inpaint).
                ctx.setBlendMode(.clear)
                ctx.addPath(s.path.applying(CGAffineTransform(scaleX: scale, y: scale)).cgPath)
                ctx.setLineWidth(s.lineWidth * scale)
                ctx.strokePath()
            case .erase(let e):
                // Eraser restores opacity (un-mask).
                ctx.setBlendMode(.normal)
                ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 1)
                ctx.addPath(e.path.applying(CGAffineTransform(scaleX: scale, y: scale)).cgPath)
                ctx.setLineWidth(e.lineWidth * scale)
                ctx.strokePath()
            case .fill:
                break
            }
        }

        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: pixelSize)
    }

    private func addPoint(to path: Binding<Path>, point: CGPoint) {
        if path.wrappedValue.isEmpty {
            path.wrappedValue.move(to: point)
        } else {
            path.wrappedValue.addLine(to: point)
        }
    }

    private func performFill(at point: CGPoint) {
        guard !isFilling else { return }
        isFilling = true
        let currentColor = color
        let currentAnnotations = annotations
        let currentImageFrame = imageFrame
        let sourceImage = image

        Task.detached(priority: .userInitiated) {
            let filledImage = createFilledMaskAsync(
                seed: point, color: currentColor,
                annotations: currentAnnotations,
                imageFrame: currentImageFrame,
                image: sourceImage
            )
            await MainActor.run {
                if let filledImage {
                    saveToHistory()
                    annotations.append(.fill(Fill(image: filledImage)))
                }
                isFilling = false
            }
        }
    }

    private func renderAnnotatedImage() -> PlatformImage? {
        let originalSize = image.platformSize

        guard originalSize != .zero else {
            Log.debug("DEBUG: Skipping render due to zero original image size")
            return nil
        }

        let scale = originalSize.width / imageFrame.width

        return PlatformRendererFactory.renderer.render(
            image: image,
            annotations: annotations,
            textBoxes: textBoxes,
            annotationScale: scale,
            offset: .zero
        )
    }
#endif

    private func saveImage(_ image: PlatformImage, to folderURL: URL) {
        let fm = FileManager.default
        var num = 1
        var newURL = folderURL.appendingPathComponent("\(baseFileName)_annotated_\(num).\(fileExtension)")
        let extLower = fileExtension.lowercased()
        
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            Log.debug("Invalid folder")
            return
        }
        
        do {
            try withSecureAccess(to: folderURL) {
                while fm.fileExists(atPath: newURL.path) {
                    num += 1
                    newURL = folderURL.appendingPathComponent("\(baseFileName)_annotated_\(num).\(fileExtension)")
                }
                
                if let data = image.platformData(forType: extLower) {
                    try data.write(to: newURL)
                    Log.debug("Saved to \(newURL.path)")
                    DispatchQueue.main.async {
                        self.savedFilename = newURL.lastPathComponent
                        self.showSaveSuccess = true
                    }
                } else {
                    Log.debug("Unsupported file format")
                }
            }
        } catch {
            Log.debug("Error saving image: \(error)")
        }
    }
    
    private func closeEditor() {
#if os(macOS)
        editorWindow?.close()
#else
        dismiss()
#endif
    }

}

struct DraggableText: View {
    @Binding var box: TextBox
    var zoomScale: CGFloat = 1.0
    @GestureState private var translation: CGSize = .zero
    let onTap: () -> Void
    // Optional transform for position calculation (iOS uses screen-space transform)
    var positionTransform: ((CGPoint, CGSize) -> CGPoint)? = nil
    // Optional custom drag end handler (iOS needs to record undo + scale delta)
    var onDragEnd: ((Binding<TextBox>, CGSize) -> Void)? = nil

    var body: some View {
        let currentColor = box.color
        let basePosition = box.position

        let currentPosition: CGPoint
        if let transform = positionTransform {
            currentPosition = transform(basePosition, translation)
        } else {
            currentPosition = CGPoint(
                x: basePosition.x + translation.width,
                y: basePosition.y + translation.height
            )
        }

        let textView = Text(box.text)
            .font(.system(size: 20))
            .foregroundColor(currentColor)

        let positionedText = textView
            .position(currentPosition)

        let draggedText = positionedText
            .gesture(
                DragGesture()
                    .updating($translation) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        if let customEnd = onDragEnd {
                            customEnd($box, value.translation)
                        } else {
                            var newPosition = box.position
                            newPosition.x += value.translation.width
                            newPosition.y += value.translation.height
                            box.position = newPosition
                        }
                    }
            )

        let tappableText = draggedText
            .onTapGesture(perform: onTap)

        return tappableText
            .accessibilityLabel("Text annotation: \(box.text)")
            .accessibilityHint("Double tap to edit, drag to move")
    }
}

struct ColorPickerButton: View {
    let col: Color
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(col)
            .frame(width: 14, height: 14)
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.gray, lineWidth: 1)
                } else {
                    Circle()
                        .stroke(Color.clear, lineWidth: 1)
                }
            }
    }
}

private func colorName(for color: Color) -> String {
    switch color {
    case .red: return "red"
    case .green: return "green"
    case .blue: return "blue"
    case .yellow: return "yellow"
    case .purple: return "purple"
    case .orange: return "orange"
    case .black: return "black"
    case .white: return "white"
    default: return "custom"
    }
}

struct FloatingPaletteView: View {
    @Binding var color: Color
    @Binding var lineWidth: CGFloat
    @Binding var addingText: Bool
    @Binding var fillMode: Bool // New binding for fillMode
    @Binding var eraseMode: Bool // New binding for eraseMode
    @Binding var maskMode: Bool // Mask-drawing mode (macOS, mask-capable models only)
    let maskSupported: Bool      // When false the mask tool is hidden
    let colors: [Color]
    let isLandscape: Bool
    let onStartAddingText: () -> Void
    let onUndo: () -> Void
    let onClear: () -> Void
    let canUndo: Bool
    var onCancel: () -> Void
    var onSaveFile: () -> Void
    var onDone: () -> Void

    // Helper computed property to determine if pen mode is active (none of the other tools)
    private var penMode: Bool {
        !addingText && !fillMode && !eraseMode && !maskMode
    }

    // Compact button size for tight spaces
    private let buttonSize: CGFloat = 36

    private var toolsGroup: some View {
        HStack(spacing: 10) {
            // Pen tool button
            Button {
                addingText = false
                fillMode = false
                eraseMode = false
                maskMode = false
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(penMode ? .blue : .primary)
            }
            .buttonStyle(.bordered)
            .frame(width: buttonSize, height: buttonSize)
            .help("Pen tool (draw)")
            .accessibilityLabel("Pen tool")
            .accessibilityHint("Draw lines on the image")

            // Mask tool button (mask-capable gpt-image models only) — paints the inpainting region.
            if maskSupported {
                Button {
                    maskMode.toggle()
                } label: {
                    Image(systemName: "paintbrush.pointed.fill")
                        .foregroundColor(maskMode ? .blue : .primary)
                }
                .buttonStyle(.bordered)
                .frame(width: buttonSize, height: buttonSize)
                .help("Mask tool — paint the region to inpaint (sent as the edit mask)")
                .accessibilityLabel("Mask tool")
                .accessibilityHint("Paint the area the model should regenerate; sent as the inpainting mask")
            }

            Button {
                fillMode.toggle()
            } label: {
                Image(systemName: "drop.fill")
                    .foregroundColor(fillMode ? .blue : .primary)
            }
            .buttonStyle(.bordered)
            .frame(width: buttonSize, height: buttonSize)
            .help("Toggle fill tool")
            .accessibilityLabel("Fill tool")
            .accessibilityHint("Fills enclosed areas with selected color")

            Button {
                eraseMode.toggle()
            } label: {
                Image(systemName: "eraser")
                    .foregroundColor(eraseMode ? .blue : .primary)
            }
            .buttonStyle(.bordered)
            .frame(width: buttonSize, height: buttonSize)
            .help("Toggle eraser tool")
            .accessibilityLabel("Eraser tool")
            .accessibilityHint("Erase annotations from the image")

            Button {
                if addingText {
                    addingText = false
                } else {
                    onStartAddingText()
                }
            } label: {
                Image(systemName: "textformat.size")
                    .foregroundColor(addingText ? .blue : .primary)
            }
            .buttonStyle(.bordered)
            .frame(width: buttonSize, height: buttonSize)
            .help("Toggle text annotation mode")
            .accessibilityLabel("Text tool")
            .accessibilityHint("Adds or edits text annotations on the image")

            Button {
                onUndo()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.bordered)
            .disabled(!canUndo)
            .frame(width: buttonSize, height: buttonSize)
            .help("Undo last annotation action")
            .accessibilityLabel("Undo")
            .accessibilityHint("Reverts the most recent change")

            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .frame(width: buttonSize, height: buttonSize)
            .help("Clear all annotations")
            .accessibilityLabel("Clear")
            .accessibilityHint("Removes all drawings and text from the image")
        }
    }
    
    private var colorGroup: some View {
        HStack(spacing: 4) {
#if os(macOS)
            Text("Pen Color:")
                .font(.caption)
                .accessibilityHidden(true) // Since it's visual label
#endif
            
            ForEach(colors, id: \.self) { col in
                Button(action: { color = col }) {
                    ColorPickerButton(col: col, isSelected: col == $color.wrappedValue)
                }
                .buttonStyle(.plain)
                .help("Select \(colorName(for: col)) color for pen or text")
                .accessibilityLabel("\(colorName(for: col).capitalized) color")
                .accessibilityHint("Changes the color of the pen or text to \(colorName(for: col))")
            }
        }
    }
    
    private var widthGroup: some View {
        HStack(spacing: 4) {
            #if os(macOS)
            Text("Width:")
                .font(.caption)
                .accessibilityHidden(true) // Visual label
            #endif

            Slider(value: $lineWidth, in: 1...20)
                .frame(width: isLandscape ? 100 : 70) // Compact slider for portrait
                .help("Adjust the pen line width")
                .accessibilityLabel("Line width")
                .accessibilityValue("\(Int(lineWidth))")
                .accessibilityHint("Slide to change the thickness of the drawing line, from 1 to 20")
        }
    }
    
    private var actionsGroup: some View {
        HStack(spacing: 10) {
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderedProminent)
            .frame(width: buttonSize, height: buttonSize)
            .help("Close without saving")
            .accessibilityLabel("Close")
            .accessibilityHint("Closes the editor, discarding any changes, from the toolbar")

            Button {
                onSaveFile()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .frame(width: buttonSize, height: buttonSize)
            .help("Save annotated image to a file")
            .accessibilityLabel("Save to file")
            .accessibilityHint("Saves the current annotations to a new image file")

            Button {
                onDone()
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .frame(width: buttonSize, height: buttonSize)
            .help("Apply changes and close")
            .accessibilityLabel("Done")
            .accessibilityHint("Saves the annotations and closes the editor")
        }
    }

    var body: some View {
        if isLandscape {
            HStack(spacing: 6) {
                toolsGroup

                Spacer()

                colorGroup

                Spacer()

                widthGroup

                Spacer()

                actionsGroup
            }
            .padding(.horizontal, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(DS.Radius.standard)
            .shadow(radius: 4)
            .padding(.horizontal)
        } else {
            // Portrait mode: horizontally scrollable single row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    toolsGroup

                    // Divider between tools and colors
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 28)

                    colorGroup

                    // Divider between colors and width
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 28)

                    widthGroup

                    // Divider before actions
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 28)

                    actionsGroup
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(DS.Radius.standard)
            .shadow(radius: 4)
            .padding(.horizontal, 4)
        }
    }
}

#if os(iOS)
extension View {
    @ViewBuilder
    func applySafeAreaPadding(_ edge: Edge.Set, _ length: CGFloat) -> some View {
        self.safeAreaPadding(edge, length)
    }
}
#endif
