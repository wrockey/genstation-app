import Foundation
import CoreML
import Vision
import CoreImage
import CoreGraphics
import Metal
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import GenStationCore

// MARK: - Errors

enum UpscaleError: LocalizedError {
    case modelLoadFailed(String)
    case unsupportedHardware
    case imageLoadFailed
    case imageTooLarge(width: Int, height: Int)
    case cancelled
    case outputAssemblyFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let reason):
            return "Failed to load upscaling model: \(reason)"
        case .unsupportedHardware:
            return "Metal GPU not available on this device"
        case .imageLoadFailed:
            return "Source image not found"
        case .imageTooLarge(let w, let h):
            return "Image too large to upscale (\(w)x\(h), max 4096x4096)"
        case .cancelled:
            return "Upscale cancelled"
        case .outputAssemblyFailed:
            return "Failed to assemble upscaled image"
        }
    }
}

// MARK: - UpscaleService

/// On-device 4x image upscaling using Real-ESRGAN Core ML model via Vision framework.
/// Uses tile-based processing (512x512 tiles → 2048x2048 output tiles) to keep memory bounded.
final class UpscaleService: @unchecked Sendable {

    static let shared = UpscaleService()

    private let scaleFactor = 4
    private let tileSize = 512
    private let maxSourceDimension = 4096
    private let maxOutputPixels = 20_000_000  // ~20MP cap, post-scale if exceeded
    private let ciContext = CIContext()

    private var visionModel: VNCoreMLModel?
    private let lock = NSLock()

    // MARK: - Hardware Check

    static func isSupported() -> Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }

    // MARK: - Model Loading

    private func ensureModel() throws -> VNCoreMLModel {
        lock.lock()
        defer { lock.unlock() }

        if let existing = visionModel { return existing }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        do {
            let mlModel = try RealESRGAN(configuration: config).model
            let vnModel = try VNCoreMLModel(for: mlModel)
            self.visionModel = vnModel
            return vnModel
        } catch {
            throw UpscaleError.modelLoadFailed(error.localizedDescription)
        }
    }

    // MARK: - Upscale

    func upscale(image: CGImage, progressHandler: (@Sendable (Double) -> Void)? = nil) throws -> CGImage {
        guard UpscaleService.isSupported() else {
            throw UpscaleError.unsupportedHardware
        }

        let width = image.width
        let height = image.height

        guard width <= maxSourceDimension && height <= maxSourceDimension else {
            throw UpscaleError.imageTooLarge(width: width, height: height)
        }

        let model = try ensureModel()

        // Pad image to tile boundary
        let paddedImage = try padImageToTileBoundary(image)
        let paddedWidth = paddedImage.width
        let paddedHeight = paddedImage.height

        let upscaledWidth = width * scaleFactor
        let upscaledHeight = height * scaleFactor
        let paddedUpscaledWidth = paddedWidth * scaleFactor
        let paddedUpscaledHeight = paddedHeight * scaleFactor
        let upscaledTileSize = tileSize * scaleFactor

        let tilesX = paddedWidth / tileSize
        let tilesY = paddedHeight / tileSize
        let totalTiles = tilesX * tilesY
        var completedTiles = 0

        // Create output context for stitching
        guard let outputContext = CGContext(
            data: nil,
            width: paddedUpscaledWidth,
            height: paddedUpscaledHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw UpscaleError.outputAssemblyFailed
        }

        // Process each tile using regionOfInterest
        for tx in 0..<tilesX {
            for ty in 0..<tilesY {
                // Vision uses normalized coordinates (0-1), origin at bottom-left
                let regionX = Double(tx * tileSize) / Double(paddedWidth)
                let regionY = Double(ty * tileSize) / Double(paddedHeight)
                let regionW = Double(tileSize) / Double(paddedWidth)
                let regionH = Double(tileSize) / Double(paddedHeight)

                var tileError: Error?
                let request = VNCoreMLRequest(model: model) { request, error in
                    if let error = error {
                        tileError = error
                        return
                    }
                    guard let observations = request.results as? [VNPixelBufferObservation],
                          let pixelBuffer = observations.first?.pixelBuffer else {
                        tileError = UpscaleError.outputAssemblyFailed
                        return
                    }

                    let ciImage = CIImage(cvImageBuffer: pixelBuffer)
                    guard let cgResult = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                        tileError = UpscaleError.outputAssemblyFailed
                        return
                    }
                    outputContext.draw(cgResult, in: CGRect(
                        x: tx * upscaledTileSize,
                        y: ty * upscaledTileSize,
                        width: cgResult.width,
                        height: cgResult.height
                    ))
                }

                request.regionOfInterest = CGRect(x: regionX, y: regionY, width: regionW, height: regionH)
                request.imageCropAndScaleOption = .scaleFill

                let handler = VNImageRequestHandler(cgImage: paddedImage)
                try handler.perform([request])

                if let tileError = tileError { throw tileError }

                completedTiles += 1
                progressHandler?(Double(completedTiles) / Double(totalTiles))
            }
        }

        // Crop padded upscaled image to final size
        guard let paddedResult = outputContext.makeImage() else {
            throw UpscaleError.outputAssemblyFailed
        }

        // Crop from bottom-left (CGImage origin) — remove top/right padding
        let cropRect = CGRect(x: 0, y: paddedUpscaledHeight - upscaledHeight, width: upscaledWidth, height: upscaledHeight)
        guard let croppedImage = paddedResult.cropping(to: cropRect) else {
            throw UpscaleError.outputAssemblyFailed
        }

        // Post-scale if output exceeds pixel budget
        let outputPixels = upscaledWidth * upscaledHeight
        if outputPixels > maxOutputPixels {
            let scale = sqrt(Double(maxOutputPixels) / Double(outputPixels))
            let targetW = Int(Double(upscaledWidth) * scale)
            let targetH = Int(Double(upscaledHeight) * scale)
            Log.debug("Post-scaling \(upscaledWidth)x\(upscaledHeight) (\(outputPixels/1_000_000)MP) → \(targetW)x\(targetH) (\(targetW * targetH / 1_000_000)MP)")
            return try downscaleImage(croppedImage, toWidth: targetW, height: targetH)
        }

        return croppedImage
    }

    // MARK: - Post-Scale

    private func downscaleImage(_ image: CGImage, toWidth targetW: Int, height targetH: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw UpscaleError.outputAssemblyFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let result = context.makeImage() else {
            throw UpscaleError.outputAssemblyFailed
        }
        return result
    }

    // MARK: - Padding

    private func padImageToTileBoundary(_ image: CGImage) throws -> CGImage {
        let w = image.width
        let h = image.height

        let paddedW = ((w + tileSize - 1) / tileSize) * tileSize
        let paddedH = ((h + tileSize - 1) / tileSize) * tileSize

        if paddedW == w && paddedH == h {
            return image
        }

        guard let context = CGContext(
            data: nil,
            width: paddedW,
            height: paddedH,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw UpscaleError.outputAssemblyFailed
        }

        // Draw at origin (bottom-left in CG coordinates), padding extends top and right
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let padded = context.makeImage() else {
            throw UpscaleError.outputAssemblyFailed
        }
        return padded
    }

    // MARK: - Save Upscaled Image

    static func saveUpscaledImage(data: Data, outputDirectory: URL?) -> String? {
        let fileManager = FileManager.default
        var outputDir = outputDirectory

        if outputDir == nil {
            outputDir = AppStorageContext.fallbackOutputDirectory
        }
        guard let dirURL = outputDir else { return nil }

        var resolvedDir = dirURL
        var didStart = false

        do {
            if outputDirectory != nil {
                didStart = resolvedDir.startAccessingSecurityScopedResource()
                if !didStart {
                    guard let downloads = AppStorageContext.fallbackOutputDirectory else { return nil }
                    resolvedDir = downloads
                }
            }
            defer { if didStart { resolvedDir.stopAccessingSecurityScopedResource() } }

            // List existing files for unique filename
            var existingFiles: [URL] = []
            var listError: NSError?
            var innerListError: Error?
            NSFileCoordinator().coordinate(readingItemAt: resolvedDir, options: [], error: &listError) { coordinatedURL in
                do {
                    existingFiles = try fileManager.contentsOfDirectory(at: coordinatedURL, includingPropertiesForKeys: nil)
                } catch {
                    innerListError = error
                }
            }
            if let listError = listError { throw listError }
            if let innerListError = innerListError { throw innerListError }

            // Auto-increment filename
            let prefix = "upscaled_4x_"
            let generatedFiles = existingFiles.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "png" }
            let numbers = generatedFiles.compactMap {
                Int($0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: prefix, with: ""))
            }
            let nextNum = (numbers.max() ?? 0) + 1
            let filename = "\(prefix)\(nextNum).png"
            let fileURL = resolvedDir.appendingPathComponent(filename)

            // Write file
            var writeError: NSError?
            var innerWriteError: Error?
            let writeOptions: NSFileCoordinator.WritingOptions = fileManager.fileExists(atPath: fileURL.path) ? .forReplacing : []
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: writeOptions, error: &writeError) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL)
                } catch {
                    innerWriteError = error
                }
            }
            if let writeError = writeError { throw writeError }
            if let innerWriteError = innerWriteError { throw innerWriteError }

            return fileURL.path
        } catch {
            Log.debug("Failed to save upscaled image: \(error)")
            let tempURL = AppStorageContext.current.temporaryDirectory.appendingPathComponent("upscaled_4x_\(Date().timeIntervalSince1970).png")
            do {
                try data.write(to: tempURL)
                return tempURL.path
            } catch {
                return nil
            }
        }
    }

    // MARK: - Shared Pipeline

    @MainActor
    static func upscaleHistoryItem(
        _ item: HistoryItem,
        appState: AppState,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> HistoryItem {
        // 1. Load full image
        guard let platformImage = await LazyThumbnailView.loadFullImage(for: item, appState: appState) else {
            throw UpscaleError.imageLoadFailed
        }

        guard let cgImage = platformImage.asCGImage else {
            throw UpscaleError.imageLoadFailed
        }

        // 2. Run upscale, PNG encode, and save on background thread
        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        let outputDir = appState.settings.outputDirectory
        let (savedPath, outputWidth, outputHeight) = try await Task.detached(priority: .userInitiated) {
            let upscaledCG = try shared.upscale(image: cgImage, progressHandler: progressHandler)

            let upscaledImage = PlatformImage(cgImageSource: upscaledCG)
            guard let pngData = upscaledImage.platformPngData() else {
                throw UpscaleError.outputAssemblyFailed
            }

            guard let path = saveUpscaledImage(data: pngData, outputDirectory: outputDir) else {
                throw UpscaleError.outputAssemblyFailed
            }
            return (path, upscaledCG.width, upscaledCG.height)
        }.value

        // 5. Create new history item
        let newItem = HistoryItem(
            prompt: item.prompt,
            responseText: "Upscaled \(sourceWidth)x\(sourceHeight) → \(outputWidth)x\(outputHeight) from \(item.modelUsed ?? "unknown model") output",
            imagePath: savedPath,
            date: Date(),
            mode: item.mode,
            task: .image,  // Upscaling always yields a still, whatever the source was.
            modelUsed: "Real-ESRGAN 4x",
            parentItemId: item.id
        )

        appState.historyState.history.append(.item(newItem))
        appState.ui.sessionGeneratedIDs.append(newItem.id)
        appState.historyState.saveHistory()

        return newItem
    }
}
