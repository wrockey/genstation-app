import Foundation
import CoreFoundation
import CryptoKit

/// Metadata for the durable local MCP authority only. Never populate with GUI history
/// or legacy session jobs. Caller identity is not established by the signed helper.
public struct AgentJobSummary: Sendable {
    public let id: String
    public let requestID: String
    public let kind: String
    public let createdAt: Date
    public let status: String
    public let billing: String
    public let pendingApproval: Bool
    public let recoveryAvailable: Bool
    public let label: String?

    public init(id: String, requestID: String, kind: String, createdAt: Date, status: String,
                billing: String, pendingApproval: Bool, recoveryAvailable: Bool, label: String?) {
        self.id = id; self.requestID = requestID; self.kind = kind; self.createdAt = createdAt
        self.status = status; self.billing = billing; self.pendingApproval = pendingApproval
        self.recoveryAvailable = recoveryAvailable; self.label = label
    }
    public var needsAttention: Bool {
        pendingApproval || billing == "billing_unresolved" || ["failed", "denied", "cancelled", "interrupted", "recoverable", "submission_unknown", "budget_exhausted", "billing_unresolved", "grant_revoked", "grant_expired", "storage_unavailable"].contains(status)
    }
    public func json(now: Date) -> [String: Any] {
        var result: [String: Any] = ["job_id": id, "request_id": requestID, "kind": kind,
            "created_at": ISO8601DateFormatter().string(from: createdAt), "age_seconds": Int(max(0, min(2_147_483_647, now.timeIntervalSince(createdAt)))),
            "status": status, "billing_status": billing, "approval_state": pendingApproval ? "pending" : (status == "awaiting_approval" ? "preparing_review" : "not_pending"),
            "needs_attention": needsAttention, "recovery_available": recoveryAvailable, "resubmit_safe": false]
        if let label { result["request_label"] = label }
        var tokenFields = result
        tokenFields.removeValue(forKey: "age_seconds")
        let data = (try? JSONSerialization.data(withJSONObject: tokenFields, options: [.sortedKeys])) ?? Data()
        result["state_token"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if pendingApproval { result["approval_guidance"] = "Open GenStation → Jobs → Pending Approvals and review this job ID. Closing review leaves it waiting while the app is open. Only the user can approve; keep polling the same job." }
        return result
    }
}

public enum AgentJobDiscovery {
    public static let kinds = ["image", "video", "saved_comfy_workflow"]
    public static func label(_ arguments: [String: Any]) throws -> String? {
        guard let raw = arguments["request_label"] else { return nil }
        guard let value = raw as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.count <= 128, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AgentImageError("request_label must contain 1–128 display characters without control characters. It grants no authority.")
        }
        return value
    }
    public static func lookup(_ params: [String: Any], jobs: [AgentJobSummary]) throws -> String {
        guard Set(params.keys).isSubset(of: ["job_id", "request_id", "kind"]) else { throw AgentImageError("Use job_id or exact request_id with optional kind.") }
        let jobID = try string(params, "job_id", max: 128)
        let requestID = try string(params, "request_id", max: 128)
        let kind = try string(params, "kind", max: 32)
        guard (jobID != nil) != (requestID != nil), kind == nil || kinds.contains(kind!) else { throw AgentImageError("Provide exactly one job_id or request_id, with a supported optional kind.") }
        let matches = jobs.filter {
            (kind == nil || $0.kind == kind) && (requestID != nil ? $0.requestID == requestID : $0.id.caseInsensitiveCompare(jobID!) == .orderedSame)
        }
        guard matches.count == 1, let job = matches.first else {
            throw AgentImageError(matches.isEmpty ? "No accessible durable job matches this identity. Do not submit again to look it up." : "Identity matches more than one job kind. Supply kind or use list_jobs to choose the existing job_id.")
        }
        return job.id
    }
    private struct Cursor: Codable {
        let version: Int
        let query: String
        let createdAt: Date
        let id: String
    }
    public static func list(_ arguments: [String: Any], jobs: [AgentJobSummary], now: Date = Date()) throws -> [String: Any] {
        guard Set(arguments.keys).isSubset(of: ["request_id", "kind", "filter", "limit", "cursor"]) else {
            throw AgentImageError("Use request_id, kind, filter, limit and cursor only.")
        }
        let requestID = try string(arguments, "request_id", max: 128)
        let kind = try string(arguments, "kind", max: 32)
        let filter = try string(arguments, "filter", max: 32) ?? "all"
        guard kind == nil || kinds.contains(kind!), ["all", "pending", "attention"].contains(filter) else { throw AgentImageError("Invalid job kind or filter. Use all, pending or attention.") }
        var limit = 25
        if let raw = arguments["limit"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                  (1...100).contains(number.doubleValue) else { throw AgentImageError("limit must be an integer from 1 to 100.") }
            limit = number.intValue
        }
        let query = String(data: try JSONSerialization.data(withJSONObject: ["request_id": requestID ?? "", "kind": kind ?? "", "filter": filter], options: [.sortedKeys]), encoding: .utf8)!
        var cursor: Cursor?
        if let raw = try string(arguments, "cursor", max: 2048) {
            guard let bytes = Data(base64Encoded: raw), let decoded = try? JSONDecoder().decode(Cursor.self, from: bytes),
                  decoded.version == 1, decoded.query == query, decoded.createdAt.timeIntervalSince1970.isFinite else {
                throw AgentImageError("Invalid cursor or changed query. Restart list_jobs with the intended filters.")
            }
            cursor = decoded
        }
        let matches = jobs.filter { job in
            (requestID == nil || job.requestID == requestID) && (kind == nil || job.kind == kind) &&
            (filter == "all" || (filter == "pending" ? job.pendingApproval : job.needsAttention)) &&
            (cursor == nil || job.createdAt < cursor!.createdAt || (job.createdAt == cursor!.createdAt && job.id < cursor!.id))
        }.sorted { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
        let page = Array(matches.prefix(limit))
        var result: [String: Any] = ["jobs": page.map { $0.json(now: now) }, "count": page.count,
            "scope": "local_mcp_jobs", "scope_description": "Durable jobs created through this app's local MCP access, shared across authorized local helpers. Not a per-bot identity or access to manual History jobs. Asset access is checked separately.",
            "pagination": "Newest first. Live state and access are rechecked per page; restart listing to catch newly created or newly pending jobs."]
        if matches.count > limit, let last = page.last {
            result["next_cursor"] = try JSONEncoder().encode(Cursor(version: 1, query: query, createdAt: last.createdAt, id: last.id)).base64EncodedString()
        }
        return result
    }
    public static func string(_ args: [String: Any], _ key: String, max: Int) throws -> String? {
        guard let raw = args[key] else { return nil }
        guard let value = raw as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= max else {
            throw AgentImageError("\(key) must be a nonempty string of at most \(max) characters.")
        }
        return value
    }
}
