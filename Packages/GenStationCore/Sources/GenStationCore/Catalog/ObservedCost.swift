import Foundation

/// What a model has actually cost this user, and over how many runs.
///
/// Deliberately not an estimate. The spec's original plan was a `priceEstimate` table seeded from
/// an audit document that turned out to contain zero price data, and the captured `/models`
/// response publishes no pricing field either — so an estimate would be hand-authored, unfalsifiable
/// and would rot exactly the way the four `unverified:` descriptor tables did. An observed figure
/// carries its own authority, and its sample size says how much.
public struct ObservedCost: Sendable, Hashable {
    /// Sum of the recorded `usd_spent` values. Only runs that actually recorded one contribute.
    public let totalUSD: Double
    /// How many runs contributed. **Never** the number of times the model was used — a run whose
    /// cost the provider did not report is not a sample, and counting it would understate the mean.
    public let sampleCount: Int

    public init(totalUSD: Double, sampleCount: Int) {
        self.totalUSD = totalUSD
        self.sampleCount = sampleCount
    }

    /// nil when there are no samples. Optional rather than a guarded division so no caller can
    /// render "$0.0000" from an empty set and imply the model is free.
    public var meanUSD: Double? {
        sampleCount > 0 ? totalUSD / Double(sampleCount) : nil
    }
}

/// One history record reduced to what the cost index needs.
public struct CostSample: Sendable, Hashable {
    public let modelID: String?
    public let costUSD: Double?

    public init(modelID: String?, costUSD: Double?) {
        self.modelID = modelID
        self.costUSD = costUSD
    }
}

/// Builds the per-model cost index.
///
/// **Canonical keys.** `HistoryItem.modelUsed` keeps whatever spelling the generation was made
/// under, forever — `history_v2.json` is never rewritten (design § 4.3), so after the 209 → 122
/// collapse most stored spellings are aliases. Every key here goes through `Catalog.canonicalID`,
/// which is what makes one model's history one row.
public enum ObservedCostIndex {

    /// The key a model id folds onto: its canonical id, or its lowercased self when the catalog has
    /// never heard of it (an advanced-mode pick).
    public static func key(for modelID: String) -> String {
        Catalog.canonicalID(for: modelID) ?? modelID.lowercased()
    }

    /// Walks the in-memory history tree once, accumulating straight into the result.
    ///
    /// Deliberately not `entries.flatMap(\.allItems)`: `HistoryEntry.allItems` materialises an array
    /// of every `HistoryItem` — 22 fields each, prompts and response text included — and this runs
    /// on every history change. Nothing here reads `history_v2.json`; the caller passes the array
    /// that was decoded once at launch.
    public static func build(from entries: [HistoryEntry]) -> [String: ObservedCost] {
        var totals: [String: (total: Double, count: Int)] = [:]
        walk(entries, into: &totals)
        return finalize(totals)
    }

    public static func build(fromSamples samples: [CostSample]) -> [String: ObservedCost] {
        var totals: [String: (total: Double, count: Int)] = [:]
        for sample in samples {
            accumulate(modelID: sample.modelID, costUSD: sample.costUSD, into: &totals)
        }
        return finalize(totals)
    }

    /// Looks a model up through the same key function the index was built with, so a caller holding
    /// an alias spelling cannot silently miss.
    public static func cost(for modelID: String,
                            in index: [String: ObservedCost]) -> ObservedCost? {
        index[key(for: modelID)]
    }

    private static func walk(_ entries: [HistoryEntry],
                             into totals: inout [String: (total: Double, count: Int)]) {
        for entry in entries {
            switch entry {
            case .item(let item):
                accumulate(modelID: item.modelUsed, costUSD: item.costUSD, into: &totals)
            case .folder(let folder):
                walk(folder.children, into: &totals)
            }
        }
    }

    private static func accumulate(modelID: String?,
                                   costUSD: Double?,
                                   into totals: inout [String: (total: Double, count: Int)]) {
        guard let modelID = modelID, !modelID.isEmpty, let cost = costUSD else { return }
        let key = key(for: modelID)
        var running = totals[key] ?? (total: 0, count: 0)
        running.total += cost
        running.count += 1
        totals[key] = running
    }

    private static func finalize(
        _ totals: [String: (total: Double, count: Int)]
    ) -> [String: ObservedCost] {
        var out: [String: ObservedCost] = [:]
        out.reserveCapacity(totals.count)
        for (key, running) in totals {
            out[key] = ObservedCost(totalUSD: running.total, sampleCount: running.count)
        }
        return out
    }
}
