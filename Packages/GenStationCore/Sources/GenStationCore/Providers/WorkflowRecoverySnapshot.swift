import Foundation
import CryptoKit

public struct WorkflowInputSnapshot: Codable, Equatable, Sendable {
    public let name: String
    public let assetID: UUID
    public let contentSHA256: String
    public var uploadedFileID: String?
    public init(name: String, assetID: UUID, contentSHA256: String) {
        self.name = name; self.assetID = assetID; self.contentSHA256 = contentSHA256
    }
}

public struct WorkflowOutputSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: String { descriptor.id }
    public let descriptor: ComfyUIOutput
    public let assetID: UUID
    public var localPath: String?
    public var usedFallback: Bool?
    public var mediaType: String?
    public var width: Int?
    public var height: Int?
    public var byteCount: Int?
    public var manifest: AgentAssetManifest?
    public var errorMessage: String?
    public init(descriptor: ComfyUIOutput, assetID: UUID = UUID()) {
        self.descriptor = descriptor; self.assetID = assetID
    }
}

/// Recovery needs the bound server, returned IDs and output descriptors, never
/// another copy of a graph that may contain node credentials or upload payloads.
public struct WorkflowRecoverySnapshot: Codable, Sendable {
    public static func digest(_ graph: [String: Any]) throws -> String {
        SHA256.hash(data: try JSONSerialization.data(withJSONObject: graph, options: .sortedKeys)).map { String(format: "%02x", $0) }.joined()
    }
    public let workflowID: UUID?
    public let workflowRevision: Int?
    public let graphDigest: String
    public let serverURL: String
    public let selectedOutputNodeID: String?
    public let workflowName: String
    public let displayPrompt: String
    public let assetID: UUID
    public var promptFingerprint: String?
    public var promptID: String?
    public var outputs: [ComfyUIOutput] = []
    public var localPath: String?
    public var usedFallback: Bool?
    public var submittedGraphDigest: String?
    public var inputAssets: [WorkflowInputSnapshot]?
    public var effectiveInputs: [String: WorkflowInputValue]?
    public var resultAssets: [WorkflowOutputSnapshot]?
    public var selectedOutputNodeIDs: [String]?
    public var isVideo = false

    public init(workflowID: UUID?, workflowRevision: Int?, graphDigest: String,
                serverURL: String, selectedOutputNodeID: String?, workflowName: String,
                displayPrompt: String, assetID: UUID = UUID()) {
        self.workflowID = workflowID; self.workflowRevision = workflowRevision
        self.graphDigest = graphDigest; self.serverURL = serverURL
        self.selectedOutputNodeID = selectedOutputNodeID; self.workflowName = workflowName
        self.displayPrompt = displayPrompt; self.assetID = assetID
    }

    public mutating func recordOutputs(_ descriptors: [ComfyUIOutput]) throws {
        guard !descriptors.isEmpty, descriptors.count <= 12,
              Set(descriptors.map(\.id)).count == descriptors.count else {
            throw AgentImageError("Select between one and twelve distinct workflow outputs.")
        }
        if let resultAssets {
            guard resultAssets.map(\.descriptor) == descriptors else { throw AgentImageError("Server output descriptors changed for the recorded job. Existing originals were retained.") }
            return
        }
        outputs = descriptors
        resultAssets = descriptors.enumerated().map { index, descriptor in
            WorkflowOutputSnapshot(descriptor: descriptor, assetID: index == 0 ? assetID : UUID())
        }
    }
}
