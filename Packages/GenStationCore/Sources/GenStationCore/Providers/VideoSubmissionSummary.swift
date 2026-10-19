import Foundation

public enum VideoSubmissionSummary {
    public static func describe(payload: Data) -> String {
        let body = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        func value(_ keys: [String], fallback: String) -> String {
            for key in keys { if let value = body[key] { return String(describing: value) } }
            return fallback
        }
        let model = (body["model"] as? String).flatMap { Catalog.model(for: $0) }
        func present(_ key: String) -> Bool {
            guard let v = body[key] else { return false }
            if let values = v as? [Any] { return !values.isEmpty }
            if let value = v as? String { return !value.isEmpty }
            return !(v is NSNull)
        }
        let frames = ["image", "image_url", "image_urls", "first_frame_image", "first_frame_url", "start_image_url", model?.imageInputParam ?? ""].contains(where: present)
        let last = ["last_frame_image", "last_frame_url", "end_image_url", model?.secondImageParam ?? ""].contains(where: present)
        return "Duration: \(value(["duration"], fallback: "model default"))\nResolution: \(value(["resolution"], fallback: "model default"))\nAspect: \(value(["aspect_ratio"], fallback: "model / source image default"))\nAudio: \(value(["generate_audio", "audio"], fallback: "model default"))\nFirst frame: \(frames ? "present" : "none")\nLast frame: \(last ? "present" : "none")\nHosting: \(containsHostedInput(body) ? "Input uses hosted URLs shared with the provider." : "No hosted input URLs.")"
    }
    public static func containsHostedInput(_ value: Any) -> Bool {
        if let s = value as? String { return s.hasPrefix("https://") || s.hasPrefix("http://") }
        if let a = value as? [Any] { return a.contains(where: containsHostedInput) }
        if let d = value as? [String: Any] { return d.filter { $0.key != "prompt" }.values.contains(where: containsHostedInput) }
        return false
    }
}
