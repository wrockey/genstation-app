import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Non-generating authenticated reads. Never infer authentication from an error response.
public enum KeyValidation {
    public static func request(provider: Provider, key: String) -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        switch provider {
        case .gemini: url = GeminiClient.modelsURL(apiKey: key)
        case .grok: url = GrokClient.modelsURL
        case .aimlapi: url = AIMLEndpoints.baseURL.appendingPathComponent("v2/billing/detail")
        case .comfyUI: preconditionFailure("Use the existing server connection check")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        if provider != .gemini { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }

    public static func check(provider: Provider, key: String, session: URLSession = .shared) async throws {
        do {
            let (data, response) = try await session.data(for: request(provider: provider, key: key))
            guard let http = response as? HTTPURLResponse else { throw ConnectionFailure.unavailable }
            if provider == .gemini, http.statusCode == 400,
               let body = String(data: data, encoding: .utf8), body.contains("API_KEY_INVALID") {
                throw ConnectionFailure.credentials
            }
            if let failure = failure(status: http.statusCode) { throw failure }
        } catch let failure as ConnectionFailure { throw failure }
        catch is CancellationError { throw CancellationError() }
        catch { throw ConnectionFailure.offline }
    }

    public static func failure(status: Int) -> ConnectionFailure? {
        switch status {
        case 200..<300: return nil
        case 401: return .credentials
        case 403: return .denied
        case 429: return .throttled
        default: return .unavailable
        }
    }
}

public enum ConnectionFailure: Error, LocalizedError {
    case credentials, denied, throttled, unavailable, offline
    public var errorDescription: String? {
        switch self {
        case .credentials: return "Credentials rejected. Check the key in provider settings."
        case .denied: return "Access denied. Check this key's permissions with your provider."
        case .throttled: return "The provider is limiting requests. Wait before checking again."
        case .unavailable: return "The provider could not verify this connection. Try again later."
        case .offline: return "Connection interrupted or offline. Check your network and try again."
        }
    }
}
