import Foundation

/// The browse surface's logic (design § 3.8). Everything about *what* is shown, in what order, in
/// what group, with what badges. Nothing about *how* — no `Color`, no `Image`, no SwiftUI type, and
/// no opinion about sheets, columns or navigation.
///
/// The app-side view is a renderer over these values. That split is what lets Stage 5 rebuild the
/// chrome without rebuilding any of this, and it is what makes the browse surface testable at all:
/// before this file existed, the video/image split was a 35-token substring heuristic inside a
/// SwiftUI view's private method, reachable by no test in the repository.
public enum ModelBrowser {

    // MARK: - Badges

    /// A per-row signal, as **data**. `CatalogGroup`'s rule applies for the same reason: the
    /// package must not name a UI framework (`PackageBoundaryTests`), so a badge is an enum plus
    /// two strings and the app decides what it looks like.
    ///
    /// There is deliberately no `.recommended` badge — the Recommended *section* already says it,
    /// and a badge repeating its own section heading is noise.
    public enum Badge: Sendable, Hashable {
        /// Only present when the offered list spans more than one provider. In Stage 3 the AI/ML
        /// picker offers one, so it is suppressed; Stage 5's cross-provider browser turns it on
        /// with no change here.
        case provider(String)
        /// `Lifecycle.superseded` — still served, still selectable, newer thing exists.
        case superseded
        /// `CatalogModel.isRegistered == false`: GenStation has no descriptor table for this model.
        /// The row stays selectable. This is the per-row form of a signal that is currently global
        /// and therefore useless for deciding about any particular model.
        case unregistered
        /// `CatalogModel.knownIssue`: the vendor currently serves this model broken, per a live
        /// probe. The row stays selectable — the vendor may fix it silently, and history re-run
        /// must keep resolving the model either way.
        case knownIssue(String)

        public var label: String {
            switch self {
            case .provider(let name): return name
            case .superseded: return "Superseded"
            case .unregistered: return "No preset"
            case .knownIssue: return "Upstream issue"
            }
        }

        public var help: String {
            switch self {
            case .provider(let name):
                return "Served by \(name)."
            case .superseded:
                return "The vendor has released a newer model. This one still works and still runs "
                    + "from history."
            case .unregistered:
                return "GenStation has no parameter preset for this model. It will post a minimal "
                    + "request, and you may need to edit the JSON by hand."
            case .knownIssue(let text):
                return text
            }
        }
    }

    // MARK: - Rows and sections

    public struct Row: Sendable, Hashable, Identifiable {
        /// The id the picker stores in `selectedAIMLModel`. **Always catalog-canonical when the
        /// catalog knows the model under any spelling**, so no call site has to canonicalize a
        /// selection ever again.
        public let id: String
        public let displayName: String
        public let subtitle: String?
        public let family: String
        public let provider: Provider
        public let releasedAt: String?
        public let isRegistered: Bool
        /// nil for an unregistered model — we do not know its lifecycle, which is precisely why
        /// `CatalogModel.isRegistered` is a separate field from `lifecycle` (contract).
        public let lifecycle: Lifecycle?
        public let isRecommended: Bool
        public let badges: [Badge]

        public init(id: String,
                    displayName: String,
                    subtitle: String? = nil,
                    family: String,
                    provider: Provider,
                    releasedAt: String? = nil,
                    isRegistered: Bool,
                    lifecycle: Lifecycle? = nil,
                    isRecommended: Bool = false,
                    badges: [Badge] = []) {
            self.id = id
            self.displayName = displayName
            self.subtitle = subtitle
            self.family = family
            self.provider = provider
            self.releasedAt = releasedAt
            self.isRegistered = isRegistered
            self.lifecycle = lifecycle
            self.isRecommended = isRecommended
            self.badges = badges
        }
    }

    public struct Section: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable, CaseIterable {
            case favorites, recent, recommended, family
        }
        public let kind: Kind
        public let title: String
        public let rows: [Row]
        public var id: String { "\(kind.rawValue)|\(title)" }

        public init(kind: Kind, title: String, rows: [Row]) {
            self.kind = kind
            self.title = title
            self.rows = rows
        }
    }

    // MARK: - Rows

    /// Every model the user may pick, deduped, canonicalized and ordered.
    ///
    /// `showAll` is retained for settings compatibility but cannot bypass the release policy.
    /// AI/ML rows must be both supported by this release and present in the provider's model list.
    public static func rows(task: CreateTask,
                            served: [ServedModel],
                            showAll: Bool,
                            providers: Set<Provider> = [.aimlapi]) -> [Row] {
        // `selectable(task:)` already drops `.dead` and groups by family (spec § 3.6 invariant 4),
        // so lifecycle filtering is inherited rather than reimplemented here.
        let catalogModels = Catalog.selectable(task: task)
            .flatMap(\.models)
            .filter { providers.contains($0.provider) }
            .filter { $0.provider != .aimlapi || ReleaseModelPolicy.allows($0.id, task: task) }

        // Served id -> the canonical catalog id it names, when the catalog knows it at all.
        var servedByCanonical: [String: ServedModel] = [:]
        for model in served where model.task == task {
            guard let canonical = catalogID(for: model) else {
                continue
            }
            if let existing = servedByCanonical[canonical] {
                servedByCanonical[canonical] = preferred(existing, model, canonical: canonical)
            } else {
                servedByCanonical[canonical] = model
            }
        }

        let includeProvider = Set(catalogModels.map(\.provider)).count > 1
        var out: [Row] = []

        for model in catalogModels {
            let servedModel = servedByCanonical[model.id]
            // The live-served gate applies to AI/ML rows only. Grok's two rows are native: there is
            // no `/models` entry for them under any spelling, so requiring one would hide them.
            if model.provider == .aimlapi && servedModel == nil { continue }
            out.append(Row(
                id: model.id,
                displayName: model.displayName,
                subtitle: servedModel?.summary,
                family: model.family,
                provider: model.provider,
                releasedAt: servedModel?.releasedAt,
                isRegistered: true,
                lifecycle: model.lifecycle,
                isRecommended: model.provider == .aimlapi,
                badges: badges(provider: model.provider,
                               lifecycle: model.lifecycle,
                               isRegistered: true,
                               knownIssue: model.knownIssue,
                               includeProvider: includeProvider)))
        }

        return out.sorted(by: isOrderedBefore)
    }

    public static func selectableIDs(task: CreateTask,
                                     served: [ServedModel],
                                     showAll: Bool,
                                     providers: Set<Provider> = [.aimlapi]) -> [String] {
        rows(task: task, served: served, showAll: showAll, providers: providers).map(\.id)
    }

    // MARK: - Sections

    /// The browse surface, sectioned. **Every row appears in exactly one section**, in this
    /// priority: Favorites, Recent, Recommended, then its family.
    ///
    /// One section per row is a deliberate choice, not an oversight. It means a flattened section
    /// list has unique ids, which is the property the old picker violated — `ForEach(others,
    /// id: \.self)` was handed a list containing 11 duplicated image ids. The cost is that a
    /// favourited model is not *also* shown under its family; the existing picker already made that
    /// trade for Favorites and Recent, and this extends it to Recommended.
    public static func sections(task: CreateTask,
                                served: [ServedModel],
                                showAll: Bool,
                                search: String,
                                favorites: [String],
                                recents: [String],
                                providers: Set<Provider> = [.aimlapi]) -> [Section] {
        let all = rows(task: task, served: served, showAll: showAll, providers: providers)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = query.isEmpty ? all : all.filter { matches($0, query) }
        let byID = Dictionary(matching.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var used: Set<String> = []
        var out: [Section] = []

        // Favourites and recents are user-ordered, so they keep their own order rather than the
        // release order. They are canonicalized on load by Task 19, so they key straight in.
        func take(_ ids: [String]) -> [Row] {
            var taken: [Row] = []
            for id in ids where !used.contains(id) {
                guard let row = byID[id] else { continue }
                used.insert(id)
                taken.append(row)
            }
            return taken
        }

        let favoriteRows = take(favorites)
        if !favoriteRows.isEmpty {
            out.append(Section(kind: .favorites, title: "★ Favorites", rows: favoriteRows))
        }
        let recentRows = take(recents)
        if !recentRows.isEmpty {
            out.append(Section(kind: .recent, title: "Recent", rows: recentRows))
        }

        let recommended = matching.filter { !used.contains($0.id) && $0.isRecommended }
        if !recommended.isEmpty {
            used.formUnion(recommended.map(\.id))
            out.append(Section(kind: .recommended, title: "Recommended", rows: recommended))
        }

        var byFamily: [String: [Row]] = [:]
        for row in matching where !used.contains(row.id) {
            byFamily[row.family.isEmpty ? "Other" : row.family, default: []].append(row)
        }
        for family in byFamily.keys.sorted() {
            out.append(Section(kind: .family, title: family, rows: byFamily[family] ?? []))
        }
        return out
    }

    // MARK: - The seams the tests reach for

    /// The badge rule, exposed to the test target so it can be exercised against hand-built inputs
    /// rather than only against whatever lifecycles the real catalog happens to carry today.
    static func badges(provider: Provider,
                       lifecycle: Lifecycle?,
                       isRegistered: Bool,
                       knownIssue: String?,
                       includeProvider: Bool) -> [Badge] {
        var out: [Badge] = []
        if includeProvider { out.append(.provider(provider.displayName)) }
        if lifecycle == .superseded { out.append(.superseded) }
        if let knownIssue { out.append(.knownIssue(knownIssue)) }
        if !isRegistered { out.append(.unregistered) }
        return out
    }

    /// Newest first. **The defined fallback for a missing `releasedAt` is the empty string**, which
    /// sorts after every real ISO date, so the 3 generation entries lacking one land at the end of
    /// their section instead of at an arbitrary position. Ties break on display name, then on id,
    /// so the order is total and never depends on input order.
    static func isOrderedBefore(_ a: Row, _ b: Row) -> Bool {
        let aDate = a.releasedAt ?? ""
        let bDate = b.releasedAt ?? ""
        if aDate != bDate { return aDate > bDate }
        let aName = a.displayName.lowercased()
        let bName = b.displayName.lowercased()
        if aName != bName { return aName < bName }
        return a.id < b.id
    }

    static func matches(_ row: Row, _ query: String) -> Bool {
        row.id.lowercased().contains(query)
            || row.displayName.lowercased().contains(query)
            || row.family.lowercased().contains(query)
    }

    /// The canonical catalog id a served entry names, through its own id or any of its aliases.
    ///
    /// This is the job `AppState.canonicalAIMLModelID(for:)` used to do one selection at a time,
    /// against the API's alias map, at pick time. It now happens once, for the whole list, against
    /// the catalog's alias index — which is why Task 20's `Catalog.canonicalID(for: id) ?? id` at
    /// the pick site becomes unnecessary in Step 7.
    private static func catalogID(for model: ServedModel) -> String? {
        if let canonical = Catalog.canonicalID(for: model.id) { return canonical }
        for alias in model.aliases {
            if let canonical = Catalog.canonicalID(for: alias) { return canonical }
        }
        return nil
    }

    /// Two served ids can name the same catalog row — `google/gemini-3-pro-image-preview` is both
    /// its own served id **and** an alias of `google/gemini-3-pro-image`; 8 captured generation
    /// spellings are in that position. Prefer the entry whose own id is the canonical, else the
    /// lexicographically smaller id, so the winner never depends on JSON ordering.
    private static func preferred(_ a: ServedModel,
                                  _ b: ServedModel,
                                  canonical: String) -> ServedModel {
        if a.id == canonical { return a }
        if b.id == canonical { return b }
        return a.id <= b.id ? a : b
    }
}
