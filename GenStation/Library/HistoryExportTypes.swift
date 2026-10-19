// HistoryExportTypes.swift
import Foundation
import GenStationCore

// MARK: - Export Types – fully supports root-level items + backward compatibility
struct ExportContainer: Codable {
    // Old format (folder-only packages)
    let folders: [ExportFolder]?
    
    // New format – any mix of items/folders at root
    let rootEntries: [ExportEntry]?
    
    init(folders: [ExportFolder]) {
        self.folders = folders
        self.rootEntries = nil
    }
    
    init(rootEntries: [ExportEntry]) {
        self.folders = nil
        self.rootEntries = rootEntries
    }
    
    func toHistoryEntries() throws -> [HistoryEntry] {
        if let rootEntries = rootEntries {
            return try rootEntries.map { try $0.toHistoryEntry() }
        }
        // Old packages – safely unwrap
        return folders?.map { $0.toHistoryEntry() } ?? []
    }
}

// Thin wrapper so we can store items OR folders at the root level
struct ExportEntry: Codable {
    let isFolder: Bool
    let folder: ExportFolder?
    let item: HistoryItem?
    
    init(from entry: HistoryEntry, itemsCollector: inout [HistoryItem]) {
        switch entry {
        case .folder(let f):
            isFolder = true
            folder = ExportFolder(from: f, itemsCollector: &itemsCollector)
            item = nil
        case .item(let i):
            isFolder = false
            folder = nil
            
            // Export only filename (import will fix paths)
            var exportItem = i
            if let fullPath = i.imagePath {
                exportItem.imagePath = URL(fileURLWithPath: fullPath).lastPathComponent
            }
            item = exportItem
            
            // Collector gets the ORIGINAL item with full path for copying
            itemsCollector.append(i)
        }
    }
    
    func toHistoryEntry() throws -> HistoryEntry {
        if isFolder, let f = folder {
            return .folder(f.toFolder())
        } else if let i = item {
            return .item(i)
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Corrupted ExportEntry: neither folder nor item"))
    }
}

// Existing ExportFolder – only tiny fixes + the missing methods
struct ExportFolder: Codable {
    let id: UUID
    let name: String
    let children: [ExportFolder]
    let items: [HistoryItem]
    
    // MARK: Export from real Folder
    init(from folder: Folder, itemsCollector: inout [HistoryItem]) {
        self.id = folder.id
        self.name = folder.name
        
        var subfolders: [ExportFolder] = []
        var localItems: [HistoryItem] = []
        
        for child in folder.children {
            switch child {
            case .folder(let subFolder):
                subfolders.append(ExportFolder(from: subFolder, itemsCollector: &itemsCollector))
            case .item(let originalItem):
                var exportItem = originalItem
                if let fullPath = originalItem.imagePath {   // ← fixed typo “ordination”
                    exportItem.imagePath = URL(fileURLWithPath: fullPath).lastPathComponent
                }
                itemsCollector.append(originalItem)          // original for copying
                localItems.append(exportItem)
            }
        }
        
        self.children = subfolders
        self.items = localItems
    }
    
    // MARK: Import (supports old packages without id)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.children = try container.decode([ExportFolder].self, forKey: .children)
        self.items = try container.decode([HistoryItem].self, forKey: .items)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, children, items
    }
    
    func toHistoryEntry() -> HistoryEntry {
        let childFolders: [HistoryEntry] = children.map { $0.toHistoryEntry() }
        let childEntries: [HistoryEntry] = childFolders + items.map { .item($0) }
        return .folder(Folder(id: id, name: name, children: childEntries))
    }
    
    // The method used by ExportEntry
    func toFolder() -> Folder {
        let childEntries: [HistoryEntry] = children.map { .folder($0.toFolder()) } + items.map { .item($0) }
        return Folder(id: id, name: name, children: childEntries)
    }
}
