// VideoExporter.swift
// Video export utilities including GIF conversion

import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - GIF Export Options

struct GIFExportOptions {
    var frameRate: Int = 10           // Frames per second
    var loopCount: Int = 0            // 0 = infinite loop
    var maxDimension: CGFloat = 480   // Max width/height in pixels

    static let small = GIFExportOptions(frameRate: 10, loopCount: 0, maxDimension: 320)
    static let medium = GIFExportOptions(frameRate: 10, loopCount: 0, maxDimension: 480)
    static let large = GIFExportOptions(frameRate: 15, loopCount: 0, maxDimension: 720)
}

// MARK: - Video to GIF Exporter

class VideoToGIFExporter {

    enum ExportError: LocalizedError {
        case noVideoTrack
        case frameExtractionFailed
        case gifCreationFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "Video has no video track"
            case .frameExtractionFailed: return "Failed to extract frames from video"
            case .gifCreationFailed: return "Failed to create GIF file"
            case .cancelled: return "Export was cancelled"
            }
        }
    }

    /// Export video to animated GIF
    /// - Parameters:
    ///   - videoURL: URL of the source video file
    ///   - options: GIF export options (frame rate, size, loop count)
    ///   - progress: Optional progress callback (0.0 to 1.0)
    /// - Returns: GIF data
    static func exportGIF(
        from videoURL: URL,
        options: GIFExportOptions = .medium,
        progress: ((Double) -> Void)? = nil
    ) async throws -> Data {
        let asset = AVAsset(url: videoURL)

        // Get video duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw ExportError.noVideoTrack
        }

        // Create image generator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: options.maxDimension, height: options.maxDimension)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        // Calculate frame times
        let frameCount = max(1, Int(durationSeconds * Double(options.frameRate)))
        var times: [CMTime] = []
        for i in 0..<frameCount {
            let time = CMTime(seconds: Double(i) / Double(options.frameRate), preferredTimescale: 600)
            times.append(time)
        }

        // Extract frames
        var images: [CGImage] = []
        for (index, time) in times.enumerated() {
            try Task.checkCancellation()

            do {
                let result = try await generator.image(at: time)
                images.append(result.image)
                progress?(Double(index + 1) / Double(times.count) * 0.9)  // 0-90% for frame extraction
            } catch {
                // Skip frames that fail to extract
                Log.debug("Failed to extract frame at \(CMTimeGetSeconds(time))s: \(error)")
                continue
            }
        }

        guard !images.isEmpty else {
            throw ExportError.frameExtractionFailed
        }

        // Create GIF
        progress?(0.95)
        let gifData = try createGIF(from: images, options: options)
        progress?(1.0)

        return gifData
    }

    /// Create GIF data from array of CGImages
    private static func createGIF(from images: [CGImage], options: GIFExportOptions) throws -> Data {
        let gifData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            gifData,
            UTType.gif.identifier as CFString,
            images.count,
            nil
        ) else {
            throw ExportError.gifCreationFailed
        }

        // Set GIF properties (loop count)
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: options.loopCount
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Calculate frame delay
        let frameDelay = 1.0 / Double(options.frameRate)
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime as String: frameDelay
            ]
        ]

        // Add each frame
        for image in images {
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.gifCreationFailed
        }

        return gifData as Data
    }
}

// MARK: - GIF Export Sheet View

struct GIFExportSheet: View {
    let videoURL: URL
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    @State private var selectedQuality: GIFQuality = .medium
    @State private var customFrameRate: Double = 10
    @State private var isExporting: Bool = false
    @State private var exportProgress: Double = 0
    @State private var exportError: String? = nil
    @State private var exportedData: Data? = nil

    enum GIFQuality: String, CaseIterable, Identifiable {
        case small = "Small (320px)"
        case medium = "Medium (480px)"
        case large = "Large (720px)"

        var id: String { rawValue }

        var options: GIFExportOptions {
            switch self {
            case .small: return .small
            case .medium: return .medium
            case .large: return .large
            }
        }

        var estimatedSize: String {
            switch self {
            case .small: return "~1-3 MB"
            case .medium: return "~3-8 MB"
            case .large: return "~8-20 MB"
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Export as GIF")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            if isExporting {
                // Progress view
                VStack(spacing: 12) {
                    ProgressView(value: exportProgress)
                        .progressViewStyle(.linear)

                    Text("Exporting... \(Int(exportProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if let error = exportError {
                // Error view
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        exportError = nil
                    }
                    .buttonStyle(.bordered)
                }
            } else if let data = exportedData {
                // Success view
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("GIF created successfully!")
                        .font(.subheadline)
                    Text("Size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button("Save") {
                            saveGIF(data: data)
                        }
                        .buttonStyle(.borderedProminent)

                        #if os(iOS)
                        Button("Share") {
                            shareGIF(data: data)
                        }
                        .buttonStyle(.bordered)
                        #endif

                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                // Options view
                VStack(alignment: .leading, spacing: 16) {
                    // Quality picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quality")
                            .font(.subheadline.weight(.medium))

                        Picker("Quality", selection: $selectedQuality) {
                            ForEach(GIFQuality.allCases) { quality in
                                Text(quality.rawValue).tag(quality)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Estimated size: \(selectedQuality.estimatedSize)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Frame rate
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Frame Rate: \(Int(customFrameRate)) fps")
                            .font(.subheadline.weight(.medium))

                        Slider(value: $customFrameRate, in: 5...20, step: 1)

                        Text("Higher = smoother but larger file")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Export button
                Button {
                    startExport()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export GIF")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 300)
    }

    private func startExport() {
        isExporting = true
        exportProgress = 0
        exportError = nil

        Task {
            // Start security-scoped access if video is in output directory
            var securityScopeStarted = false
            if let outputDir = appState.settings.outputDirectory,
               videoURL.path.hasPrefix(outputDir.path) {
                securityScopeStarted = outputDir.startAccessingSecurityScopedResource()
            }

            defer {
                if securityScopeStarted {
                    appState.settings.outputDirectory?.stopAccessingSecurityScopedResource()
                }
            }

            do {
                var options = selectedQuality.options
                options.frameRate = Int(customFrameRate)

                let data = try await VideoToGIFExporter.exportGIF(
                    from: videoURL,
                    options: options,
                    progress: { progress in
                        Task { @MainActor in
                            exportProgress = progress
                        }
                    }
                )

                await MainActor.run {
                    exportedData = data
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }

    private func saveGIF(data: Data) {
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.gif]
        savePanel.nameFieldStringValue = "exported.gif"
        savePanel.canCreateDirectories = true

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try data.write(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                dismiss()  // Auto-dismiss after successful save
            } catch {
                Log.debug("Failed to save GIF: \(error)")
            }
        }
        #else
        // iOS: Save to temporary file and share
        let tempURL = AppStorageContext.current.temporaryDirectory.appendingPathComponent("exported.gif")
        do {
            try data.write(to: tempURL)
            shareGIF(data: data)
            dismiss()  // Auto-dismiss after successful save
        } catch {
            Log.debug("Failed to save GIF: \(error)")
        }
        #endif
    }

    #if os(iOS)
    private func shareGIF(data: Data) {
        let tempURL = AppStorageContext.current.temporaryDirectory.appendingPathComponent("exported.gif")
        do {
            try data.write(to: tempURL)

            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                // Find the topmost presented controller
                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                topVC.present(activityVC, animated: true)
            }
        } catch {
            Log.debug("Failed to share GIF: \(error)")
        }
    }
    #endif
}
