import Foundation

/// URL construction for a local (or LAN) ComfyUI server.
///
/// Unlike the three hosted providers, ComfyUI's host is **user-supplied** — an
/// `@AppStorage("comfyServerURL")` text field defaulting to `http://localhost:8188`. Every
/// builder therefore returns an optional: a typo is an ordinary runtime state, not a
/// programming error. Callers surface `GenerationError.invalidURL` on nil, as they do today.
public enum ComfyUIEndpoints {

    /// Accepts what a user is likely to type — `localhost:8188`, a trailing slash, stray
    /// whitespace — and returns something `URL(string:)` can parse.
    ///
    /// **Two deliberate behavior changes** against the four copies this replaces, both fixes:
    /// 1. Trailing slashes are stripped. The old version did not, so `http://host/` and
    ///    `http://host` compared unequal in `cachedObjectInfoMatches(serverURL:)` and caused
    ///    a spurious `object_info` cache miss.
    /// 2. The WebSocket path now normalizes too. The live WS code parsed the raw setting, and
    ///    `URL(string: "localhost:8188")` yields scheme `localhost` — so a user who typed a
    ///    host with no scheme got working HTTP (which normalized separately) but a silently
    ///    broken progress socket.
    public static func normalizedServerURL(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if !trimmed.contains("://") {
            trimmed = "http://\(trimmed)"
        }
        // Strip trailing slashes, but never past the "://" separator — "http://" (no host)
        // must stay "http://" so `base(_:)` below can reject it for its nil host, rather
        // than being stripped to "http:" and re-prefixed into the bogus "http://http:".
        let separatorEnd = trimmed.range(of: "://")?.upperBound ?? trimmed.startIndex
        while trimmed.hasSuffix("/"), trimmed.index(before: trimmed.endIndex) >= separatorEnd {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func base(_ serverURL: String) -> URL? {
        let normalized = normalizedServerURL(serverURL)
        guard !normalized.isEmpty, let url = URL(string: normalized), url.host != nil,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            return nil
        }
        return url
    }

    public static func objectInfoURL(serverURL: String) -> URL? {
        base(serverURL)?.appendingPathComponent("object_info")
    }

    public static func objectInfoURL(serverURL: String, classType: String) -> URL? {
        objectInfoURL(serverURL: serverURL)?.appendingPathComponent(classType)
    }

    public static func promptURL(serverURL: String) -> URL? {
        base(serverURL)?.appendingPathComponent("prompt")
    }

    public static func uploadImageURL(serverURL: String) -> URL? {
        base(serverURL)?.appendingPathComponent("upload/image")
    }

    public static func historyURL(serverURL: String, promptID: String) -> URL? {
        base(serverURL)?.appendingPathComponent("history").appendingPathComponent(promptID)
    }

    public static func interruptURL(serverURL: String) -> URL? {
        base(serverURL)?.appendingPathComponent("interrupt")
    }

    /// Output download. `filename` regularly contains spaces, so the query is built with
    /// `URLComponents` rather than string interpolation.
    public static func viewURL(
        serverURL: String, filename: String, subfolder: String, type: String
    ) -> URL? {
        guard let base = base(serverURL) else { return nil }
        var components = URLComponents(
            url: base.appendingPathComponent("view"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "subfolder", value: subfolder),
            URLQueryItem(name: "type", value: type),
        ]
        return components?.url
    }

    /// Progress socket. `http` becomes `ws` and `https` becomes `wss` — a mismatch here
    /// fails silently, leaving the run with no progress reporting at all.
    ///
    /// `/ws` is **appended** to the host's existing path rather than replacing it, so a
    /// ComfyUI served behind a reverse-proxy subpath keeps working, and the append is
    /// idempotent. This mirrors the live code being replaced.
    public static func webSocketURL(serverURL: String, clientID: String) -> URL? {
        guard let base = base(serverURL),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        components.scheme = (components.scheme?.lowercased() == "https") ? "wss" : "ws"
        if !components.path.hasSuffix("/ws") {
            components.path += components.path.hasSuffix("/") ? "ws" : "/ws"
        }
        components.queryItems = [URLQueryItem(name: "clientId", value: clientID)]
        return components.url
    }
}
