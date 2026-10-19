import Foundation

/// Shared ordering boundary: approval and durable intent must both succeed before transport.
/// No retries here; the caller's durable request ledger owns replay decisions.
public enum AgentImageSubmission {
    @MainActor
    public static func perform(request: URLRequest,
                               authorize: () async throws -> Void,
                               persistIntent: () throws -> Void,
                               transport: (URLRequest) async throws -> (Data, URLResponse)) async throws -> (Data, URLResponse) {
        try await authorize()
        try persistIntent()
        return try await transport(request)
    }
}
