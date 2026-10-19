// ModelBrowserView.swift
// The AI/ML model browser's CONTENT (design § 3.8).
//
// **Container-agnostic by rule.** It takes a catalog and returns a selection. It owns no
// navigation, has no `dismiss`, no `NavigationStack`, no toolbar, no frame and no `AppState` — it
// takes values and two closures. Stage 5 re-hosts it in a `NavigationSplitView` column without
// changing a line here. If this view ever needs to know how it is presented, that is the signal it
// has drifted into Stage 5, and the change belongs there.
//
// Every filter, sort, group and badge decision lives in `GenStationCore.ModelBrowser` and is
// unit-tested in `ModelBrowserTests`. What is left in this file is rendering.

import SwiftUI
import GenStationCore

struct ModelBrowserView: View {
    let task: CreateTask
    let served: [ServedModel]
    let showAll: Bool
    let favorites: [String]
    let recents: [String]
    let selectedID: String
    /// Keyed by canonical model id, from `HistoryState.observedCostByModel`. Empty is a valid and
    /// common state — a fresh install, or every model the user has never run.
    let observedCost: [String: ObservedCost]
    let onSelect: (String) -> Void
    let onToggleFavorite: (String) -> Void

    @State private var search = ""

    private var sections: [ModelBrowser.Section] {
        ModelBrowser.sections(task: task,
                              served: served,
                              showAll: showAll,
                              search: search,
                              favorites: favorites,
                              recents: recents)
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section("\(section.title) (\(section.rows.count))") {
                    ForEach(section.rows) { row($0) }
                }
            }
        }
        .searchable(text: $search, prompt: "Search models")
    }

    // No `id: \.self` anywhere: `ModelBrowser.Row` is `Identifiable` on a **unique** id, and
    // `ModelBrowserTests.testEachRowAppearsInExactlyOneSection` is what keeps it unique. The old
    // picker's `ForEach(others, id: \.self)` was handed 11 duplicated image ids.
    @ViewBuilder private func row(_ item: ModelBrowser.Row) -> some View {
        let isSelected = selectedID == item.id
        let isFav = favorites.contains(item.id)
        HStack(spacing: 10) {
            Button {
                onSelect(item.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(0.35))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.displayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            ForEach(item.badges, id: \.self) { badge in
                                badgeCapsule(badge)
                            }
                        }
                        HStack(spacing: 6) {
                            Text(item.id)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let cost = costLabel(item.id) {
                                Text("· \(cost)")
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            Button {
                onToggleFavorite(item.id)
            } label: {
                Image(systemName: isFav ? "star.fill" : "star")
                    .foregroundStyle(isFav ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isFav ? "Remove from favorites" : "Add to favorites")
        }
    }

    // Same capsule the Gemini menu's "NEW" badge already uses
    // (ConfigurationSection.swift:370-375), so the two surfaces do not invent two badge styles.
    @ViewBuilder private func badgeCapsule(_ badge: ModelBrowser.Badge) -> some View {
        Text(badge.label)
            .font(.caption2).bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint(badge).opacity(0.2))
            .cornerRadius(4)
            .help(badge.help)
    }

    private func tint(_ badge: ModelBrowser.Badge) -> Color {
        switch badge {
        case .provider: return .blue
        case .superseded: return .orange
        case .unregistered: return .gray
        case .knownIssue: return .orange
        }
    }

    /// "avg $0.0412 · 7 runs", or nil for a model this user has never paid for. Nothing is shown
    /// rather than a zero or an estimate: the API publishes no prices, and inventing one is the
    /// thing design § 4.5 exists to refuse. `$%.4f` matches HistoryItemFullView.swift:1056, so the
    /// per-item figure and the average are formatted the same way.
    private func costLabel(_ id: String) -> String? {
        guard let observed = ObservedCostIndex.cost(for: id, in: observedCost),
              let mean = observed.meanUSD else { return nil }
        let runs = observed.sampleCount == 1 ? "1 run" : "\(observed.sampleCount) runs"
        return String(format: "avg $%.4f · %@", mean, runs)
    }
}
