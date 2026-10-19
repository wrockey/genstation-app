import Foundation
import CryptoKit

/// Represents a saved workflow with its configuration
public struct SavedWorkflow: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var workflowJSON: Data
    public var promptNodeID: String?
    public var outputNodeID: String?
    public var outputNodeIDs: [String]
    public var imageNodeIDs: [String]
    public var additionalInputs: [AdditionalInput]?
    public var lastUsed: Date
    public var dateAdded: Date
    public var revision: Int
    public var exposedInputVersion: Int
    public var exposedInputs: [WorkflowExposedInput]
    public var graphDigest: String { SHA256.hash(data: workflowJSON).map { String(format: "%02x", $0) }.joined() }

    public init(
        id: UUID = UUID(),
        name: String,
        workflowJSON: Data,
        promptNodeID: String? = nil,
        outputNodeID: String? = nil,
        imageNodeIDs: [String] = [],
        additionalInputs: [AdditionalInput]? = nil,
        lastUsed: Date = Date(),
        dateAdded: Date = Date(),
        revision: Int = 1,
        exposedInputVersion: Int = 1,
        exposedInputs: [WorkflowExposedInput] = [],
        outputNodeIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.workflowJSON = workflowJSON
        self.promptNodeID = promptNodeID
        self.outputNodeID = outputNodeID
        self.outputNodeIDs = outputNodeIDs
        self.imageNodeIDs = imageNodeIDs
        self.additionalInputs = additionalInputs
        self.lastUsed = lastUsed
        self.dateAdded = dateAdded
        self.revision = revision
        self.exposedInputVersion = exposedInputVersion
        self.exposedInputs = exposedInputs
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, workflowJSON, promptNodeID, outputNodeID, imageNodeIDs, additionalInputs, lastUsed, dateAdded, revision, exposedInputVersion, exposedInputs, outputNodeIDs
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        workflowJSON = try values.decode(Data.self, forKey: .workflowJSON)
        promptNodeID = try values.decodeIfPresent(String.self, forKey: .promptNodeID)
        outputNodeID = try values.decodeIfPresent(String.self, forKey: .outputNodeID)
        outputNodeIDs = try values.decodeIfPresent([String].self, forKey: .outputNodeIDs) ?? []
        imageNodeIDs = try values.decode([String].self, forKey: .imageNodeIDs)
        additionalInputs = try values.decodeIfPresent([AdditionalInput].self, forKey: .additionalInputs)
        lastUsed = try values.decode(Date.self, forKey: .lastUsed)
        dateAdded = try values.decode(Date.self, forKey: .dateAdded)
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        exposedInputVersion = try values.decodeIfPresent(Int.self, forKey: .exposedInputVersion) ?? 1
        guard exposedInputVersion == 1 else { throw AgentImageError("Unsupported exposed workflow input version; existing data was left untouched.") }
        exposedInputs = try values.decodeIfPresent([WorkflowExposedInput].self, forKey: .exposedInputs) ?? []
    }
}
