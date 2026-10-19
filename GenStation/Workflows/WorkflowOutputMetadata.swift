import Foundation
import ImageIO
import AVFoundation
import UniformTypeIdentifiers
import GenStationCore

struct WorkflowOutputMetadata {
    let mediaType: String
    let width: Int?
    let height: Int?
    static func inspect(_ data: Data, filename: String) throws -> Self {
        let ext = (filename as NSString).pathExtension.lowercased()
        let videoTypes = ["mp4": "video/mp4", "m4v": "video/x-m4v", "mov": "video/quicktime", "webm": "video/webm"]
        if let type = videoTypes[ext] {
            let validHeader = ext == "webm" ? data.starts(with: [0x1a, 0x45, 0xdf, 0xa3]) :
                (data.count >= 12 && ["ftyp", "moov", "mdat", "wide"].contains(String(data: data.subdata(in: 4..<8), encoding: .ascii) ?? ""))
            guard validHeader else { throw AgentImageError("Output does not contain a supported video container.") }
            return Self(mediaType: type, width: nil, height: nil)
        }
        let imageTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp", "gif": "image/gif"]
        guard imageTypes[ext] != nil, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier)?.preferredMIMEType, imageTypes.values.contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 40_000_000 else {
            throw AgentImageError("Output is not a supported image/video original, or exceeds the 40-megapixel image limit.")
        }
        return Self(mediaType: type, width: width, height: height)
    }

    static func videoDimensions(at path: String) async -> (Int, Int)? {
        do {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let display = size.applying(transform)
            guard display.width.isFinite, display.height.isFinite, abs(display.width) > 0, abs(display.height) > 0,
                  abs(display.width) <= 16_384, abs(display.height) <= 16_384 else { return nil }
            return (Int(abs(display.width)), Int(abs(display.height)))
        } catch { return nil }
    }
}
