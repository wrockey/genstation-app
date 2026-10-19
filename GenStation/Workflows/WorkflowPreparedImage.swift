import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import GenStationCore

/// In-memory, approved upload material. Only identifiers/hashes enter the ledger.
struct WorkflowPreparedImage {
    let name: String
    let assetID: UUID
    let sourceDigest: String
    let pngData: Data
    var snapshot: WorkflowInputSnapshot { .init(name: name, assetID: assetID, contentSHA256: sourceDigest) }

    init(name: String, assetID: UUID, original: Data) throws {
        guard original.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(original as CFData, nil), CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?, [UTType.png.identifier, UTType.jpeg.identifier].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 40_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)] as CFDictionary) else {
            throw AgentImageError("Workflow reference must be one PNG/JPEG image, at most 20 MB and 40 megapixels.")
        }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else {
            throw AgentImageError("Could not prepare workflow reference.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), encoded.length <= 20_000_000 else {
            throw AgentImageError("Prepared PNG reference exceeds the 20 MB upload limit.")
        }
        self.name = name; self.assetID = assetID
        sourceDigest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        pngData = encoded as Data
    }
}
