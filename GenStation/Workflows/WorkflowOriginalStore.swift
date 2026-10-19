import Foundation
import GenStationCore

enum WorkflowOriginalStore {
    @MainActor static func save(_ data: Data, assetID: UUID, filename: String, app: AppState) throws -> (path: String, usedFallback: Bool) {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "gif", "webp", "mp4", "m4v", "mov", "webm"].contains(ext) else {
            throw AgentImageError("Unsupported workflow original format.")
        }
        let configured = app.settings.outputDirectory
        let scoped = !AppStorageContext.current.isDemo && (configured?.startAccessingSecurityScopedResource() ?? false)
        defer { if scoped { configured?.stopAccessingSecurityScopedResource() } }
        let fallback = !AppStorageContext.current.isDemo && configured != nil && !scoped
        let selectedDirectory: URL? = AppStorageContext.current.isDemo ? AppStorageContext.current.outputDirectory :
            (scoped ? configured! : AppStorageContext.fallbackOutputDirectory)
        guard let directory = selectedDirectory, AppStorageContext.permitsOriginal(directory) else { throw AgentImageError("Workflow output directory is unavailable.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(assetID.uuidString + "." + ext)
        try data.write(to: destination, options: .atomic)
        return (destination.path, fallback)
    }
}
