//
// PKCanvasRepresentable.swift
//
#if os(iOS)
import SwiftUI
import PencilKit
import UIKit

struct PKCanvasRepresentable: UIViewRepresentable {
    let backgroundImage: UIImage
    @Binding var drawing: PKDrawing
    @Binding var contentOffset: CGPoint
    @Binding var zoomScale: CGFloat
    @Binding var undoManagerRef: UndoManager?
    @Binding var isToolPickerVisible: Bool
    @Binding var adjustedInset: UIEdgeInsets
    @Binding var initialFitScale: CGFloat?
    var onStrokeAdded: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = context.coordinator
        context.coordinator.canvasView = canvasView

        // Background image setup — as a sibling behind the canvas
        let bgImageView = UIImageView(image: backgroundImage)
        bgImageView.contentMode = .topLeft
        bgImageView.frame = CGRect(origin: .zero, size: backgroundImage.size)
        context.coordinator.backgroundImageView = bgImageView

        // We'll add the background image view as a subview of the canvas's superview
        // in updateUIView once it's in the hierarchy. For now, set content size.
        canvasView.contentSize = backgroundImage.size

        // Tool picker
        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()

        // Defer zoom setup to allow layout to complete
        DispatchQueue.main.async {
            self.configureZoom(canvasView: canvasView, coordinator: context.coordinator)
        }

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        let coordinator = context.coordinator

        // Install background image view as sibling if not yet done
        if let bgView = coordinator.backgroundImageView,
           bgView.superview == nil,
           let superview = canvasView.superview {
            superview.insertSubview(bgView, belowSubview: canvasView)
            syncBackgroundTransform(canvasView: canvasView, coordinator: coordinator)
        }

        // Update drawing if changed externally (undo/clear from SwiftUI)
        coordinator.isUpdatingFromSwiftUI = true
        if canvasView.drawing != drawing {
            coordinator.isSuppressingUndoRecord = true
            canvasView.drawing = drawing
            coordinator.isSuppressingUndoRecord = false
        }
        coordinator.isUpdatingFromSwiftUI = false

        // Toggle tool picker visibility
        if let toolPicker = coordinator.toolPicker {
            if isToolPickerVisible {
                toolPicker.setVisible(true, forFirstResponder: canvasView)
                if !canvasView.isFirstResponder {
                    canvasView.becomeFirstResponder()
                }
            } else {
                toolPicker.setVisible(false, forFirstResponder: canvasView)
                canvasView.resignFirstResponder()
            }
        }
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        if let toolPicker = coordinator.toolPicker {
            toolPicker.setVisible(false, forFirstResponder: uiView)
            toolPicker.removeObserver(uiView)
        }
        coordinator.toolPicker = nil
        coordinator.canvasView = nil
    }

    private func configureZoom(canvasView: PKCanvasView, coordinator: Coordinator) {
        let viewSize = canvasView.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else {
            // Retry if not yet laid out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.configureZoom(canvasView: canvasView, coordinator: coordinator)
            }
            return
        }

        let imageSize = backgroundImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let fitScale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        coordinator.initialFitScale = fitScale

        // Report initialFitScale back to SwiftUI
        DispatchQueue.main.async {
            self.initialFitScale = fitScale
        }

        canvasView.minimumZoomScale = min(1.0, fitScale)
        canvasView.maximumZoomScale = min(5.0, fitScale * 10)
        canvasView.zoomScale = fitScale

        // Report initial values
        DispatchQueue.main.async {
            self.zoomScale = fitScale
            self.contentOffset = canvasView.contentOffset
            self.adjustedInset = canvasView.adjustedContentInset
            self.undoManagerRef = canvasView.undoManager
        }
    }

    fileprivate func syncBackgroundTransform(canvasView: PKCanvasView, coordinator: Coordinator) {
        guard let bgView = coordinator.backgroundImageView else { return }
        let offset = canvasView.contentOffset
        let zoom = canvasView.zoomScale
        let inset = canvasView.adjustedContentInset

        bgView.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        bgView.frame = CGRect(
            x: -offset.x + inset.left,
            y: -offset.y + inset.top,
            width: backgroundImage.size.width * zoom,
            height: backgroundImage.size.height * zoom
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate {
        var parent: PKCanvasRepresentable
        var toolPicker: PKToolPicker?
        weak var canvasView: PKCanvasView?
        var backgroundImageView: UIImageView?
        var isUpdatingFromSwiftUI = false
        var isSuppressingUndoRecord = false
        var initialFitScale: CGFloat = 1.0

        init(parent: PKCanvasRepresentable) {
            self.parent = parent
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingFromSwiftUI else { return }
            parent.drawing = canvasView.drawing
            if !isSuppressingUndoRecord {
                parent.onStrokeAdded?()
            }
        }

        // MARK: UIScrollViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isUpdatingFromSwiftUI else { return }
            parent.contentOffset = scrollView.contentOffset
            parent.adjustedInset = scrollView.adjustedContentInset
            if let cv = canvasView {
                parent.syncBackgroundTransform(canvasView: cv, coordinator: self)
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard !isUpdatingFromSwiftUI else { return }
            parent.zoomScale = scrollView.zoomScale
            parent.adjustedInset = scrollView.adjustedContentInset
            if let cv = canvasView {
                parent.syncBackgroundTransform(canvasView: cv, coordinator: self)
            }
        }

        // Do NOT implement viewForZooming(in:) — PK manages zoom internally
    }
}
#endif
