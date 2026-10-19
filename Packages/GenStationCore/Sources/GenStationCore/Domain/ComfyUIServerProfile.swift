import Foundation

/// Non-secret server identity. Credentials belong in the app's scoped Keychain,
/// never in this persisted record. Jobs retain their own endpoint snapshot.
public struct ComfyUIServerProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public private(set) var name: String
    public private(set) var baseURL: String
    public private(set) var revision: Int

    public init(id: UUID = UUID(), name: String, baseURL: String, revision: Int = 1) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw AgentImageError("Enter a server name of up to 120 characters.")
        }
        let normalized = ComfyUIEndpoints.normalizedServerURL(baseURL)
        guard normalized.count <= 2048, ComfyUIEndpoints.objectInfoURL(serverURL: normalized) != nil,
              !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains), revision > 0 else {
            throw AgentImageError("Enter an HTTP or HTTPS server address without credentials, a query or a fragment.")
        }
        self.id = id
        self.name = name
        self.baseURL = normalized
        self.revision = revision
    }

    /// Different profiles sharing an endpoint still have separate inventories.
    /// An edit invalidates compatibility observations made against the old revision.
    public var inventoryKey: String { "\(id.uuidString.lowercased())-\(revision)" }

    private enum CodingKeys: String, CodingKey { case id, name, baseURL, revision }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id),
                      name: values.decode(String.self, forKey: .name),
                      baseURL: values.decode(String.self, forKey: .baseURL),
                      revision: values.decode(Int.self, forKey: .revision))
    }
}
