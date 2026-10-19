import Foundation

public struct HistoryItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public let prompt: String
    public var responseText: String
    public var imagePath: String?
    public let date: Date
    public let mode: Provider?
    /// What this record was making. `nil` on every record written before this field existed,
    /// and on paths where the task is only inferable — consumers must keep tolerating nil.
    public var task: CreateTask?
    public let workflowName: String?
    public let modelUsed: String?
    public let batchId: UUID?
    public let indexInBatch: Int?
    public let totalInBatch: Int?
    public let jobId: String?
    /// Typed lifecycle status. `nil` means "not a polled job" — which is most images.
    public var status: GenerationStatus?
    public var sourceAssetURL: String?
    public var videoUrl: String?
    public var videoHasAudio: Bool?  // Whether the video contains audio tracks
    // New fields for AIML mode
    public var pollingEndpoint: String? // Store the polling URL base for video job resume
    public var customAIMLPayload: String? // Store the JSON payload used
    public var customAIMLEndpoint: String? // Store the endpoint used
    public var parentAssetIDs: [UUID]?
    public var workflowInputs: [String: WorkflowInputValue]?
    public var sourceWorkflowID: UUID?
    public var sourceWorkflowRevision: Int?
    public var parentItemId: UUID? // ID of parent item (e.g., original image before upscaling)
    public var costUSD: Double? // Actual USD cost for this generation, captured from the API response
    // True when the generation was requested by an agent through the MCP server (WS-7).
    // Optional + encodeIfPresent/decodeIfPresent so old history files round-trip unchanged.
    public var agentGenerated: Bool?

    public init(
        id: UUID = UUID(),
        prompt: String,
        responseText: String = "",
        imagePath: String? = nil,
        date: Date,
        mode: Provider? = nil,
        task: CreateTask? = nil,
        workflowName: String? = nil,
        modelUsed: String? = nil,
        batchId: UUID? = nil,
        indexInBatch: Int? = nil,
        totalInBatch: Int? = nil,
        jobId: String? = nil,
        status: GenerationStatus? = nil,
        sourceAssetURL: String? = nil,
        videoUrl: String? = nil,
        videoHasAudio: Bool? = nil,
        pollingEndpoint: String? = nil,
        customAIMLPayload: String? = nil,
        customAIMLEndpoint: String? = nil,
        parentItemId: UUID? = nil,
        costUSD: Double? = nil,
        agentGenerated: Bool? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.responseText = responseText
        self.imagePath = imagePath
        self.date = date
        self.mode = mode
        self.task = task
        self.workflowName = workflowName
        self.modelUsed = modelUsed
        self.batchId = batchId
        self.indexInBatch = indexInBatch
        self.totalInBatch = totalInBatch
        self.jobId = jobId
        self.status = status
        self.sourceAssetURL = sourceAssetURL
        self.videoUrl = videoUrl
        self.videoHasAudio = videoHasAudio
        self.pollingEndpoint = pollingEndpoint
        self.customAIMLPayload = customAIMLPayload
        self.customAIMLEndpoint = customAIMLEndpoint
        self.parentItemId = parentItemId
        self.parentAssetIDs = nil
        self.workflowInputs = nil
        self.sourceWorkflowID = nil
        self.sourceWorkflowRevision = nil
        self.costUSD = costUSD
        self.agentGenerated = agentGenerated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.prompt = try container.decode(String.self, forKey: .prompt)
        self.responseText = try container.decode(String.self, forKey: .responseText)
        self.imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        self.date = try container.decode(Date.self, forKey: .date)
        // decodeIfPresent(Provider.self) *throws* on an unrecognized raw — it maps only
        // null/absent to nil. Decoding the raw string first means an unrecognized provider
        // *string* no longer throws, so a record written by a newer build (or carrying a
        // since-removed provider) stays readable, minus its provider attribution. A
        // wrong-typed `mode` (a number, an object) still throws typeMismatch, but
        // LossyArray contains that to the one record instead of the whole file.
        self.mode = try container.decodeIfPresent(String.self, forKey: .mode)
            .flatMap(Provider.init(rawValue:))
        // Same lenient shape as `mode`: a `.threeD` (or any later case) written by a newer
        // build must not throw here and take the whole record down with it.
        self.task = try container.decodeIfPresent(String.self, forKey: .task)
            .flatMap(CreateTask.init(rawValue:))
        self.workflowName = try container.decodeIfPresent(String.self, forKey: .workflowName)
        self.modelUsed = try container.decodeIfPresent(String.self, forKey: .modelUsed)
        self.batchId = try container.decodeIfPresent(UUID.self, forKey: .batchId)
        self.indexInBatch = try container.decodeIfPresent(Int.self, forKey: .indexInBatch)
        self.totalInBatch = try container.decodeIfPresent(Int.self, forKey: .totalInBatch)
        self.jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
        self.status = try container.decodeIfPresent(GenerationStatus.self, forKey: .status)
        self.sourceAssetURL = try container.decodeIfPresent(String.self, forKey: .sourceAssetURL)
        self.videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl)
        self.videoHasAudio = try container.decodeIfPresent(Bool.self, forKey: .videoHasAudio)
        self.pollingEndpoint = try container.decodeIfPresent(String.self, forKey: .pollingEndpoint)
        self.customAIMLPayload = try container.decodeIfPresent(String.self, forKey: .customAIMLPayload)
        self.customAIMLEndpoint = try container.decodeIfPresent(String.self, forKey: .customAIMLEndpoint)
        self.parentItemId = try container.decodeIfPresent(UUID.self, forKey: .parentItemId)
        self.parentAssetIDs = try container.decodeIfPresent([UUID].self, forKey: .parentAssetIDs)
        self.workflowInputs = try container.decodeIfPresent([String: WorkflowInputValue].self, forKey: .workflowInputs)
        self.sourceWorkflowID = try container.decodeIfPresent(UUID.self, forKey: .sourceWorkflowID)
        self.sourceWorkflowRevision = try container.decodeIfPresent(Int.self, forKey: .sourceWorkflowRevision)
        self.costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
        self.agentGenerated = try container.decodeIfPresent(Bool.self, forKey: .agentGenerated)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(responseText, forKey: .responseText)
        try container.encodeIfPresent(imagePath, forKey: .imagePath)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(task, forKey: .task)
        try container.encodeIfPresent(workflowName, forKey: .workflowName)
        try container.encodeIfPresent(modelUsed, forKey: .modelUsed)
        try container.encodeIfPresent(batchId, forKey: .batchId)
        try container.encodeIfPresent(indexInBatch, forKey: .indexInBatch)
        try container.encodeIfPresent(totalInBatch, forKey: .totalInBatch)
        try container.encodeIfPresent(jobId, forKey: .jobId)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(sourceAssetURL, forKey: .sourceAssetURL)
        try container.encodeIfPresent(videoUrl, forKey: .videoUrl)
        try container.encodeIfPresent(videoHasAudio, forKey: .videoHasAudio)
        try container.encodeIfPresent(pollingEndpoint, forKey: .pollingEndpoint)
        try container.encodeIfPresent(customAIMLPayload, forKey: .customAIMLPayload)
        try container.encodeIfPresent(customAIMLEndpoint, forKey: .customAIMLEndpoint)
        try container.encodeIfPresent(parentItemId, forKey: .parentItemId)
        try container.encodeIfPresent(parentAssetIDs, forKey: .parentAssetIDs)
        try container.encodeIfPresent(workflowInputs, forKey: .workflowInputs)
        try container.encodeIfPresent(sourceWorkflowID, forKey: .sourceWorkflowID)
        try container.encodeIfPresent(sourceWorkflowRevision, forKey: .sourceWorkflowRevision)
        try container.encodeIfPresent(costUSD, forKey: .costUSD)
        try container.encodeIfPresent(agentGenerated, forKey: .agentGenerated)
    }

    enum CodingKeys: String, CodingKey {
        case id, prompt, responseText, imagePath, date, mode, task, workflowName, modelUsed
        case batchId, indexInBatch, totalInBatch, jobId, status, videoUrl, videoHasAudio
        case pollingEndpoint, customAIMLPayload, customAIMLEndpoint, parentItemId, costUSD, parentAssetIDs, sourceWorkflowID, sourceWorkflowRevision, workflowInputs
        case agentGenerated, sourceAssetURL
    }
}

public enum HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    case item(HistoryItem)
    case folder(Folder)

    public var childrenForOutline: [HistoryEntry]? {
        if case .folder(let folder) = self {
            return folder.children
        }
        return nil
    }

    public var id: UUID {
        switch self {
        case .item(let item): return item.id
        case .folder(let folder): return folder.id
        }
    }

    public func collectAllIDs(into set: inout Set<UUID>) {
        set.insert(id)
        if case .folder(let folder) = self {
            for child in folder.children {
                child.collectAllIDs(into: &set)
            }
        }
    }

    public var imageCount: Int {
        switch self {
        case .item:
            return 1
        case .folder(let folder):
            return folder.children.reduce(0) { $0 + $1.imageCount }
        }
    }

    public var allItems: [HistoryItem] {
        switch self {
        case .item(let item):
            return [item]
        case .folder(let folder):
            return folder.children.flatMap { $0.allItems }
        }
    }

    public static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        switch (lhs, rhs) {
        case (.item(let a), .item(let b)):
            return a == b
        case (.folder(let a), .folder(let b)):
            return a == b
        default:
            return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, content
    }

    private enum EntryType: String, Codable {
        case item, folder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EntryType.self, forKey: .type)
        switch type {
        case .item:
            let item = try container.decode(HistoryItem.self, forKey: .content)
            self = .item(item)
        case .folder:
            let folder = try container.decode(Folder.self, forKey: .content)
            self = .folder(folder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .item(let item):
            try container.encode(EntryType.item, forKey: .type)
            try container.encode(item, forKey: .content)
        case .folder(let folder):
            try container.encode(EntryType.folder, forKey: .type)
            try container.encode(folder, forKey: .content)
        }
    }
    public var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    public var isItem: Bool {
        if case .item = self { return true }
        return false
    }

    // Bonus – super useful for later
    public var asFolder: Folder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }

    public var asItem: HistoryItem? {
        if case .item(let item) = self { return item }
        return nil
    }


}
public struct Folder: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID            // ← Change from let to var
    public var name: String
    public var children: [HistoryEntry]

    public init(id: UUID = UUID(), name: String = "New Folder", children: [HistoryEntry] = []) {
        self.id = id
        self.name = name
        self.children = children
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        // `children` must stay the last member decoded here. The dropped-child count below
        // is only correct because nothing after it can throw: if a later decode threw, this
        // entire folder would be dropped by the parent LossyArray (+1 there) while the
        // increment from `lossyChildren.failureCount` already landed on the shared counter —
        // double-counting the dropped children on top of the dropped folder. Add any future
        // field before `children`, not after.
        //
        // One corrupt child must not take the folder — and with it every sibling — down.
        let lossyChildren = try container.decode(HistoryFile.LossyArray<HistoryEntry>.self, forKey: .children)
        self.children = lossyChildren.elements
        // Report upwards, or a child dropped in here would never reach the caller's
        // `droppedRecordCount` and would disappear with no count and no log at all.
        (decoder.userInfo[.droppedRecordCounter] as? DroppedRecordCounter)?
            .add(lossyChildren.failureCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(children, forKey: .children)
    }

    enum CodingKeys: CodingKey {
        case id, name, children
    }

    public static func == (lhs: Folder, rhs: Folder) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.children == rhs.children
    }
}
