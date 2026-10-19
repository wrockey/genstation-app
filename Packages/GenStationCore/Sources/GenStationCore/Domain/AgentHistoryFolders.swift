import Foundation

/// Folder metadata is visible under local Agent Access. Only individually
/// accessible item IDs can move; a folder never grants access to its contents.
public enum AgentHistoryFolders {
    public static func persist(_ entries: [HistoryEntry], to file: URL) throws {
        try HistoryFile.encode(entries).write(to: file, options: .atomic)
    }
    public static func folders(_ entries: [HistoryEntry], parent: UUID? = nil) -> [(Folder, UUID?)] {
        entries.flatMap { entry -> [(Folder, UUID?)] in
            guard case .folder(let folder) = entry else { return [] }
            return [(folder, parent)] + folders(folder.children, parent: folder.id)
        }
    }
    public static func name(_ value: String) throws -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 128,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw AgentImageError("Folder name must contain 1–128 display characters without control characters.") }
        return value
    }
    public static func create(_ entries: [HistoryEntry], id: UUID, name raw: String, parent: UUID?) throws -> [HistoryEntry] {
        let label = try name(raw)
        if let existing = folders(entries).first(where: { $0.0.id == id }) {
            guard existing.0.name == label, existing.1 == parent else { throw AgentImageError("folder_id already exists with different name or parent. Rediscover folders; do not overwrite it on retry.") }
            return entries
        }
        var allIDs = Set<UUID>()
        entries.forEach { $0.collectAllIDs(into: &allIDs) }
        guard !allIDs.contains(id), parent != id else { throw AgentImageError("Folder ID conflicts with existing History or invalid nesting.") }
        var result = entries
        try insert(.folder(Folder(id: id, name: label)), parent: parent, into: &result)
        return result
    }
    public static func rename(_ entries: [HistoryEntry], id: UUID, expectedName: String, newName: String) throws -> [HistoryEntry] {
        let label = try name(newName)
        _ = try name(expectedName)
        guard let folder = folders(entries).first(where: { $0.0.id == id })?.0 else { throw AgentImageError("Unknown folder_id.") }
        guard folder.name == label || folder.name == expectedName else { throw AgentImageError("Folder name changed. Rediscover before renaming.") }
        func walk(_ entries: [HistoryEntry]) -> [HistoryEntry] {
            entries.map { entry in
                guard case .folder(var folder) = entry else { return entry }
                if folder.id == id { folder.name = label }
                folder.children = walk(folder.children)
                return .folder(folder)
            }
        }
        return walk(entries)
    }
    public static func move(_ entries: [HistoryEntry], ids: [UUID], parent: UUID?, allowed: (UUID) -> Bool) throws -> [HistoryEntry] {
        guard !ids.isEmpty, ids.count <= 100, Set(ids).count == ids.count else { throw AgentImageError("Move 1–100 distinct accessible asset IDs.") }
        guard parent == nil || folders(entries).contains(where: { $0.0.id == parent }) else { throw AgentImageError("Unknown target folder_id.") }
        let allItems = entries.flatMap(\.allItems)
        guard ids.allSatisfy({ id in allowed(id) && allItems.contains(where: { $0.id == id }) }) else { throw AgentImageError("A selected asset is missing or inaccessible. Nothing moved.") }
        var currentParents: [UUID: UUID] = [:]
        func parents(_ entries: [HistoryEntry], parent: UUID?) {
            for entry in entries {
                switch entry {
                case .item(let item): currentParents[item.id] = parent
                case .folder(let folder): parents(folder.children, parent: folder.id)
                }
            }
        }
        parents(entries, parent: nil)
        let moving = ids.filter { currentParents[$0] != parent }
        if moving.isEmpty { return entries }
        let selected = Set(moving)
        func remove(_ entries: [HistoryEntry]) -> [HistoryEntry] {
            entries.compactMap { entry in
                switch entry {
                case .item(let item): return selected.contains(item.id) ? nil : entry
                case .folder(var folder): folder.children = remove(folder.children); return .folder(folder)
                }
            }
        }
        var result = remove(entries)
        for id in moving {
            guard let item = allItems.first(where: { $0.id == id }) else { throw AgentImageError("Asset disappeared.") }
            try insert(.item(item), parent: parent, into: &result)
        }
        return result
    }
    private static func insert(_ entry: HistoryEntry, parent: UUID?, into entries: inout [HistoryEntry]) throws {
        guard let parent else { entries.append(entry); return }
        func walk(_ entries: inout [HistoryEntry]) -> Bool {
            for index in entries.indices {
                guard case .folder(var folder) = entries[index] else { continue }
                if folder.id == parent { folder.children.append(entry); entries[index] = .folder(folder); return true }
                if walk(&folder.children) { entries[index] = .folder(folder); return true }
            }
            return false
        }
        guard walk(&entries) else { throw AgentImageError("Unknown parent folder_id.") }
    }
}
