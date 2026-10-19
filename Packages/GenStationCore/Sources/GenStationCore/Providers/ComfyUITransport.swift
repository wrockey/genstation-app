import Foundation

public struct ComfyUISubmissionRejected: LocalizedError {
    public let statusCode: Int
    public var errorDescription: String? { "ComfyUI rejected the workflow (HTTP \(statusCode)). Check the workflow and server configuration before a new request." }
}

public struct ComfyUIOutput: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let nodeID: String
    public let filename: String
    public let subfolder: String
    public let type: String
    public let kind: String
    public init(id: String, nodeID: String, filename: String, subfolder: String, type: String, kind: String) {
        self.id = id; self.nodeID = nodeID; self.filename = filename
        self.subfolder = subfolder; self.type = type; self.kind = kind
    }
    public var isVideo: Bool {
        kind == "gifs" || kind == "videos" || ["mp4", "mov", "m4v", "webm", "gif", "avi"].contains((filename as NSString).pathExtension.lowercased())
    }
}

public struct ComfyUIUploadedImage: Codable, Equatable, Sendable {
    public let name: String
    public let subfolder: String
    public var serverFileID: String { subfolder.isEmpty ? name : subfolder + "/" + name }
}

/// Shared HTTP boundary. Submit makes exactly one attempt. Polling/download are
/// GET-only and cannot restart generation, even after a network failure.
public struct ComfyUITransport {
    public let serverURL: String
    private let session: URLSession
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private static let defaultSession = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
    public init(serverURL: String, session: URLSession? = nil) throws {
        let normalized = ComfyUIEndpoints.normalizedServerURL(serverURL)
        guard let url = URL(string: normalized), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw AgentImageError("Configure a valid ComfyUI HTTP(S) server.")
        }
        self.serverURL = normalized
        self.session = session ?? Self.defaultSession
    }

    public func submit(apiWorkflow: [String: Any], clientID: String,
                       persistIntent: @MainActor () throws -> Void,
                       persistPromptID: @MainActor (String) throws -> Void) async throws -> String {
        try WorkflowPromptSafety.requireSafe(apiWorkflow)
        guard let url = ComfyUIEndpoints.promptURL(serverURL: serverURL) else { throw AgentImageError("Invalid ComfyUI prompt endpoint.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": apiWorkflow, "client_id": clientID], options: .sortedKeys)
        try Task.checkCancellation()
        try await persistIntent()
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, (400...499).contains(http.statusCode), http.statusCode != 408 {
            throw ComfyUISubmissionRejected(statusCode: http.statusCode)
        }
        try Self.check(response, operation: "submission")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["prompt_id"] as? String, Self.validPromptID(id) else {
            throw AgentImageError("ComfyUI did not return a prompt ID. Submission outcome is unknown; do not automatically resubmit.")
        }
        try await persistPromptID(id)
        return id
    }

    public func history(promptID: String) async throws -> [String: Any]? {
        guard Self.validPromptID(promptID),
              let url = ComfyUIEndpoints.historyURL(serverURL: serverURL, promptID: promptID) else {
            throw AgentImageError("Invalid ComfyUI prompt ID.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await GenerationTransport.recover(request, session: session)
        try Self.check(response, operation: "history retrieval")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AgentImageError("Invalid ComfyUI history response.") }
        let entry = object[promptID] as? [String: Any]
        if let status = entry?["status"] as? [String: Any], let failure = ComfyUIExecutionStatus.failureMessage(status) {
            throw AgentImageError(failure)
        }
        return entry
    }

    /// One approved upload attempt. This operation never submits a workflow.
    public func uploadPNG(_ data: Data) async throws -> ComfyUIUploadedImage {
        guard data.count <= 20_000_000, data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let url = ComfyUIEndpoints.uploadImageURL(serverURL: serverURL) else {
            throw AgentImageError("Workflow input must be a validated PNG of at most 20 MB.")
        }
        let boundary = "GenStation-" + UUID().uuidString
        let filename = "genstation_" + UUID().uuidString.lowercased() + ".png"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\nContent-Type: image/png\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"type\"\r\n\r\ninput\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\nfalse\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        try Task.checkCancellation()
        let (responseData, response) = try await session.data(for: request)
        try Self.check(response, operation: "image upload")
        return try Self.uploadedImage(from: responseData)
    }

    public static func uploadedImage(from data: Data) throws -> ComfyUIUploadedImage {
        func safeComponent(_ value: String) -> Bool {
            !value.isEmpty && value != "." && value != ".." && value.utf8.count <= 255 &&
            !value.contains(where: { $0 == "/" || $0 == "\\" || $0 == ":" || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true })
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String, safeComponent(name), name.lowercased().hasSuffix(".png"),
              json["type"] as? String == "input",
              let subfolder = json["subfolder"] as? String,
              subfolder.isEmpty || (subfolder.utf8.count <= 1024 && subfolder.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { safeComponent(String($0)) }) else {
            throw AgentImageError("Server returned an unsafe image identifier. No workflow was submitted; the uploaded input may remain on the server.")
        }
        return ComfyUIUploadedImage(name: name, subfolder: subfolder)
    }

    public static func outputs(in entry: [String: Any], selectedNodeID: String? = nil, selectedNodeIDs: [String] = []) -> [ComfyUIOutput] {
        guard let outputs = entry["outputs"] as? [String: Any] else { return [] }
        var result: [ComfyUIOutput] = []
        for nodeID in outputs.keys.sorted() {
            if !selectedNodeIDs.isEmpty {
                if !selectedNodeIDs.contains(nodeID) { continue }
            } else if let selectedNodeID, !selectedNodeID.isEmpty, nodeID != selectedNodeID { continue }
            guard let node = outputs[nodeID] as? [String: Any] else { continue }
            for kind in ["images", "gifs", "videos"] {
                for (index, media) in ((node[kind] as? [[String: Any]]) ?? []).enumerated() {
                    guard let filename = media["filename"] as? String, !filename.isEmpty else { continue }
                    result.append(ComfyUIOutput(id: "\(nodeID):\(kind):\(index)", nodeID: nodeID, filename: filename,
                        subfolder: media["subfolder"] as? String ?? "", type: media["type"] as? String ?? "output", kind: kind))
                }
            }
        }
        return result
    }

    public func download(_ output: ComfyUIOutput) async throws -> Data {
        guard let url = ComfyUIEndpoints.viewURL(serverURL: serverURL, filename: output.filename, subfolder: output.subfolder, type: output.type) else {
            throw AgentImageError("Invalid ComfyUI output descriptor.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (bytes, response) = try await session.bytes(for: request)
        try Self.check(response, operation: "output download")
        let limit = 50_000_000
        guard response.expectedContentLength <= limit else { throw AgentImageError("Workflow output exceeds the 50 MB per-file limit.") }
        var data = Data()
        data.reserveCapacity(response.expectedContentLength > 0 ? Int(response.expectedContentLength) : 65_536)
        for try await byte in bytes {
            guard data.count < limit else { throw AgentImageError("Workflow output exceeds the 50 MB per-file limit.") }
            data.append(byte)
        }
        guard !data.isEmpty else { throw AgentImageError("ComfyUI returned an empty output file.") }
        return data
    }

    private static func check(_ response: URLResponse, operation: String) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AgentImageError("ComfyUI \(operation) failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
    }

    private static func validPromptID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 256 && id != "." && id != ".." &&
            id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_" )).contains($0) }
    }
}
