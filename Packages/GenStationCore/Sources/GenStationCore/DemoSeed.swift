import Foundation
import ImageIO

/// Explicit imported-art fixtures. The schema has no provider job, cost, approval,
/// credential or lineage fields; fixture records cannot impersonate generation.
public struct DemoSeed: Decodable {
    public struct Asset: Decodable {
        public let id: UUID
        public let relativePath: String
        public let title: String
        public let provenance: String
        public let importedAt: Date
    }
    public let version: Int
    public let assets: [Asset]

    /// Uses the application's HistoryFile persistence format. Only an empty,
    /// marked demo workspace accepts a seed; no existing history is overwritten.
    public static func install(manifest: URL, context: StorageContext, lease: DemoWorkspaceLease) throws {
        guard context.isDemo, lease.context == context else { throw DemoWorkspaceLease.Failure.productionTarget }
        try lease.validateTree()
        let files = FileManager.default
        guard !files.fileExists(atPath: context.historyURL.path),
              files.fileExists(atPath: context.supportDirectory.appendingPathComponent(".genstation-demo-v1").path) else {
            throw AgentImageError("Seed requires an empty, initialized demo workspace. Reset it explicitly first.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let seed = try decoder.decode(Self.self, from: Data(contentsOf: manifest))
        guard seed.version == 1, !seed.assets.isEmpty, seed.assets.count <= 50,
              Set(seed.assets.map(\.id)).count == seed.assets.count else { throw AgentImageError("Seed version, asset count or IDs are invalid.") }
        let sourceRoot = manifest.deletingLastPathComponent().resolvingSymlinksInPath()
        var prepared: [(Asset, Data, String)] = []
        var totalBytes = 0
        for asset in seed.assets {
            let relative = asset.relativePath
            guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains(".."),
                  !asset.title.isEmpty, !asset.provenance.isEmpty else { throw AgentImageError("Seed needs relative media paths, titles and provenance.") }
            let source = sourceRoot.appendingPathComponent(relative).resolvingSymlinksInPath()
            guard source.path.hasPrefix(sourceRoot.path + "/"), ["png", "jpg", "jpeg"].contains(source.pathExtension.lowercased()) else { throw AgentImageError("Seed media escapes its directory or uses an unsupported format.") }
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 25 * 1024 * 1024 else { throw AgentImageError("Seed media is empty or larger than 25 MB: \(relative)") }
            totalBytes += size
            guard totalBytes <= 100 * 1024 * 1024 else { throw AgentImageError("Seed media exceeds the 100 MB batch limit.") }
            let bytes = try Data(contentsOf: source)
            guard let image = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 16_384, height <= 16_384,
                  width * height <= 40_000_000,
                  CGImageSourceCreateImageAtIndex(image, 0, nil) != nil else { throw AgentImageError("Seed media is not a readable image: \(relative)") }
            prepared.append((asset, bytes, source.pathExtension.lowercased()))
        }
        try files.createDirectory(at: context.outputDirectory, withIntermediateDirectories: true)
        var written: [URL] = []
        do {
            var entries: [HistoryEntry] = []
            for (asset, data, ext) in prepared {
                let target = context.outputDirectory.appendingPathComponent("imported-\(asset.id.uuidString).\(ext)")
                guard !files.fileExists(atPath: target.path) else { throw AgentImageError("Seed destination already exists.") }
                try data.write(to: target, options: .atomic)
                written.append(target)
                entries.append(.item(HistoryItem(id: asset.id, prompt: asset.title,
                    responseText: "Imported demo artwork. \(asset.provenance)", imagePath: target.path, date: asset.importedAt)))
            }
            try HistoryFile.encode(entries).write(to: context.historyURL, options: .atomic)
        } catch {
            for target in written { try? files.removeItem(at: target) }
            throw error
        }
    }
}
