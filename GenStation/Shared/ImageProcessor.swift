//  ImageProcessor.swift
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import ImageIO // Required for CGImageSource/Destination APIs
import UniformTypeIdentifiers



// No need for duplicated typealias or platformPngData extension—they're in PlatformAbstractions.swift

func processImageForUpload(image: PlatformImage, originalData: Data? = nil, format: String = "jpeg", isBase64: Bool = false, convertToJPG: Bool = false, scale50Percent: Bool = false) -> (data: Data, mimeType: String)? {
    var processedImage = image
    var useFormat = format
    var quality: CGFloat = 0.6  // Default
    
    if isBase64 {
        if scale50Percent {
            let newSize = CGSize(width: image.platformSize.width * 0.5, height: image.platformSize.height * 0.5)
            #if os(macOS)
            let resized = NSImage(size: newSize, flipped: false, drawingHandler: { _ in
                image.draw(in: NSRect(origin: .zero, size: newSize))
                return true
            })
            processedImage = resized
            #elseif os(iOS)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            if let resized = UIGraphicsGetImageFromCurrentImageContext() {
                processedImage = resized
            } else {
                UIGraphicsEndImageContext()
                return nil
            }
            UIGraphicsEndImageContext()
            #endif
        }
        if convertToJPG {
            useFormat = "jpeg"
            quality = 0.8  // Higher for base64 to balance size/quality
        }
    }
    
    let lower = useFormat.lowercased()
    let ext = lower == "jpeg" ? "jpg" : "png"
    let mime = lower == "jpeg" ? "image/jpeg" : "image/png"
    
    if lower == "png", let orig = originalData, isPNGData(orig) {
        // Passthrough original PNG data to preserve metadata/chunks
        return (orig, mime)
    }
    
    if let imageData = processedImage.platformData(forType: ext, compressionQuality: quality) {
        let safeData: Data
        if lower == "png" {
            safeData = imageData  // Generated PNG (may lose custom chunks)
        } else {
            safeData = stripExif(from: imageData) ?? imageData
        }
        return (safeData, mime)
    }
    return nil
}

private func stripExif(from imageData: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
          let type = CGImageSourceGetType(source) else {
        return nil
    }
    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, type, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImageFromSource(destination, source, 0, nil) // Copies without metadata
    guard CGImageDestinationFinalize(destination) else { return nil }
    return mutableData as Data
}
// In ImageProcessor.swift (add at the end; replace any prior PNG function)

/// Returns true if data is JPEG (checks signature).
func isJPEGData(_ data: Data) -> Bool {
    guard data.count >= 2 else { return false }
    return data[0] == 0xFF && data[1] == 0xD8
}

/// Converts image data to JPEG (if not already) and adds an EXIF UserComment (e.g., "[prompt]\n[creator]"), preserving compatible metadata.
/// Returns JPEG data with EXIF on success; nil on failure.
/// Truncates prompt to maxTotalLength chars (with "..." if needed); set high for no effective limit.
func addCommentToJPEG(inputData: Data, prompt: String, creator: String, quality: CGFloat = 0.95, maxTotalLength: Int = 255) -> Data? {
    guard let source = CGImageSourceCreateWithData(inputData as CFData, nil) else {
        return nil
    }
    
    let count = CGImageSourceGetCount(source)
    guard count > 0 else {
        return nil
    }
    
    let destinationData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(destinationData as CFMutableData, UTType.jpeg.identifier as CFString, count, nil)
    else {
        return nil
    }
    
    // Truncate prompt to fit total limit (reserve space for "\n" + creator)
    let reserved = 1 + creator.count  // "\n" + creator
    let maxPromptLen = maxTotalLength - reserved
    let truncatedPrompt = (prompt.count > maxPromptLen) ? String(prompt.prefix(max(0, maxPromptLen - 3))) + "..." : prompt
    let comment = "\(truncatedPrompt)\n\(creator)"  // Eliminated "Prompt: " for space
    
    for i in 0..<count {
        // Copy existing properties (preserves compatible metadata)
        var mutableProps = (CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]) ?? [:]
        
        // Add/update EXIF dictionary with UserComment
        var exifDict = mutableProps[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exifDict[kCGImagePropertyExifUserComment as String] = comment
        mutableProps[kCGImagePropertyExifDictionary as String] = exifDict
        
        // Set JPEG compression quality
        let destOptions = [kCGImageDestinationMergeMetadata: true as CFBoolean, kCGImageDestinationImageMaxPixelSize: 0 as CFNumber, kCGImageDestinationLossyCompressionQuality: quality as CFNumber] as CFDictionary
        
        // Add image with updated props
        CGImageDestinationAddImageFromSource(destination, source, i, mutableProps as CFDictionary)
        CGImageDestinationSetProperties(destination, destOptions)
    }
    
    guard CGImageDestinationFinalize(destination) else { return nil }
    return destinationData as Data
}

/// Adds an EXIF UserComment to PNG data, preserving the PNG format losslessly.
/// Returns PNG data with EXIF on success; nil on failure.
func addCommentToPNG(inputData: Data, prompt: String, creator: String, maxTotalLength: Int = 255) -> Data? {
    guard let source = CGImageSourceCreateWithData(inputData as CFData, nil) else {
        return nil
    }

    let count = CGImageSourceGetCount(source)
    guard count > 0 else {
        return nil
    }

    let destinationData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(destinationData as CFMutableData, UTType.png.identifier as CFString, count, nil)
    else {
        return nil
    }

    let reserved = 1 + creator.count
    let maxPromptLen = maxTotalLength - reserved
    let truncatedPrompt = (prompt.count > maxPromptLen) ? String(prompt.prefix(max(0, maxPromptLen - 3))) + "..." : prompt
    let comment = "\(truncatedPrompt)\n\(creator)"

    for i in 0..<count {
        var mutableProps = (CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]) ?? [:]
        var exifDict = mutableProps[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exifDict[kCGImagePropertyExifUserComment as String] = comment
        mutableProps[kCGImagePropertyExifDictionary as String] = exifDict

        CGImageDestinationAddImageFromSource(destination, source, i, mutableProps as CFDictionary)
    }

    guard CGImageDestinationFinalize(destination) else { return nil }
    return destinationData as Data
}

/// Detects image format from data magic bytes. Returns file extension.
func detectImageFormat(_ data: Data) -> String {
    if isJPEGData(data) { return "jpg" }
    if isPNGData(data) { return "png" }
    // WebP: "RIFF" + 4 bytes + "WEBP"
    if data.count >= 12 && data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46
        && data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50 {
        return "webp"
    }
    // TIFF: "II" (little-endian) or "MM" (big-endian)
    if data.count >= 4 && ((data[0] == 0x49 && data[1] == 0x49) || (data[0] == 0x4D && data[1] == 0x4D)) {
        return "tiff"
    }
    return "unknown"
}
