import Foundation

/// The model store. A namespace enum, never instantiated.
///
/// Two maps, not one. Keeping the alias index separate — rather than searching each row's
/// `aliases` array — is what makes resolution O(1) and makes "the canonical set and the alias set
/// are disjoint" a set operation rather than a scan. Everything here is a stored `let`, so `all`
/// no longer re-invokes 209 closures on every access the way `ModelRegistry.allModels`
/// (`ModelRegistry.swift:2096-2100`) did.
// MARK: - Canonical spelling
//
// Stage 3 Task 11. 209 registered spellings, 122 models, 87 aliases. The rule that picked the
// canonical id of each group, applied by tools/stage3-catalog-gen/collapse_aliases.py:
//
//   The fully-qualified `vendor/model` spelling wins. Ties break on the order of the `reg([...])`
//   literal. A group with no `/` in any id takes its only id (all five such groups are singletons).
//
// Not taste. Two call sites compare a catalog id against the ids the API serves as ENTRY ids —
// `MCPService.swift:643` (`!live.contains(model.id)` -> model_unavailable) and
// `ConfigurationSection.swift:1574-1578` (`registryIDs.intersection(apiModels)`). Six ids exist on
// the wire only inside some entry's `aliases` array and never as an entry id: `gpt-image-1`,
// `gpt-image-1.5`, `gpt-image-2`, `imagen-4.0-generate-001`, `sora-2-t2v`, `veo2`. Making one of
// those the canonical spelling would have MCP reject its own advertised model. All six remain
// resolvable as aliases.
//
// KNOWN LIMIT, carried on the live-test checklist and handed to Task 22. A `reg()` group is a
// builder-sharing group, not an identity group: the registry grouped ids that happen to have the
// same capabilities, and the spec says so itself (§ 3.4, on `:1813` — "two families in one
// builder"). `collapse_aliases.py --report-suspect-groups` flags 26 groups where a demoted id is
// not a spelling of its canonical modulo punctuation. Most are naming-scheme variants of one
// product; some name a genuinely different product. Task 22 has the live `/models` fixture, which
// decides it mechanically: an id the endpoint serves as its own entry id is its own model and must
// be promoted back to a canonical row.
public enum Catalog {

    /// Canonical rows, keyed by canonical id. 122 models, collapsed from 209 registered spellings
    /// in Task 11. Grok's 2 rows join in Task 14.
    private static let canonical: [String: CatalogModel] = {
        var out: [String: CatalogModel] = [:]
        // Cross-provider from here on: the AI/ML rows plus the native Grok rows (Task 14).
        // `selectable(task:)` therefore returns rows from more than one provider, and every
        // picker must filter by provider.
        for model in AIMLRegisteredModels.all + Catalog.grokRows { out[model.id] = model }
        return out
    }()

    /// Alias spelling -> canonical id. 87 entries. Built from the rows rather than written twice,
    /// so an alias cannot exist in the index without existing on a model.
    private static let aliasIndex: [String: String] = {
        var out: [String: String] = [:]
        // Excludes `Catalog.grokRows`, unlike `canonical` above. Safe only because both Grok rows
        // carry `aliases: []` (Task 14) — so there is nothing of theirs to index. If a Grok row ever
        // gains an alias, it must be added to this loop too, or `Catalog.canonicalID` silently
        // returns nil for it instead of resolving it.
        for model in AIMLRegisteredModels.all {
            for alias in model.aliases { out[alias] = model.id }
        }
        return out
    }()

    /// Sorted once, not per access — `selectable(task:)` reads `all` and would otherwise re-sort
    /// on every call. Derived from `canonical` rather than from `AIMLRegisteredModels.all` so
    /// `all` and `model(for:)` cannot disagree about what is in the store.
    private static let sortedAll: [CatalogModel] = canonical.values.sorted { $0.id < $1.id }

    /// Alias or canonical id -> canonical id. Nil when the id is unknown to the catalog.
    public static func canonicalID(for id: String) -> String? {
        let key = id.lowercased()
        if canonical[key] != nil { return key }
        return aliasIndex[key]
    }

    /// Honest nil for an unknown id. Resolves aliases.
    ///
    /// **Returns `.dead` and `.superseded` models on purpose** — lifecycle hides a model from
    /// pickers, it must never break history re-run. This is where `enhancedModelFor(id:)`'s
    /// `Optional` stopped telling the truth: it returned nil only for a nil or empty id
    /// (`ModelRegistry.swift:2044-2046`) and synthesized unconditionally otherwise, which made
    /// nine of its ten call sites' `else` branches dead code.
    public static func model(for id: String) -> CatalogModel? {
        guard let key = canonicalID(for: id) else { return nil }
        return canonical[key]
    }

    /// Canonical rows, sorted by id. Never includes synthesized rows.
    public static var all: [CatalogModel] { sortedAll }

    /// Best-effort synthesis for an unregistered API id. Always returns a value, always with
    /// `isRegistered == false`. Never called implicitly — a caller opts in by name.
    ///
    /// Reproduces `ModelRegistry.swift:2052-2082` exactly, including its quirks: the token match
    /// is on the *lowercased* id, `provider` is the first `/`-separated component and becomes the
    /// whole id when there is no `/`, and a video id gets the per-provider synthesized path that
    /// `RegistryEndpointTests:117-125` proves disagrees with the registry for 91 of 129 video ids.
    /// Preserving that is the point of Phase A; changing it belongs to whichever task decides to.
    public static func synthesized(for id: String) -> CatalogModel {
        let lowerID = id.lowercased()
        let isVideoModel = lowerID.contains("video") || lowerID.contains("i2v")
            || lowerID.contains("t2v")
        let isI2I = lowerID.contains("edit") || lowerID.contains("image-to-image")
            || lowerID.contains("i2i") || (isVideoModel && lowerID.contains("i2v"))
        let requiresInputImage = lowerID.contains("edit") || lowerID.contains("image-to-image")
            || lowerID.contains("i2i")
        let provider = lowerID.split(separator: "/").first.map(String.init) ?? "unknown"

        let generationEndpoint: String
        let pollingEndpoint: String?
        if isVideoModel {
            generationEndpoint = AIMLEndpoints.providerVideoGeneration(provider: provider)
            pollingEndpoint = AIMLEndpoints.providerVideoGenerationPoll(provider: provider)
        } else {
            generationEndpoint = AIMLEndpoints.imageGeneration
            pollingEndpoint = nil
        }

        return CatalogModel(
            id: lowerID,
            aliases: [],
            provider: .aimlapi,
            displayName: lowerID,
            family: "",
            lifecycle: .current,
            typicalWallClock: nil,
            isRegistered: false,
            task: CreateTask(isVideo: isVideoModel),
            isI2I: isI2I,
            requiresInputImage: requiresInputImage,
            supportsMask: false,
            maxInputImages: isI2I ? 1 : 0,
            imageInputParam: isI2I ? "image_urls" : "",
            secondImageParam: nil,
            acceptsMultiImages: false,
            acceptsBase64: true,
            acceptsPublicURL: true,
            acceptsBinary: false,
            generationEndpoint: generationEndpoint,
            pollingEndpoint: pollingEndpoint)
    }

    /// `model(for:) ?? synthesized(for:)`. For call sites that genuinely accept either — and only
    /// those. Unlike `enhancedModelFor(id:)` this never returns nil, including for `""`.
    public static func resolve(_ id: String) -> CatalogModel {
        model(for: id) ?? synthesized(for: id)
    }

    /// The selectable surface: `.dead` filtered out, everything else grouped by `family`, groups
    /// sorted by family name, models sorted by id. Spec § 3.6 invariant 4.
    ///
    /// `.superseded` is **kept**. Lifecycle is a recommendation, not a revocation: a model the
    /// API still serves stays pickable, and only a model the API no longer serves disappears from
    /// the list while remaining resolvable through `model(for:)` forever.
    public static func selectable(task: CreateTask) -> [CatalogGroup] {
        selectable(task: task, from: all)
    }

    /// The testable seam. Internal, so `@testable import` reaches it and nothing outside the
    /// package can bypass `all`. It exists because the invariants above must be provable against
    /// hand-built rows — the real catalog carries no `.dead` model and one provisional family
    /// until Tasks 12 and 22, and an untestable invariant is not an invariant.
    static func selectable(task: CreateTask, from models: [CatalogModel]) -> [CatalogGroup] {
        var byFamily: [String: [CatalogModel]] = [:]
        for model in models where model.task == task && model.lifecycle != .dead {
            byFamily[model.family, default: []].append(model)
        }
        return byFamily.keys.sorted().map { family in
            CatalogGroup(family: family, models: byFamily[family]!.sorted { $0.id < $1.id })
        }
    }
}

extension Catalog {

    /// A provider's live model list merged with our presentation overrides.
    ///
    /// **Nothing calls this in Stage 3.** It exists because Gemini's list is a live
    /// `v1beta/models` fetch and therefore cannot be static rows, and because that fetch path holds
    /// two of the four silent healers the design consolidates (`GenStationApp.swift:248-256` and
    /// `:526-532`). Wiring it sits on top of Task 20's consolidated healer and belongs to Stage 5;
    /// landing it now means that task changes only the caller.
    ///
    /// **This does not filter.** `fetchAvailableGeminiModels` filters three times before it gets
    /// here (`:476-500`): `canGenerateContent`, an image-token allowlist and a substring denylist.
    /// The first is unrepresentable — `LiveModelRow` carries no `supportedGenerationMethods` — and
    /// the other two are Gemini policy, not catalog data. Filtering stays at the fetch site.
    ///
    /// Dedupe reproduces `:502-518` exactly: group by the **live** display name, and inside a group
    /// prefer the provider's priority list, else the shortest id. The override is applied *after*
    /// dedupe, so renaming a model cannot change which duplicate survives.
    ///
    /// The sort is the one deliberate difference from today. `:520` sorts on the live display name
    /// — the string the menu does **not** show for the two overridden Gemini rows — and a
    /// single-field `<` is not a total order, so equal names come out in whatever order the
    /// dictionary produced. Here the sort is on the final display name with the id as tiebreak.
    public static func merge(live: [LiveModelRow], provider: Provider) -> [CatalogModel] {
        // No capabilities template for this provider yet (Stage 3 only ever merges Gemini) — return
        // no rows rather than fabricate one. `capabilities(for:)`'s doc explains why silence beats a
        // structurally-valid-but-unusable `CatalogModel`.
        guard let caps = capabilities(for: provider) else { return [] }
        let overrides = presentationOverrides(for: provider)
        let priority = priorityIDs(for: provider)

        let deduped = Dictionary(grouping: live, by: { $0.displayName ?? $0.id })
            .compactMap { _, group -> LiveModelRow? in
                for id in priority {
                    if let match = group.first(where: { $0.id == id }) { return match }
                }
                // Shortest id = newest, per GenStationApp.swift:517-518. Length alone is not a
                // total order, so the id breaks the tie and keeps this deterministic.
                return group.min { ($0.id.count, $0.id) < ($1.id.count, $1.id) }
            }

        return deduped
            .map { row -> CatalogModel in
                let override = overrides[row.id]
                return CatalogModel(
                    id: row.id,
                    aliases: [],
                    provider: provider,
                    displayName: override?.displayName ?? row.displayName ?? row.id,
                    family: override?.family ?? row.displayName ?? row.id,
                    lifecycle: .current,
                    // Every merged row is an image model today, so Task 13's invariant applies.
                    typicalWallClock: nil,
                    // A live row is a real row. `isRegistered` is false only for
                    // `synthesized(for:)` — see the contract.
                    isRegistered: true,
                    task: .image,
                    isI2I: caps.isI2I,
                    requiresInputImage: false,
                    supportsMask: false,
                    maxInputImages: caps.maxInputImages,
                    imageInputParam: caps.imageInputParam,
                    secondImageParam: nil,
                    acceptsMultiImages: caps.maxInputImages > 1,
                    acceptsBase64: caps.acceptsBase64,
                    acceptsPublicURL: false,
                    acceptsBinary: false,
                    generationEndpoint: caps.generationEndpoint,
                    pollingEndpoint: nil
                )
            }
            .sorted { ($0.displayName, $0.id) < ($1.displayName, $1.id) }
    }

    private static func presentationOverrides(for provider: Provider) -> [String: PresentationOverride] {
        switch provider {
        case .gemini: return geminiOverrides
        case .grok, .aimlapi, .comfyUI: return [:]
        }
    }

    /// Reproduces the `priorityOrder` array at `GenStationApp.swift:506-511`. Only Gemini has one.
    private static func priorityIDs(for provider: Provider) -> [String] {
        switch provider {
        case .gemini:
            return ["gemini-3-pro-image",
                    "gemini-3-pro-image-preview",
                    "gemini-3.1-flash-image",
                    "gemini-2.5-flash-image"]
        case .grok, .aimlapi, .comfyUI:
            return []
        }
    }

    private struct LiveCapabilities {
        let isI2I: Bool
        let maxInputImages: Int
        let imageInputParam: String
        let acceptsBase64: Bool
        let generationEndpoint: String
    }

    /// The capability half of a merged row, which the live list does not describe. Every value here
    /// is read off working code, not guessed:
    ///
    /// - Gemini takes input images as base64 `inline_data` parts inside the request `contents`
    ///   (`ContentView+Generation.swift`), and `AppState.maxImageSlots` caps the provider at 4
    ///   (`GenStationApp.swift:2447-2448`).
    /// - `generationEndpoint` is the models collection. The per-model `:generateContent` suffix and
    ///   the `?key=` query are added by `GeminiClient.generateContentURL(model:apiKey:)`
    ///   (`GeminiClient.swift:18-25`), which is the only thing in the app that posts to Gemini.
    ///
    /// `nil` for every provider but Gemini, because Stage 3 only ever merges Gemini. **This is a
    /// refusal, not a placeholder.** It used to return a no-input-images template — `isI2I: false`,
    /// `maxInputImages: 0`, `generationEndpoint: ""` — for the other three providers: a
    /// `CatalogModel` that type-checks and reads as "a text-only model with no endpoint" instead of
    /// what it actually was, "nobody has written this provider's template yet." Nothing calls
    /// `merge` today, which is exactly why that was dangerous: the day Stage 5 wires a second live
    /// provider through it, that template becomes a real row a real picker offers, and it cannot
    /// generate — with no signal at the point of the mistake.
    ///
    /// `merge(live:provider:)` is the only caller and returns `[]` when this is nil, rather than
    /// rows built from a garbage template. Wiring a second provider means adding its case here;
    /// until then, calling `merge` for it is a documented, tested no-op.
    private static func capabilities(for provider: Provider) -> LiveCapabilities? {
        switch provider {
        case .gemini:
            return LiveCapabilities(
                isI2I: true,
                maxInputImages: 4,
                imageInputParam: "inline_data",
                acceptsBase64: true,
                generationEndpoint: GeminiClient.baseURL
                    .appendingPathComponent("models").absoluteString
            )
        case .grok, .aimlapi, .comfyUI:
            return nil
        }
    }
}
