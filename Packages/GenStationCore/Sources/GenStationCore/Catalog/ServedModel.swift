import Foundation

/// One generation model the AI/ML API currently serves, reduced to what a browser needs.
///
/// This is the app's runtime half of the capture (design § 4.4). `AIMLEndpoints.ModelEntry` is the
/// wire shape; this is what survives classification, grouping and persistence. It exists because
/// `/models` publishes per-model metadata the app used to discard at decode — `type`, `info.name`,
/// `info.developer`, `info.releasedAt`, `info.isHottest` — and every one of those replaces a guess.
///
/// It is `Codable` because it is cached in `UserDefaults` alongside the flat id list, so the picker
/// can classify and name models on a cold launch before any fetch completes.
public struct ServedModel: Codable, Sendable, Hashable {

    /// Lowercased. No captured generation id carries uppercase, but lowercasing here is what makes
    /// the catalog lookup and the dedupe single-cased, and it is what ends the "5 served ids
    /// carrying uppercase can never match" bug in the old curated intersection.
    public let id: String

    /// The API's own alias spellings for this entry, lowercased and sorted. Consulted when `id`
    /// itself is unknown to the catalog: six registered ids (`gpt-image-1`, `gpt-image-2`,
    /// `gpt-image-1.5`, `sora-2-t2v`, `veo2`, `imagen-4.0-generate-001`) are reachable *only*
    /// inside some entry's `aliases` array.
    public let aliases: [String]

    /// From the endpoint family, never from the id's spelling.
    public let task: CreateTask

    /// `info.name` — present on 907/907 captured entries.
    public let displayName: String

    /// `info.developer` — present on 907/907. Seeds the section title for an unregistered model,
    /// which is what keeps registered and unregistered rows in coherent sections (spec § 3.4 makes
    /// `CatalogModel.family` seed from the same field).
    public let developer: String

    /// `info.description` — 769/907.
    public let summary: String?

    /// `info.releasedAt`, ISO `yyyy-MM-dd`, kept as a String because it is a sort key and never a
    /// date calculation. **3 of the 333 captured generation ids lack it**
    /// (`google/gemini-3-1-flash-lite-image`, `google/gemini-3.1-flash-lite-image`,
    /// `google/gemini-omni-flash-preview`), which is why the ordering below defines a fallback.
    public let releasedAt: String?

    /// `info.isHottest` — the vendor's own recommended set. 26 of the 333 generation ids carry it
    /// (14 video, 12 image), which is what makes a "Recommended" group vendor data rather than
    /// editorial judgement.
    public let isRecommended: Bool

    public init(id: String,
                aliases: [String] = [],
                task: CreateTask,
                displayName: String,
                developer: String = "",
                summary: String? = nil,
                releasedAt: String? = nil,
                isRecommended: Bool = false) {
        self.id = id
        self.aliases = aliases
        self.task = task
        self.displayName = displayName
        self.developer = developer
        self.summary = summary
        self.releasedAt = releasedAt
        self.isRecommended = isRecommended
    }

    /// Every image or video model in a `/models` response, one row per id.
    ///
    /// Three things happen here and all three matter:
    ///
    /// 1. **Grouping.** 91 of the 762 captured ids are served on more than one endpoint family, 11
    ///    of them generation models. `response.data.map(\.id)` therefore emits those ids twice, and
    ///    that is the duplicate-identity bug in the image picker. Grouping by lowercased id ends it
    ///    at the boundary, before any view can see it.
    /// 2. **Classification over the union of families**, via `AIMLEndpoints.wireTask`. A model
    ///    served on both `chat-completions` and `image-generations` is an image model.
    /// 3. **Picking the right `info` block.** The same id carries different names on different
    ///    families (`"Gemini 2.5 Flash Image"` on `image-generations`, `"Nano Banana (Gemini 2.5
    ///    Flash Image)"` on `chat-completions`). `AIMLEndpoints.infoPreferenceOrder` decides, then
    ///    the lexicographically smallest `type` breaks ties — so the answer never depends on the
    ///    order entries happen to appear in the JSON.
    ///
    /// Non-generation entries are dropped, not "unclassified": 569 of 907 captured entries are
    /// chat, responses, messages, batches, TTS, STT, embeddings, audio or OCR models, and a model
    /// picker that offers them is wrong.
    public static func generationModels(
        from response: AIMLEndpoints.ModelsResponse
    ) -> [ServedModel] {
        var families: [String: Set<String>] = [:]
        var aliasesByID: [String: Set<String>] = [:]
        var bestInfo: [String: (rank: Int, type: String, info: AIMLEndpoints.ModelEntry.Info)] = [:]

        for entry in response.data {
            let key = entry.id.lowercased()
            let type = entry.type ?? ""
            families[key, default: []].insert(type)
            for alias in entry.aliases ?? [] {
                aliasesByID[key, default: []].insert(alias.lowercased())
            }
            if let info = entry.info {
                let rank = AIMLEndpoints.infoPreferenceOrder.firstIndex(of: type)
                    ?? AIMLEndpoints.infoPreferenceOrder.count
                if let current = bestInfo[key], (current.rank, current.type) <= (rank, type) {
                    continue
                }
                bestInfo[key] = (rank: rank, type: type, info: info)
            }
        }

        var out: [ServedModel] = []
        out.reserveCapacity(families.count)
        for (id, types) in families {
            let wireTask = AIMLEndpoints.wireTask(forEndpointFamilies: types)
            guard let task = AIMLEndpoints.createTask(for: wireTask) else { continue }
            let info = bestInfo[id]?.info
            out.append(ServedModel(
                id: id,
                aliases: (aliasesByID[id] ?? []).sorted(),
                task: task,
                displayName: nonEmpty(info?.name) ?? id,
                developer: nonEmpty(info?.developer) ?? "",
                summary: nonEmpty(info?.description),
                releasedAt: nonEmpty(info?.releasedAt),
                isRecommended: info?.isHottest ?? false))
        }
        return out.sorted { $0.id < $1.id }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }
}
