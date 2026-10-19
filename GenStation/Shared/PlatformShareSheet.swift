// PlatformShareSheet.swift

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Unified Share Sheet Abstraction (macOS + iOS)
struct PlatformShareSheet {
    static func present(items: [Any]) {
        #if os(macOS)
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = SharingDelegate.shared
        
        if let window = NSApp.keyWindow ?? NSApp.mainWindow,
           let view = window.contentView {
            let rect = NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
        }
        
        #elseif os(iOS)
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        activityVC.excludedActivityTypes = [
            .addToReadingList, .assignToContact, .copyToPasteboard,
            .mail, .markupAsPDF, .message, .openInIBooks,
            .postToFacebook, .postToFlickr, .postToTwitter,
            .postToVimeo, .postToWeibo, .print, .saveToCameraRoll
        ]
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = UIView()
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX,
                                        y: UIScreen.main.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        
        var topVC = keyWindow?.rootViewController
        while let presented = topVC?.presentedViewController {
            topVC = presented
        }
        topVC?.present(activityVC, animated: true)
        #endif
    }
}

// MARK: - macOS: Custom services for AirDrop, Copy, and Save
#if os(macOS)

private class SharingDelegate: NSObject, NSSharingServicePickerDelegate {
    static let shared = SharingDelegate()
    
    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        sharingServicesForItems items: [Any],
        proposedSharingServices proposedServices: [NSSharingService]
    ) -> [NSSharingService] {
        
        var allowed: [NSSharingService] = []
        
        // 1. AirDrop (use system-provided)
        if let airdrop = proposedServices.first(where: { $0.title.lowercased().contains("airdrop") }) {
            allowed.append(airdrop)
        }
        
        // 2. Custom "Save Package…" (triggers NSSavePanel)
        let capturedItemsForSave = items
        let customSave = NSSharingService(
            title: "Save Package…",
            image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save") ?? NSImage(),
            alternateImage: nil,
            handler: {
                guard let url = capturedItemsForSave.first as? URL else { return }
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [UTType.gzip]
                savePanel.nameFieldStringValue = url.lastPathComponent
                if savePanel.runModal() == .OK, let dest = savePanel.url {
                    do {
                        try FileManager.default.copyItem(at: url, to: dest)
                    } catch {
                        Log.debug("Failed to save package: \(error)")
                    }
                }
            }
        )
        allowed.append(customSave)
        
        // 3. Custom "Copy Package" (copies file to pasteboard)
        let capturedItemsForCopy = items
        let customCopy = NSSharingService(
            title: "Copy Package",
            image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy") ?? NSImage(),
            alternateImage: nil,
            handler: {
                guard let url = capturedItemsForCopy.first as? URL else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([url as NSURL])
            }
        )
        allowed.append(customCopy)
        
        return allowed
    }
}

#endif
