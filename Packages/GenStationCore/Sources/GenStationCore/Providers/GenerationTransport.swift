import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A submission identity can cause at most one POST, even after an ambiguous network failure.
/// Approval is supplied by the UI review or the existing noninteractive agent policy.
public actor GenerationTransport {
    private var submitted: Set<UUID> = []
    public init() {}
    public func submit(_ request: URLRequest, id: UUID, approved: Bool, session: URLSession = .shared) async throws -> (Data, URLResponse) {
        guard approved else { throw CancellationError() }
        try Task.checkCancellation()
        guard request.httpMethod == "POST", submitted.insert(id).inserted else {
            throw TransportError.duplicateOrInvalidSubmission
        }
        return try await session.data(for: request)
    }
    public enum TransportError: Error { case duplicateOrInvalidSubmission, recoveryMustBeReadOnly }
    /// Recovery is structurally unable to issue a new generation POST.
    public static func recover(_ request: URLRequest, session: URLSession = .shared) async throws -> (Data, URLResponse) {
        guard request.httpMethod == "GET", request.httpBody == nil else {
            throw TransportError.recoveryMustBeReadOnly
        }
        return try await session.data(for: request)
    }
}
