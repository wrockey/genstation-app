import Foundation
import CryptoKit

public struct AgentVideoJob: Codable, Sendable {
    public let id: String
    public let requestID: String
    public let fingerprint: String
    public var status = "awaiting_approval"
    public var billing = "not_submitted"
    public var message: String?
    public var filterReasons: [PromptSafetyPolicy.FilterReason]?
    public var errorCode: String?
    /// Recovery snapshot: provider ID, endpoint, original history identity and output URL.
    /// Never contains API keys or image payloads.
    public var history: HistoryItem?
    public var historyLinked = false
    public var manifest: AgentAssetManifest?
    public var requestLabel: String?
    public var createdAt = Date()
}

public struct AgentVideoLedger: Codable, Sendable {
    public private(set) var jobs: [String: AgentVideoJob] = [:]
    public init() {}
    public static func load(from file: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: file.path) else { return Self() }
        var value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
        for (key, var job) in value.jobs {
            if job.status == "submitting", job.history?.jobId == nil {
                job.status = "submission_unknown"
                job.message = "The submission may have reached the provider, but its job ID was not recorded. Do not automatically resubmit."
            } else if ["awaiting_approval", "preparing"].contains(job.status) {
                job.status = "interrupted"
                job.message = "Interrupted before generation submission. No automatic resubmission; a new request needs new approval."
            } else if ["polling", "saving"].contains(job.status), job.history?.jobId != nil {
                job.status = "recoverable"
                job.message = "Known provider job can be recovered with GET requests; generation will not be resubmitted."
            }
            value.jobs[key] = job
        }
        return value
    }
    public func existing(requestID: String, arguments: [String: Any]) throws -> AgentVideoJob? {
        guard let existing = jobs.values.first(where: { $0.requestID == requestID }) else { return nil }
        guard existing.fingerprint == (try Self.fingerprint(arguments)) else { throw AgentImageError("request_id already exists with different video arguments. Retrieve the existing job; a new ID creates a new potentially billable request.") }
        return existing
    }
    public mutating func register(requestID: String, arguments: [String: Any], at file: URL) throws -> AgentVideoJob {
        guard !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, requestID.count <= 128 else { throw AgentImageError("request_id must contain 1–128 characters.") }
        if let existing = try existing(requestID: requestID, arguments: arguments) { return existing }
        var job = AgentVideoJob(id: UUID().uuidString, requestID: requestID, fingerprint: try Self.fingerprint(arguments))
        job.requestLabel = try AgentJobDiscovery.label(arguments)
        try update(job, at: file)
        return job
    }
    public mutating func update(_ job: AgentVideoJob, at file: URL) throws {
        var snapshot = self
        var sanitized = job
        sanitized.history?.customAIMLPayload = nil
        sanitized.history?.customAIMLEndpoint = nil
        snapshot.jobs[job.id] = sanitized
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        self = snapshot
    }
    private static func fingerprint(_ arguments: [String: Any]) throws -> String {
        SHA256.hash(data: try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])).map { String(format: "%02x", $0) }.joined()
    }
}
