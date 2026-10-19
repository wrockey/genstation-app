import Foundation
import CryptoKit

public struct AgentImageJob: Codable, Sendable {
    public let id: String
    public let requestID: String
    public let fingerprint: String
    public var status = "awaiting_approval"
    public var billing = "not_submitted"
    public var message: String?
    public var filterReasons: [PromptSafetyPolicy.FilterReason]?
    public var errorCode: String?
    public var assetIDs: [UUID] = []
    public var requiresManifest: Bool?
    public var manifests: [AgentAssetManifest]?
    public var costUSD: Double?
    public var budgetGrantID: String?
    public var chargeEvidence: ProviderChargeEvidence?
    public var billingEvidenceIssue: String?
    public var requestLabel: String?
    public var createdAt = Date()
    public var workflow: WorkflowRecoverySnapshot?
}

/// Request identities survive reconnects and process death. Writes must succeed before POST.
/// Payloads and credentials are never persisted here. Unknown submissions are never replayed.
public struct AgentImageLedger: Codable, Sendable {
    public private(set) var jobs: [String: AgentImageJob] = [:]
    public init() {}

    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        var ledger = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        for (id, var job) in ledger.jobs where job.status == "uploading" {
            job.status = "failed"; job.billing = "not_submitted"
            job.message = "Input upload was interrupted before workflow submission. Uploaded files may remain on the server. Validate and approve a new request to run."
            ledger.jobs[id] = job
        }
        for (id, var job) in ledger.jobs where job.workflow != nil && ["submitting", "queued", "downloading", "saving", "recovering"].contains(job.status) {
            job.status = job.workflow?.promptID == nil ? "submission_unknown" : "recoverable"
            job.message = job.workflow?.promptID == nil
                ? "Submission outcome is unknown. Do not automatically resubmit."
                : "Known ComfyUI job can be recovered with GET requests. Generation will not be resubmitted."
            ledger.jobs[id] = job
        }
        for (id, var job) in ledger.jobs where ["awaiting_approval", "budget_queued", "budget_exhausted", "billing_unresolved", "grant_revoked", "grant_expired", "storage_unavailable", "submitting", "saving"].contains(job.status) {
            job.status = "interrupted"
            job.message = "Interrupted. This request will not be submitted again. Check the app library and provider billing before making a new request."
            ledger.jobs[id] = job
        }
        return ledger
    }

    public func existing(requestID: String, arguments: [String: Any]) throws -> AgentImageJob? {
        guard let job = jobs.values.first(where: { $0.requestID == requestID }) else { return nil }
        guard job.fingerprint == (try Self.fingerprint(arguments)) else {
            throw AgentImageError("request_id already exists with different arguments; use its existing job or a new ID for a new paid request.")
        }
        return job
    }

    public mutating func register(requestID: String, arguments: [String: Any], at url: URL) throws -> AgentImageJob {
        guard !requestID.isEmpty, requestID.count <= 128 else { throw AgentImageError("request_id must contain 1–128 characters.") }
        if let job = try existing(requestID: requestID, arguments: arguments) { return job }
        var job = AgentImageJob(id: UUID().uuidString, requestID: requestID, fingerprint: try Self.fingerprint(arguments))
        job.requestLabel = try AgentJobDiscovery.label(arguments)
        try update(job, at: url)
        return job
    }

    public mutating func update(_ job: AgentImageJob, at url: URL) throws {
        var next = self
        next.jobs[job.id] = job
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        self = next
    }

    private static func fingerprint(_ arguments: [String: Any]) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

public struct AgentImageError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}
