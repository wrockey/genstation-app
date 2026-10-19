import Foundation

public enum ProviderFailure {
    public enum Phase: Sendable { case connection, submission, polling, download, save }
    public enum Kind: String, Sendable { case credentials, denied, credits, throttled, input, unavailable, offline, timeout, save, unknown }
    public struct Diagnosis: Equatable, Sendable {
        public let kind: Kind
        public let message: String
    }
    public static func classify(provider: Provider, status: Int? = nil, code: String? = nil,
                                phase: Phase, transportCode: Int? = nil) -> Diagnosis {
        let code = code?.lowercased() ?? ""
        if phase == .save { return Diagnosis(kind: .save, message: "The result could not be saved. Check disk space and output-folder access, then download the existing result again when available.") }
        if ["insufficient_credits", "insufficient_balance", "insufficient_funds", "billing_hard_limit_reached"].contains(code) {
            return Diagnosis(kind: .credits, message: "Your provider reports insufficient credits. Check your provider balance. Your draft and saved job are retained.")
        }
        if ["content_policy_violation", "moderation_blocked", "invalid_argument", "invalid_request_error"].contains(code) {
            return Diagnosis(kind: .input, message: "The provider rejected the input or model options. Edit your prompt, images, or settings before generating.")
        }
        switch status ?? -1 {
        case 401: return Diagnosis(kind: .credentials, message: "Credentials rejected. Open provider settings and check your key.")
        case 403: return Diagnosis(kind: .denied, message: "Provider access denied. Check this key's permissions and model restrictions.")
        case 429: return Diagnosis(kind: .throttled, message: "Provider rate or quota limit reached. Wait and check your provider limits; no new generation was started automatically.")
        case 400, 422: return Diagnosis(kind: .input, message: "The provider rejected the input or model options. Review the prompt, images, and settings.")
        case 500...599: return Diagnosis(kind: .unavailable, message: "The provider is unavailable. If submission already began, check the existing job before generating again.")
        default: break
        }
        if transportCode == NSURLErrorTimedOut {
            return Diagnosis(kind: .timeout, message: phase == .submission
                ? "Submission timed out. The provider may have accepted it. Check the existing job or provider dashboard before starting another paid generation."
                : "The connection timed out. Check the existing job or download again; do not resubmit automatically.")
        }
        if transportCode != nil { return Diagnosis(kind: .offline, message: "Connection interrupted or offline. Check your network, then recover the existing job if available.") }
        return Diagnosis(kind: .unknown, message: "The provider request failed. Review the details and preserve your draft before trying again.")
    }
    public static func message(provider: Provider, status: Int, body: Data, phase: Phase) -> String {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let error = json["error"] as? [String: Any] ?? json
        let code = error["code"] as? String ?? error["type"] as? String
        let diagnosis = classify(provider: provider, status: status, code: code, phase: phase)
        let detail = error["message"] as? String ?? ""
        return diagnosis.message + (detail.isEmpty ? "" : "\n" + redact(detail))
    }
    /// Bounded diagnostics suitable for alerts and copying. Never include raw request bodies.
    public static func redact(_ text: String) -> String {
        var result = text
        let patterns = [
            #"(?i)(authorization\s*[:=]\s*)(?:bearer\s+)?[^\s,\"}]+"#,
            #"(?i)([?&](?:key|api_key|apikey|token|access_token|signature|sig)=)[^&\s\"]+"#,
            #"(?i)(\"?(?:api_key|apikey|authorization|access_token)\"?\s*:\s*\")[^\"]+"#,
            #"(?i)(data:image/[^;]+;base64,)[A-Za-z0-9+/=]+"#,
            #"\b(?:sk-|xai-|AIza)[A-Za-z0-9_-]{12,}\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "[redacted]")
        }
        return String(result.prefix(1600))
    }
}
