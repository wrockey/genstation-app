//CustomTextEditor.swift

import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// Add this class definition at the top of CustomTextEditor.swift (after imports, before struct CustomTextEditor)
#if os(macOS)

class TextEditorWindowDelegate: NSObject, NSWindowDelegate {
    var shouldCloseHandler: (() -> Bool)?
    weak var window: NSWindow?
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Log.debug("windowShouldClose called for window: \(sender.title)")
        return shouldCloseHandler?() ?? true
    }
}
#endif

struct CustomTextEditor: View {
    @Binding var text: String
    @Binding var platformTextView: (any PlatformTextView)?

    /// When true, shows batch editor features: line numbers and zebra striping
    let isBatchEditor: Bool

    #if os(macOS)
    let windowDelegate: TextEditorWindowDelegate?
    let windowTitle: String
    #endif

    #if os(macOS)
    init(text: Binding<String>, platformTextView: Binding<(any PlatformTextView)?>, windowDelegate: TextEditorWindowDelegate? = nil, windowTitle: String = "", isBatchEditor: Bool = false) {
        self._text = text
        self._platformTextView = platformTextView
        self.windowDelegate = windowDelegate
        self.windowTitle = windowTitle
        self.isBatchEditor = isBatchEditor
    }
    #else
    init(text: Binding<String>, platformTextView: Binding<(any PlatformTextView)?>, isBatchEditor: Bool = false) {
        self._text = text
        self._platformTextView = platformTextView
        self.isBatchEditor = isBatchEditor
    }
    #endif

    var body: some View {
        #if os(macOS)
        MacCustomTextEditor(text: $text, platformTextView: $platformTextView, windowDelegate: windowDelegate, windowTitle: windowTitle, isBatchEditor: isBatchEditor)
        #elseif os(iOS)
        iOSCustomTextEditor(text: $text, platformTextView: $platformTextView, isBatchEditor: isBatchEditor)
        #endif
    }
}

#if os(macOS)

// MARK: - Zebra Striping Layout Manager

/// Custom layout manager that draws alternating background colors for each logical line (paragraph).
/// This helps users distinguish individual prompts when they wrap across multiple visual lines.
class ZebraStripingLayoutManager: NSLayoutManager {

    /// Color for odd-numbered lines (0-indexed, so lines 1, 3, 5... visually)
    var oddLineColor: NSColor = NSColor.secondaryLabelColor.withAlphaComponent(0.06)

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // First draw default backgrounds
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage, let textContainer = textContainers.first else { return }

        let string = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)

        // Enumerate paragraphs (logical lines) and draw alternating backgrounds
        var paragraphIndex = 0
        string.enumerateSubstrings(in: fullRange, options: [.byParagraphs, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            // Only draw background for odd paragraphs (0-indexed)
            if paragraphIndex % 2 == 1 {
                // Get glyph range for this paragraph
                let glyphRange = self.glyphRange(forCharacterRange: enclosingRange, actualCharacterRange: nil)

                // Only draw if this paragraph overlaps with the glyphs we're drawing
                let intersection = NSIntersectionRange(glyphRange, glyphsToShow)
                if intersection.length > 0 {
                    // Get the bounding rect for all glyphs in this paragraph
                    var lineRect = self.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    lineRect.origin.x = 0  // Extend to full width
                    lineRect.size.width = textContainer.containerSize.width
                    lineRect.origin.x += origin.x
                    lineRect.origin.y += origin.y

                    // Draw the background
                    self.oddLineColor.setFill()
                    lineRect.fill()
                }
            }
            paragraphIndex += 1
        }
    }
}

class CustomNSTextView: NSTextView {
    // Removed customUndoManager

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string) {
            self.insertText(string, replacementRange: self.selectedRange())
        }
    }
}

// MARK: - Line Number Ruler View

/// A ruler view that displays line numbers for each logical line (paragraph) in the text view.
class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let gutterWidth: CGFloat = 40

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = gutterWidth
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              textView.textContainer != nil else { return }

        let string = textView.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)

        // Background
        NSColor.textBackgroundColor.withAlphaComponent(0.5).setFill()
        rect.fill()

        // Right border
        NSColor.separatorColor.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: rect.maxX - 0.5, y: rect.minY))
        borderPath.line(to: NSPoint(x: rect.maxX - 0.5, y: rect.maxY))
        borderPath.lineWidth = 1
        borderPath.stroke()

        // Text attributes for line numbers
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // Calculate visible rect in text view coordinates
        let visibleRect = textView.visibleRect
        let textInset = textView.textContainerInset

        // Enumerate paragraphs and draw line numbers
        var lineNumber = 1
        string.enumerateSubstrings(in: fullRange, options: [.byParagraphs, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            let glyphRange = layoutManager.glyphRange(forCharacterRange: enclosingRange, actualCharacterRange: nil)

            // Get the line fragment rect for the first glyph of this paragraph
            var lineFragmentRect = NSRect.zero
            if glyphRange.length > 0 {
                lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            } else if enclosingRange.location == string.length {
                // Empty last line - position below the last content
                if string.length > 0 {
                    let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: string.length - 1)
                    let lastRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
                    lineFragmentRect = NSRect(x: 0, y: lastRect.maxY, width: lastRect.width, height: lastRect.height)
                }
            }

            // Convert to ruler view coordinates
            let yPosition = lineFragmentRect.origin.y + textInset.height - visibleRect.origin.y

            // Only draw if visible
            if yPosition + lineFragmentRect.height >= 0 && yPosition <= rect.height {
                let lineNumberString = "\(lineNumber)"
                let size = lineNumberString.size(withAttributes: attributes)

                // Right-align the number with some padding
                let x = self.gutterWidth - size.width - 8
                let y = yPosition + (lineFragmentRect.height - size.height) / 2

                lineNumberString.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            }

            lineNumber += 1
        }

        // Handle empty text (show "1")
        if string.length == 0 {
            let lineNumberString = "1"
            let size = lineNumberString.size(withAttributes: attributes)
            let x = gutterWidth - size.width - 8
            let y = textInset.height + 2
            lineNumberString.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }
    }
}

struct MacCustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var platformTextView: (any PlatformTextView)?
    let windowDelegate: TextEditorWindowDelegate?
    let windowTitle: String
    let isBatchEditor: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSScrollView()

            // Create text system - use zebra striping only for batch editor
            let textStorage = NSTextStorage()
            let layoutManager: NSLayoutManager
            if isBatchEditor {
                layoutManager = ZebraStripingLayoutManager()
            } else {
                layoutManager = NSLayoutManager()
            }
            textStorage.addLayoutManager(layoutManager)

            let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            layoutManager.addTextContainer(textContainer)

            let textView = CustomNSTextView(frame: .zero, textContainer: textContainer)
            textView.font = NSFont.systemFont(ofSize: 16, weight: .regular)
            textView.textColor = .textColor
            textView.backgroundColor = .textBackgroundColor.withAlphaComponent(0.5)
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.autoresizingMask = [.width]
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.minSize = NSSize(width: 0, height: 0)

            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true

            // Add line number ruler only for batch editor
            if isBatchEditor {
                let rulerView = LineNumberRulerView(textView: textView)
                scrollView.verticalRulerView = rulerView
                scrollView.hasVerticalRuler = true
                scrollView.rulersVisible = true

                // Store ruler reference in coordinator for updates
                context.coordinator.rulerView = rulerView

                // Register for notifications to update ruler
                textView.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    context.coordinator,
                    selector: #selector(Coordinator.textDidChangeLayout(_:)),
                    name: NSView.frameDidChangeNotification,
                    object: textView
                )
                NotificationCenter.default.addObserver(
                    context.coordinator,
                    selector: #selector(Coordinator.textDidChangeLayout(_:)),
                    name: NSScrollView.didLiveScrollNotification,
                    object: scrollView
                )
            }

            textView.delegate = context.coordinator
            textView.string = text
            textView.typingAttributes[.font] = NSFont.systemFont(ofSize: 16, weight: .regular)
            textView.typingAttributes[.foregroundColor] = NSColor.textColor

            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.textDidChangeLayout(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )

            DispatchQueue.main.async {
                platformTextView = textView
            }

            context.coordinator.undoManager = textView.undoManager

            return scrollView
        }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
            guard let textView = nsView.documentView as? CustomNSTextView else { return }

            // Update text only if changed externally (preserves cursor)
            if textView.string != text {
                // Clear undo stack before programmatic text replacement
                // This prevents NSUndoManager from holding stale ranges that become invalid
                textView.undoManager?.removeAllActions()

                // Store the current selection
                let oldSelection = textView.selectedRange()

                // Replace the text
                textView.string = text

                // Clamp the selection to be valid for the new text length
                let newLength = (text as NSString).length
                let clampedLocation = min(oldSelection.location, newLength)
                let clampedLength = min(oldSelection.length, newLength - clampedLocation)
                let safeRange = NSRange(location: clampedLocation, length: clampedLength)
                textView.setSelectedRange(safeRange)
            }
            
            textView.typingAttributes[.font] = NSFont.systemFont(ofSize: 16, weight: .regular)
            textView.typingAttributes[.foregroundColor] = NSColor.textColor
            
            // Handle window delegate and title
            if let window = nsView.window {
                if let windowDelegate = windowDelegate, window.delegate !== windowDelegate {
                    windowDelegate.window = window
                    window.delegate = windowDelegate
                }
                if !windowTitle.isEmpty && window.title != windowTitle {
                    window.title = windowTitle
                }
            }
        }
    
    class Coordinator: NSObject, NSTextViewDelegate {
            var parent: MacCustomTextEditor
            var undoManager: UndoManager?
            weak var rulerView: LineNumberRulerView?

            init(parent: MacCustomTextEditor) {
                self.parent = parent
            }

            func textDidChange(_ notification: Notification) {
                if let textView = notification.object as? NSTextView {
                    parent.text = textView.string
                    // Update ruler when text changes
                    rulerView?.needsDisplay = true
                }
            }

            @objc func textDidChangeLayout(_ notification: Notification) {
                // Update ruler when layout or scroll position changes
                rulerView?.needsDisplay = true
            }

            deinit {
                NotificationCenter.default.removeObserver(self)
            }
        }
}
#endif

#if os(iOS)

// MARK: - Zebra Striping Layout Manager (iOS)

/// Custom layout manager that draws alternating background colors for each logical line (paragraph).
class ZebraStripingLayoutManageriOS: NSLayoutManager {

    /// Color for odd-numbered lines
    var oddLineColor: UIColor = UIColor.secondaryLabel.withAlphaComponent(0.06)

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage, let textContainer = textContainers.first else { return }

        let string = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)

        var paragraphIndex = 0
        string.enumerateSubstrings(in: fullRange, options: [.byParagraphs, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            if paragraphIndex % 2 == 1 {
                let glyphRange = self.glyphRange(forCharacterRange: enclosingRange, actualCharacterRange: nil)
                let intersection = NSIntersectionRange(glyphRange, glyphsToShow)
                if intersection.length > 0 {
                    var lineRect = self.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    lineRect.origin.x = 0
                    lineRect.size.width = textContainer.size.width
                    lineRect.origin.x += origin.x
                    lineRect.origin.y += origin.y

                    self.oddLineColor.setFill()
                    UIRectFill(lineRect)
                }
            }
            paragraphIndex += 1
        }
    }
}

class CustomUITextView: UITextView {
    // Removed customUndoManager
}

// MARK: - Line Number View (iOS)

/// A view that displays line numbers for each logical line (paragraph) in the text view.
class LineNumberView: UIView {
    weak var textView: UITextView?
    let gutterWidth: CGFloat = 36

    private let font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.5)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let textView = textView else { return }

        let layoutManager = textView.layoutManager
        let context = UIGraphicsGetCurrentContext()

        // Draw background
        UIColor.secondarySystemBackground.withAlphaComponent(0.5).setFill()
        context?.fill(rect)

        // Draw right border
        UIColor.separator.setStroke()
        let borderPath = UIBezierPath()
        borderPath.move(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY))
        borderPath.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.maxY))
        borderPath.lineWidth = 1
        borderPath.stroke()

        // Text attributes
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]

        let string = (textView.text ?? "") as NSString
        let fullRange = NSRange(location: 0, length: string.length)
        let textInset = textView.textContainerInset
        let contentOffset = textView.contentOffset

        // Enumerate paragraphs and draw line numbers
        var lineNumber = 1
        string.enumerateSubstrings(in: fullRange, options: [.byParagraphs, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            let glyphRange = layoutManager.glyphRange(forCharacterRange: enclosingRange, actualCharacterRange: nil)

            // Get the line fragment rect for the first glyph
            var lineFragmentRect = CGRect.zero
            if glyphRange.length > 0 {
                lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            } else if enclosingRange.location == string.length {
                // Empty last line
                if string.length > 0 {
                    let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: string.length - 1)
                    let lastRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
                    lineFragmentRect = CGRect(x: 0, y: lastRect.maxY, width: lastRect.width, height: lastRect.height)
                }
            }

            // Convert to line number view coordinates
            let yPosition = lineFragmentRect.origin.y + textInset.top - contentOffset.y

            // Only draw if visible
            if yPosition + lineFragmentRect.height >= 0 && yPosition <= rect.height {
                let lineNumberString = "\(lineNumber)"
                let size = lineNumberString.size(withAttributes: attributes)

                // Right-align with padding
                let x = self.gutterWidth - size.width - 8
                let y = yPosition + (lineFragmentRect.height - size.height) / 2

                lineNumberString.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
            }

            lineNumber += 1
        }

        // Handle empty text
        if string.length == 0 {
            let lineNumberString = "1"
            let size = lineNumberString.size(withAttributes: attributes)
            let x = gutterWidth - size.width - 8
            let y = textInset.top + 2
            lineNumberString.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
        }
    }
}

/// Container view that holds the text view and optionally a line number view
class LineNumberTextContainer: UIView {
    let lineNumberView: LineNumberView?
    let textView: CustomUITextView
    let showLineNumbers: Bool
    private let gutterWidth: CGFloat = 36

    init(textView: CustomUITextView, showLineNumbers: Bool = true) {
        self.textView = textView
        self.showLineNumbers = showLineNumbers

        if showLineNumbers {
            self.lineNumberView = LineNumberView()
        } else {
            self.lineNumberView = nil
        }

        super.init(frame: .zero)

        if let lineNumberView = lineNumberView {
            lineNumberView.textView = textView
            addSubview(lineNumberView)
        }
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if showLineNumbers, let lineNumberView = lineNumberView {
            lineNumberView.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
            textView.frame = CGRect(x: gutterWidth, y: 0, width: bounds.width - gutterWidth, height: bounds.height)
        } else {
            textView.frame = bounds
        }
    }

    func updateLineNumbers() {
        lineNumberView?.setNeedsDisplay()
    }
}

struct iOSCustomTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var platformTextView: (any PlatformTextView)?
    @Environment(\.colorScheme) var colorScheme  // Track dark/light mode
    let isBatchEditor: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> LineNumberTextContainer {
        // Create text system - use zebra striping only for batch editor
        let textStorage = NSTextStorage()
        let layoutManager: NSLayoutManager
        if isBatchEditor {
            layoutManager = ZebraStripingLayoutManageriOS()
        } else {
            layoutManager = NSLayoutManager()
        }
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = CustomUITextView(frame: .zero, textContainer: textContainer)
        textView.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        textView.delegate = context.coordinator
        textView.textColor = .label  // Adaptive color (white in dark mode, black in light)
        textView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.5)
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.contentInsetAdjustmentBehavior = .automatic
        textView.text = text

        let container = LineNumberTextContainer(textView: textView, showLineNumbers: isBatchEditor)
        context.coordinator.container = container

        DispatchQueue.main.async {
            platformTextView = textView
        }
        context.coordinator.undoManager = textView.undoManager
        return container
    }

    func updateUIView(_ uiView: LineNumberTextContainer, context: Context) {
        let textView = uiView.textView

        // Update text only if changed externally (prevents cursor jump)
        if textView.text != text {
            // Clear undo stack before programmatic text replacement
            // This prevents UndoManager from holding stale ranges that become invalid
            textView.undoManager?.removeAllActions()

            // Store the current selection
            let oldSelection = textView.selectedRange

            // Replace the text
            textView.text = text

            // Clamp the selection to be valid for the new text length
            let newLength = (text as NSString).length
            let clampedLocation = min(oldSelection.location, newLength)
            let clampedLength = min(oldSelection.length, newLength - clampedLocation)
            let safeRange = NSRange(location: clampedLocation, length: clampedLength)
            textView.selectedRange = safeRange
        }

        // Ensure textColor adapts to color scheme
        textView.textColor = .label  // Reapply to handle appearance changes
        textView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.5)
        textView.typingAttributes[.foregroundColor] = UIColor.label
        textView.typingAttributes[.font] = UIFont.systemFont(ofSize: 16, weight: .regular)

        // Refresh line numbers
        uiView.updateLineNumbers()
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: iOSCustomTextEditor
        var undoManager: UndoManager?
        weak var container: LineNumberTextContainer?

        init(parent: iOSCustomTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            container?.updateLineNumbers()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            container?.updateLineNumbers()
        }
    }
}
#endif
