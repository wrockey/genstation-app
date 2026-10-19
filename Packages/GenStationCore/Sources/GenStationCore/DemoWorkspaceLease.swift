import Foundation
import Darwin

/// Holds exclusive ownership for the entire app lifetime. Reset tooling must use
/// this same lock outside the resettable directory, never unlink the lock file.
public final class DemoWorkspaceLease {
    private let descriptor: Int32
    public let context: StorageContext
    public enum Failure: Error { case productionTarget, unsafePath, alreadyInUse, unavailable, unknownWorkspace, unresolvedJobs }

    public init(context: StorageContext) throws {
        guard context.isDemo, context.bundleID == StorageContext.demoID else { throw Failure.productionTarget }
        let root = context.supportDirectory
        let parent = root.deletingLastPathComponent().resolvingSymlinksInPath()
        let expected = parent.appendingPathComponent(StorageContext.demoID, isDirectory: true)
        guard root.resolvingSymlinksInPath().standardizedFileURL.path == expected.standardizedFileURL.path else { throw Failure.unsafePath }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let lock = parent.appendingPathComponent(".genstation-demo.lock")
        let fd = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure.unavailable }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw Failure.alreadyInUse
        }
        descriptor = fd
        self.context = context
    }

    public func validateTree() throws {
        let root = context.supportDirectory
        guard !((try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false) else { throw Failure.unsafePath }
        if let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let entry as URL in entries {
                if try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw Failure.unsafePath }
            }
        }
    }

    private var marker: URL { context.supportDirectory.appendingPathComponent(".genstation-demo-v1") }
    private let markerData = Data("GenStation isolated demo workspace v1\n".utf8)

    public func prepare() throws {
        try validateTree()
        let files = FileManager.default
        if files.fileExists(atPath: marker.path) {
            guard try Data(contentsOf: marker) == markerData else { throw Failure.unknownWorkspace }
            return
        }
        if files.fileExists(atPath: context.supportDirectory.path) {
            guard try files.contentsOfDirectory(atPath: context.supportDirectory.path).isEmpty else { throw Failure.unknownWorkspace }
        } else {
            try files.createDirectory(at: context.supportDirectory, withIntermediateDirectories: true)
        }
        try markerData.write(to: marker, options: .atomic)
    }

    /// Retains the old workspace as a sibling backup. Unknown or unresolved job
    /// states block reset even when the app is no longer polling the provider.
    @discardableResult public func reset() throws -> URL {
        try validateTree()
        guard try Data(contentsOf: marker) == markerData else { throw Failure.unknownWorkspace }
        let files = FileManager.default
        let known: Set<String> = [".genstation-demo-v1", "history_v2.json", "custom_styles.json", "workflows_v1.json", "mcp_state.json", "agent_image_jobs.json", "agent_video_jobs.json", "agent_workflow_jobs.json", "gui_workflow_jobs.json", "RecoveredWorkflowOutputs", "Originals", "Staging", "mcp.sock"]
        let names = try files.contentsOfDirectory(atPath: context.supportDirectory.path)
        guard names.allSatisfy({ known.contains($0) }) else { throw Failure.unknownWorkspace }
        for name in ["history_v2.json", "mcp_state.json", "agent_image_jobs.json", "agent_video_jobs.json", "agent_workflow_jobs.json", "gui_workflow_jobs.json"] where names.contains(name) {
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: context.supportDirectory.appendingPathComponent(name)))
            // Legacy MCP records have no terminal status of their own. Preserve
            // them until recovery can establish their outcome rather than guessing.
            if name == "mcp_state.json", let object = value as? [String: Any],
               let jobs = object["jobs"] as? [String: Any], !jobs.isEmpty { throw Failure.unresolvedJobs }
            try Self.requireSettled(value)
        }
        let backup = context.supportDirectory.deletingLastPathComponent().appendingPathComponent(".genstation-demo-backup-\(UUID().uuidString)")
        try files.moveItem(at: context.supportDirectory, to: backup)
        do { try prepare() }
        catch {
            // Do not delete either tree on failure; the backup always retains the data.
            throw error
        }
        return backup
    }

    private static func requireSettled(_ value: Any) throws {
        if let dictionary = value as? [String: Any] {
            if let status = dictionary["status"] {
                guard let text = status as? String,
                      ["completed", "done", "failed", "denied", "blocked", "expired"].contains(text) else { throw Failure.unresolvedJobs }
            }
            if let reservations = dictionary["reservations"] as? [String: Any], !reservations.isEmpty { throw Failure.unresolvedJobs }
            for child in dictionary.values { try requireSettled(child) }
        } else if let array = value as? [Any] {
            for child in array { try requireSettled(child) }
        }
    }

    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}
