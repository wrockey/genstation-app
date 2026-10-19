import Foundation

/// ImgBB is an image *host*, not a generation provider — GenStation uploads input images
/// there to obtain temporary public URLs for models that will not accept base64 or binary.
public enum ImgBBClient {

    public static let baseURL = URL(string: "https://api.imgbb.com/1")!

    /// Upload target. The key travels as a query parameter, so this URL contains a secret.
    /// `expirationSeconds` defaults to the 10 minutes the privacy notice promises.
    public static func uploadURL(apiKey: String, expirationSeconds: Int = 600) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("upload"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "expiration", value: String(expirationSeconds)),
        ]
        return components.url!
    }

    /// Cheap shape check before spending a network round trip. Two call sites disagreed —
    /// one required 32 hex digits, the other only a length of 32; the stricter rule wins.
    public static func isPlausibleKey(_ key: String) -> Bool {
        key.count == 32 && key.allSatisfy(\.isHexDigit)
    }

    public struct UploadResponse: Codable {
        public let data: UploadData?
        public let success: Bool
        public let status: Int
        public let error: OpenAICompatible.ErrorDict?
        public let status_code: Int?
        public let status_txt: String?
    }

    public struct UploadData: Codable {
        public let id: String
        public let title: String?
        public let url: String?
    }
}
