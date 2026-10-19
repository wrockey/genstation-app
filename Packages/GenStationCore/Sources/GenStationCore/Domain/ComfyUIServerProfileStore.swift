import Foundation

/// Atomic profile storage. Reading an invalid/newer file never overwrites it.
/// The caller supplies the old single URL once; its defaults entry is retained.
public struct ComfyUIServerProfileStore {
    private struct Envelope: Codable {
        var schemaVersion = 1
        var profiles: [ComfyUIServerProfile]
        var selectedID: UUID?
    }
    public let fileURL: URL
    public private(set) var profiles: [ComfyUIServerProfile]
    public private(set) var selectedID: UUID?
    public var selected: ComfyUIServerProfile? { profiles.first { $0.id == selectedID } }

    public init(fileURL: URL, legacyServerURL: String? = nil) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let decoded = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
            guard decoded.schemaVersion == 1 else {
                throw AgentImageError("Unsupported server profile version. Existing settings were left untouched.")
            }
            try Self.validate(decoded.profiles, selectedID: decoded.selectedID)
            profiles = decoded.profiles
            selectedID = decoded.selectedID
        } else if let legacyServerURL {
            let profile = try ComfyUIServerProfile(name: "My ComfyUI server", baseURL: legacyServerURL)
            try Self.write([profile], selectedID: profile.id, to: fileURL)
            profiles = [profile]
            selectedID = profile.id
        } else {
            profiles = []
            selectedID = nil
        }
    }

    @discardableResult
    public mutating func save(_ profile: ComfyUIServerProfile, replacingID: UUID? = nil) throws -> ComfyUIServerProfile {
        var next = profiles
        let saved: ComfyUIServerProfile
        if let replacingID {
            guard let index = next.firstIndex(where: { $0.id == replacingID }), next[index].revision < Int.max else {
                throw AgentImageError("Server profile cannot be updated. Add a new profile explicitly.")
            }
            saved = try ComfyUIServerProfile(id: replacingID, name: profile.name, baseURL: profile.baseURL, revision: next[index].revision + 1)
            next[index] = saved
        } else {
            guard !next.contains(where: { $0.id == profile.id }) else {
                throw AgentImageError("Server profile already exists. Choose an explicit update.")
            }
            saved = profile
            next.append(saved)
        }
        try commit(next, selectedID: selectedID ?? saved.id)
        return saved
    }

    public mutating func select(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { throw AgentImageError("Server profile no longer exists.") }
        try commit(profiles, selectedID: id)
    }

    /// Deleting the selected profile leaves no selection; it never silently
    /// redirects a draft or a recoverable job to a different server.
    public mutating func delete(id: UUID) throws {
        try commit(profiles.filter { $0.id != id }, selectedID: selectedID == id ? nil : selectedID)
    }

    private mutating func commit(_ next: [ComfyUIServerProfile], selectedID: UUID?) throws {
        try Self.write(next, selectedID: selectedID, to: fileURL)
        profiles = next
        self.selectedID = selectedID
    }
    private static func validate(_ profiles: [ComfyUIServerProfile], selectedID: UUID?) throws {
        guard Set(profiles.map(\.id)).count == profiles.count,
              selectedID == nil || profiles.contains(where: { $0.id == selectedID }) else {
            throw AgentImageError("Server profiles contain duplicate or missing identities. Existing settings were left untouched.")
        }
    }
    private static func write(_ profiles: [ComfyUIServerProfile], selectedID: UUID?, to url: URL) throws {
        try validate(profiles, selectedID: selectedID)
        let data = try JSONEncoder().encode(Envelope(profiles: profiles, selectedID: selectedID))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
