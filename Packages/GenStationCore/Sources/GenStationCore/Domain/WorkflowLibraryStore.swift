import Foundation

/// Durable identity is the UUID; names are editable labels. Failed writes leave
/// the in-memory snapshot unchanged. Legacy defaults are retained after migration.
public struct WorkflowLibraryStore {
    private struct Envelope: Codable {
        var schemaVersion = 2
        var workflows: [SavedWorkflow]
    }
    public let fileURL: URL
    public private(set) var workflows: [SavedWorkflow]

    public init(fileURL: URL, legacyData: Data? = nil) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let decoded = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
            guard [1, 2].contains(decoded.schemaVersion) else { throw AgentImageError("Unsupported workflow library version. The file was left untouched.") }
            workflows = decoded.workflows
        } else if let legacyData {
            workflows = try JSONDecoder().decode([SavedWorkflow].self, from: legacyData)
            guard Set(workflows.map(\.id)).count == workflows.count else { throw AgentImageError("Legacy workflow library contains duplicate IDs. It was left untouched.") }
            try Self.write(workflows, to: fileURL)
        } else {
            workflows = []
        }
        guard Set(workflows.map(\.id)).count == workflows.count else { throw AgentImageError("Workflow library contains duplicate IDs. Repair it before saving.") }
    }

    public var sortedWorkflows: [SavedWorkflow] {
        workflows.sorted { $0.lastUsed == $1.lastUsed ? $0.id.uuidString < $1.id.uuidString : $0.lastUsed > $1.lastUsed }
    }
    public var recentWorkflows: [SavedWorkflow] { Array(sortedWorkflows.prefix(10)) }

    public mutating func save(_ workflow: SavedWorkflow, replacingID: UUID? = nil) throws -> SavedWorkflow {
        guard !workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentImageError("Enter a workflow name.") }
        var next = workflows
        var saved = workflow
        if let replacingID {
            guard let index = next.firstIndex(where: { $0.id == replacingID }) else { throw AgentImageError("Saved workflow no longer exists. Save a new copy explicitly.") }
            let old = next[index]
            saved = SavedWorkflow(id: old.id, name: workflow.name, workflowJSON: workflow.workflowJSON,
                promptNodeID: workflow.promptNodeID, outputNodeID: workflow.outputNodeID,
                imageNodeIDs: workflow.imageNodeIDs, additionalInputs: workflow.additionalInputs,
                lastUsed: workflow.lastUsed, dateAdded: old.dateAdded, revision: old.revision + 1,
                exposedInputVersion: workflow.exposedInputVersion, exposedInputs: workflow.exposedInputs, outputNodeIDs: workflow.outputNodeIDs)
            next[index] = saved
        } else {
            guard !next.contains(where: { $0.id == workflow.id }) else { throw AgentImageError("Workflow ID already exists; choose an explicit update.") }
            next.append(saved)
        }
        try commit(next)
        return saved
    }

    public mutating func rename(id: UUID, to name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentImageError("Enter a workflow name.") }
        var next = workflows
        guard let index = next.firstIndex(where: { $0.id == id }) else { throw AgentImageError("Workflow no longer exists.") }
        next[index].name = name
        try commit(next)
    }
    public mutating func markUsed(id: UUID, now: Date = Date()) throws {
        var next = workflows
        guard let index = next.firstIndex(where: { $0.id == id }) else { throw AgentImageError("Workflow no longer exists.") }
        next[index].lastUsed = now
        try commit(next)
    }
    public mutating func delete(id: UUID) throws {
        try commit(workflows.filter { $0.id != id })
    }
    private mutating func commit(_ next: [SavedWorkflow]) throws {
        try Self.write(next, to: fileURL)
        workflows = next
    }
    private static func write(_ workflows: [SavedWorkflow], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Envelope(workflows: workflows))
        try data.write(to: url, options: .atomic)
        guard try Data(contentsOf: url) == data else { throw AgentImageError("Workflow library verification failed. Legacy data was retained.") }
    }
}
