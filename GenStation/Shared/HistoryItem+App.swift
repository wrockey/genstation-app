// HistoryItem+App.swift
//
// The one member of HistoryItem that cannot live in GenStationCore: it needs AppState to
// resolve the security-scoped output directory before touching the filesystem.
import Foundation
import GenStationCore

extension HistoryItem {
    var hasVideoContent: Bool {
        task == .video || videoUrl != nil || imagePath.map {
            ["mp4", "m4v", "mov", "webm"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
        } == true
    }

    func fileExists(appState: AppState) -> Bool {
        guard let path = imagePath else {
            return false
        }
        let directory = appState.settings.outputDirectory
        let didStart = directory?.startAccessingSecurityScopedResource() ?? false
        defer { if didStart { directory?.stopAccessingSecurityScopedResource() } }
        // App-owned Documents needs no security scope. A false start result alone
        // does not mean the file is unavailable.
        return FileManager.default.fileExists(atPath: path)
    }
}


extension HistoryState {
    /// Updates nested library items as well as top-level entries, preserving folder placement.
    func updateItem(id: UUID, _ mutate: (inout HistoryItem) -> Void) {
        func update(_ entries: inout [HistoryEntry]) -> Bool {
            for index in entries.indices {
                switch entries[index] {
                case .item(var item) where item.id == id:
                    mutate(&item)
                    entries[index] = .item(item)
                    return true
                case .folder(var folder):
                    if update(&folder.children) {
                        entries[index] = .folder(folder)
                        return true
                    }
                default: break
                }
            }
            return false
        }
        var snapshot = history
        if update(&snapshot) { history = snapshot }
    }
}
