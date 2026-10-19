import Foundation

/// The AI/ML API's base URL and its endpoint-routing rules.
///
/// Every AI/ML endpoint string in the app now resolves here — `ModelRegistry.swift`'s 198 per-model
/// literals collapsed onto the members below in Stage 2, which is what let `EndpointBoundaryTests`
/// drop its last file exemption. **CORRECTED 2026-07-27 (Stage 3, Task 26):** `ModelRegistry` is
/// deleted; `CatalogModel.generationEndpoint` / `.pollingEndpoint` now own *which* endpoint each
/// model uses. This type owns what those endpoints are, plus the two routing *rules* that were each
/// implemented twice and could drift: `/v1/images/edits` routing and video-endpoint synthesis.
public enum AIMLEndpoints {

    public static let baseURL = URL(string: "https://api.aimlapi.com")!

    /// Billing *console* — a human-facing page, not an API. Embedded in credit-exhaustion
    /// copy and in the MCP `insufficient_credits` payload, where `smoke_test.py` asserts it.
    public static let billingConsoleURLString = "https://aimlapi.com/app/billing/"

    public static var imagesGenerationsURL: URL { baseURL.appendingPathComponent("v1/images/generations") }
    public static var imagesEditsURL: URL { baseURL.appendingPathComponent("v1/images/edits") }
    public static var videoGenerationsURL: URL { baseURL.appendingPathComponent("v2/video/generations") }
    public static var chatCompletionsURL: URL { baseURL.appendingPathComponent("v1/chat/completions") }
    public static var modelsURL: URL { baseURL.appendingPathComponent("models") }
    public static var balanceFallbackURL: URL { baseURL.appendingPathComponent("v1/billing/balance") }

    /// Primary balance endpoint. Lives on a different host from everything else, which is
    /// why `AIMLAPIBilling` falls back to `balanceFallbackURL` on failure.
    public static let balanceURL = URL(string: "https://billing.aimlapi.com/v1/billing/balance")!

    // MARK: - Registry endpoint strings

    /// `ModelRegistry`'s per-model `generationEndpoint` / `pollingEndpoint` are `String`s, and its
    /// 198 literals turned out to be only these few distinct shapes. They are spelled as strings
    /// rather than reusing the `URL` members above so the registry substitution is a swap of
    /// equal-valued constants — which cannot change any posting URL. `AIMLEndpointsTests` pins both
    /// each value and its agreement with the corresponding `URL` member.
    ///
    /// Note these are *not* interchangeable with `videoEndpoint(modelID:)`: which shape a model uses
    /// is a per-model fact recorded on `CatalogModel.generationEndpoint` (was the registry; deleted
    /// Stage 3, Task 26), and synthesis reproduces it for only 38 of the 129 registered video ids.
    /// The catalog is the truth; see `videoEndpoint(modelID:)`.
    public static let imageGeneration = "https://api.aimlapi.com/v1/images/generations"
    public static let videoGeneration = "https://api.aimlapi.com/v2/video/generations"
    public static let videoGenerationPoll = "https://api.aimlapi.com/v2/video/generations?generation_id="
    public static let klingGeneration = "https://api.aimlapi.com/v2/generate/video/kling/generation"
    public static let klingGenerationPoll = "https://api.aimlapi.com/v2/generate/video/kling/generation?generation_id="

    /// The synthesized per-provider video path, for the registry's fallback branch that handles an
    /// id it does not know. Registered models name their endpoint explicitly instead.
    public static func providerVideoGeneration(provider: String) -> String {
        "https://api.aimlapi.com/v2/generate/video/\(provider)/generation"
    }

    public static func providerVideoGenerationPoll(provider: String) -> String {
        "\(providerVideoGeneration(provider: provider))?generation_id="
    }

    /// Where an image generation posts.
    ///
    /// Mask-capable `gpt-image-*` models edit via `/v1/images/edits` when an input image is
    /// present; everything else — including `gpt-image-1.5` and `-mini`, which are
    /// text-to-image only — uses `/generations`.
    public static func imageEndpoint(supportsMask: Bool, hasInputImages: Bool) -> URL {
        supportsMask && hasInputImages ? imagesEditsURL : imagesGenerationsURL
    }

    /// Where a video generation posts.
    ///
    /// `openai/*` and `google/*` share the v2 video endpoint; every other provider gets a
    /// path synthesized from the first component of the model id. A model id with no `/`
    /// falls back to the shared endpoint rather than emitting an empty path component.
    public static func videoEndpoint(modelID: String) -> URL {
        if modelID.hasPrefix("openai/") || modelID.hasPrefix("google/") {
            return videoGenerationsURL
        }
        let parts = modelID.split(separator: "/")
        guard parts.count >= 2, !parts[0].isEmpty else { return videoGenerationsURL }
        return baseURL.appendingPathComponent("v2/generate/video/\(parts[0])/generation")
    }

    /// The poll URL prefix for a generation endpoint. `JobQueue` appends the job id
    /// directly, so this deliberately ends with `=`.
    public static func pollingEndpoint(for generationEndpoint: URL) -> String {
        "\(generationEndpoint.absoluteString)?generation_id="
    }

    // MARK: - Wire DTOs

    public struct VideoGenerationResponse: Codable {
        public let id: String?
        public let status: String?
        public let error: OpenAICompatible.ErrorDict?
    }

    public struct VideoPollResponse: Codable {
        public let id: String
        public let status: String
        public let video: VideoURL?
        public let error: OpenAICompatible.ErrorDict?
    }

    public struct VideoURL: Codable {
        public let url: String
    }

    public struct VideoErrorResponse: Codable {
        public let id: String?
        public let status: String?
        public let error: OpenAICompatible.ErrorDict?
    }

    /// The `GET /models` wire shape.
    ///
    /// Moved out of `ConfigurationSection.swift:11-19`, where it lived in the app target and could
    /// therefore be tested against nothing at all. `AIMLModelsFixtureTests` now decodes the captured
    /// live response (`Tests/GenStationCoreTests/Fixtures/aiml-models-response.json`, committed at
    /// `b16f840`) through it.
    ///
    /// **Every field except `id` is optional, and that is a rule, not an accident.** This type
    /// decodes a third party's response. A field disappearing from the wire must degrade a feature,
    /// never break the decode and empty the model picker. Only `id` is required, because an entry
    /// without one cannot be referred to.
    public struct ModelEntry: Codable, Sendable, Hashable {

        /// The per-entry `info` block. Present on 907/907 captured entries; still optional, per the
        /// rule above.
        ///
        /// The captured block carries eleven keys. The seven modelled here are the ones Stage 3
        /// consumes. `url`, `contextLength`, `outputMax` and `cutoffAt` are deliberately unmodelled —
        /// nothing needs them — and `AIMLModelsFixtureTests.testTheInfoKeysAreWhatWasObserved`
        /// records the full observed set so an unmodelled key is documented rather than invisible.
        public struct Info: Codable, Sendable, Hashable {
            /// 907/907. The vendor's own display name. Spec § 3.4: this is `displayName`'s source.
            public let name: String?
            /// 907/907. Spec § 3.4: this seeds `family`.
            public let developer: String?
            /// 907/907. Human documentation page.
            public let docsUrl: String?
            /// 907/907. The per-model OpenAPI document; 167 of them are captured in
            /// `Fixtures/aiml-model-schemas.json`.
            public let docsJson: String?
            /// 899/907 — **8 entries lack it**, so every ordering that uses it needs a defined
            /// fallback. ISO `yyyy-MM-dd`, kept as a String: it is a sort key, not a date.
            public let releasedAt: String?
            /// 769/907. Row subtitles.
            public let description: String?
            /// 55/907. The vendor's own recommended set; spec § 3.8's **Recommended** group.
            public let isHottest: Bool?

            public init(
                name: String? = nil,
                developer: String? = nil,
                docsUrl: String? = nil,
                docsJson: String? = nil,
                releasedAt: String? = nil,
                description: String? = nil,
                isHottest: Bool? = nil
            ) {
                self.name = name
                self.developer = developer
                self.docsUrl = docsUrl
                self.docsJson = docsJson
                self.releasedAt = releasedAt
                self.description = description
                self.isHottest = isHottest
            }
        }

        public let id: String
        public let aliases: [String]?
        /// The **endpoint family** that serves this entry — `internal/video-generations/submit`,
        /// `openai/image-generations`, `openai/chat-completions`, … It is not `"image"`/`"video"`.
        /// Classify it with `AIMLEndpoints.wireTask(forEndpointFamilies:)`; never by substring.
        public let type: String?
        /// `playground:video` / `playground:image` / `playground:chat` plus a tier marker. A second,
        /// independent confirmation of `type`.
        public let tags: [String]?
        public let info: Info?

        public init(
            id: String,
            aliases: [String]? = nil,
            type: String? = nil,
            tags: [String]? = nil,
            info: Info? = nil
        ) {
            self.id = id
            self.aliases = aliases
            self.type = type
            self.tags = tags
            self.info = info
        }
    }

    /// The app's old `AIMLModelsResponse` also declared a **required** `object: String`. It is
    /// dropped: nothing ever read it, and a required field the server could stop sending is a decode
    /// failure waiting to happen. `JSONDecoder` ignores unknown keys, so this is strictly more
    /// permissive than what it replaces — it cannot fail on a body the old type accepted.
    public struct ModelsResponse: Codable, Sendable {
        public let data: [ModelEntry]

        public init(data: [ModelEntry]) {
            self.data = data
        }
    }

    // MARK: - Endpoint-family classification

    /// What an endpoint family produces. `other` is a real answer, not a failure: 569 of the 907
    /// captured entries are chat, responses, messages, batches, TTS, STT, embeddings, audio or OCR
    /// models. They are not unclassifiable — they are not generation models, and the model pickers
    /// must exclude them.
    public enum WireTask: String, Sendable, Hashable, CaseIterable {
        case image
        case video
        case other
    }

    /// Endpoint families that produce video. Captured distribution: 207 entries.
    public static let videoEndpointFamilies: Set<String> = [
        "internal/video-generations/submit",
    ]

    /// Endpoint families that produce images. Captured distribution: 126 + 5 = 131 entries.
    public static let imageEndpointFamilies: Set<String> = [
        "openai/image-generations",
        "openai/image-editing",
    ]

    /// Endpoint families that produce neither, enumerated rather than defaulted. Captured
    /// distribution: 569 entries. Listing them explicitly is what lets the tripwire below tell
    /// "a family we decided is not a generation family" apart from "a family nobody has seen".
    public static let nonGenerationEndpointFamilies: Set<String> = [
        "anthropic/batches",
        "anthropic/batches-cancel",
        "anthropic/batches-status",
        "anthropic/messages",
        "internal/audio-generations/submit",
        "internal/optical-character-recognition",
        "internal/speech-to-text/submit",
        "internal/text-to-speech",
        "openai/chat-completions",
        "openai/embeddings",
        "openai/responses/submit",
    ]

    /// Every endpoint family this classifier has an opinion about. A `type` value outside this set
    /// is a **new endpoint family** and must be triaged deliberately —
    /// `AIMLTypeAgreementTests.testEveryWireTypeIsAKnownEndpointFamily` fails on it rather than
    /// letting it fall through to `.other` and vanish from the pickers.
    public static var knownEndpointFamilies: Set<String> {
        videoEndpointFamilies
            .union(imageEndpointFamilies)
            .union(nonGenerationEndpointFamilies)
    }

    /// Classify a *spelling*, which may be served on several endpoint families at once.
    ///
    /// 91 of the 762 captured ids appear under more than one family — the same model exposed on
    /// `chat-completions` **and** `image-generations`, for instance. Classification is therefore over
    /// a set, and video wins over image wins over neither. No captured id is both video and image.
    public static func wireTask(forEndpointFamilies families: Set<String>) -> WireTask {
        if !families.isDisjoint(with: videoEndpointFamilies) { return .video }
        if !families.isDisjoint(with: imageEndpointFamilies) { return .image }
        return .other
    }

    /// The `CreateTask` a wire classification denotes, or nil for a non-generation model.
    public static func createTask(for wireTask: WireTask) -> CreateTask? {
        switch wireTask {
        case .image: return .image
        case .video: return .video
        case .other: return nil
        }
    }

    /// Which entry's `info` block wins when one spelling is served on several endpoint families.
    /// Generation families first, in this order; a spelling served on none of them falls back to the
    /// lexicographically smallest `type`, so the answer never depends on JSON ordering.
    public static let infoPreferenceOrder: [String] = [
        "internal/video-generations/submit",
        "openai/image-generations",
        "openai/image-editing",
    ]

    // MARK: - Response Reading

    /// Extracts the actual USD cost from an AIML API response body, if present.
    /// AIML responses include `meta.usage.usd_spent` (image) or a top-level `usage`.
    public static func usdSpent(from data: Data) -> Double? {
        ProviderChargeEvidence.observe(provider: .aimlapi, data: data, httpStatus: 200).evidence?.amount.displayUSD
    }

    /// True when a `friendlyError(status:body:)`-produced message is the credit-exhaustion
    /// classification (402/403 + balance keywords). Lets the MCP layer map the
    /// failure to the structured 'insufficient_credits' error code.
    public static func isInsufficientCredits(_ message: String) -> Bool {
        message.contains("out of API credits")
    }

    /// Maps a failed HTTP response to a concise, user-facing message instead of a raw status dump.
    /// Handles the AIML/OpenAI/Google error JSON shapes (message / error.message / error / title).
    public static func friendlyError(status: Int, body: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            let error = json["error"] as? [String: Any] ?? json
            let code = error["code"] as? String ?? error["type"] as? String
            if ProviderFailure.classify(provider: .aimlapi, status: status, code: code, phase: .submission).kind == .credits {
                return "You're out of API credits. Check your provider balance before generating again."
            }
        }
        let raw = String(data: body, encoding: .utf8) ?? ""
        var detail = ""
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let m = json["message"] as? String { detail = m }
            else if let e = json["error"] as? [String: Any], let m = e["message"] as? String { detail = m }
            else if let e = json["error"] as? String { detail = e }
            else if let t = json["title"] as? String { detail = t }
        }
        let lower = (detail + " " + raw).lowercased()
        detail = ProviderFailure.redact(detail)
        switch status {
        case 401:
            return "Invalid or missing API key — check your key in Settings."
        case 402, 403:
            if lower.contains("fund") || lower.contains("balance") || lower.contains("credit") || lower.contains("top up") {
                // Keep in sync with isInsufficientCredits(_:).
                return "You're out of API credits. Top up your balance to continue:\n\(AIMLEndpoints.billingConsoleURLString)"
            }
            return detail.isEmpty ? "Access denied (HTTP \(status))." : detail
        case 404:
            if lower.contains("model") { return "This model isn't available on your plan (or was renamed). Try another model or toggle Advanced models." }
            return detail.isEmpty ? "Not found (HTTP \(status))." : detail
        case 429:
            return "Rate limited — too many requests. Wait a moment and try again."
        case 400:
            if lower.contains("moder") || lower.contains("safety") || lower.contains("content policy") || lower.contains("flag") {
                return "The request was blocked by content moderation. Try adjusting the prompt or input image."
            }
            return detail.isEmpty ? "Invalid request (HTTP 400)." : "Invalid request: \(detail)"
        case 500...599:
            return "The provider had a server error (HTTP \(status)). Please try again in a moment."
        default:
            return detail.isEmpty ? "Request failed (HTTP \(status))." : detail
        }
    }

    /// Decoded result from an AIML video poll response.
    /// Used by both the live polling loop and the background resume path.
    public enum VideoPollResult {
        case inProgress(status: String)
        /// costUSD is the actual `usd_spent` from the completion poll response, when
        /// the provider includes it — it only appears in this final response, so it
        /// must be captured here or it is lost.
        case completed(videoUrl: String, costUSD: Double?)
        case failed(message: String)
        case decodingError(message: String?)
    }

    /// Decodes AIML or normalized native video poll data; billing uses the actual provider adapter.
    /// Handles both normal and error response formats.
    public static func decodeVideoPoll(_ data: Data, provider: Provider = .aimlapi) -> VideoPollResult {
        // Try normal response first
        if let decoded = try? JSONDecoder().decode(AIMLEndpoints.VideoPollResponse.self, from: data) {
            if let err = decoded.error {
                return .failed(message: err.message ?? "Unknown error")
            }
            let parsed = GenerationStatus(legacy: decoded.status)
            if parsed.isInProgress { return .inProgress(status: decoded.status) }
            if parsed == .completed {
                guard let urlString = decoded.video?.url else {
                    return .failed(message: "No video URL returned")
                }
                return .completed(videoUrl: urlString, costUSD: ProviderChargeEvidence.observe(provider: provider, data: data, httpStatus: 200).evidence?.amount.displayUSD)
            }
            return .failed(message: "Generation ended with status: \(decoded.status)")
        }
        // Try error response format
        if let errorResp = try? JSONDecoder().decode(AIMLEndpoints.VideoErrorResponse.self, from: data),
           let err = errorResp.error {
            return .failed(message: err.message ?? "Server error")
        }
        return .decodingError(message: String(data: data, encoding: .utf8))
    }
}
