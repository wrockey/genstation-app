// PhotosLibraryHelper.swift
import SwiftUI
#if os(iOS)
import Photos
#elseif os(macOS)
import AppKit
#endif
import GenStationCore

struct PhotosLibraryHelper {
    /// Saves images to Photos (iOS) or Pictures folder (macOS)
    /// Returns (successCount, totalCount)
    static func saveToPhotosLibrary(items: [HistoryItem], appState: AppState) async -> (Int, Int) {
        var success = 0
        let total = items.count
        
        for item in items {
            guard let path = item.imagePath else { continue }
            let fileURL = URL(fileURLWithPath: path)
            
            // Reuse your existing fileExists logic — it already resumes the bookmark!
            guard item.fileExists(appState: appState) else { continue }
            
            // CRITICAL: Resume access to the OUTPUT DIRECTORY (not the file)
            guard let outputDir = appState.settings.outputDirectory else { continue }
            
            let dirAccessStarted = outputDir.startAccessingSecurityScopedResource()
            defer {
                if dirAccessStarted {
                    outputDir.stopAccessingSecurityScopedResource()
                }
            }
            
            // Now read — this WILL work because the directory is resumed
            guard let imageData = try? Data(contentsOf: fileURL), !imageData.isEmpty else {
                Log.debug("PhotosLibraryHelper: Failed to read data from \(fileURL.path)")
                continue
            }
            
            #if os(iOS)
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .photo, data: imageData, options: nil)
                }
                success += 1
            } catch {
                Log.debug("Photos save failed: \(error)")
            }
            
            #elseif os(macOS)
            guard let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else { continue }
            let destURL = picturesURL.appendingPathComponent("GenStation – \(fileURL.lastPathComponent)")
            
            do {
                try imageData.write(to: destURL, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([destURL])
                success += 1
            } catch {
                Log.debug("Failed to write to Pictures: \(error)")
            }
            #endif
            
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        
        return (success, total)
    }
}
