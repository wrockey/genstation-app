import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The queue invokes this only after approval. Persistence must succeed before network dispatch.
public enum AgentVideoSubmission {
    @MainActor
    public static func perform(_ request: URLRequest, jobID: UUID, transport: GenerationTransport,
                               session: URLSession, persistIntent: () throws -> Void) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        try persistIntent()
        return try await transport.submit(request, id: jobID, approved: true, session: session)
    }
}
