import SwiftUI
import GenStationCore

/// Display recorded charges only; absent billing must not look like a free generation.
struct HistoryCostLabel: View {
    let item: HistoryItem
    var body: some View {
        if let cost = item.costUSD, cost.isFinite, cost >= 0 {
            Text("Provider-reported cost: \(String(format: "$%.4f", cost))")
                .font(.caption).foregroundStyle(.secondary)
                .help("Reported for this generation; not independently reconciled with your provider invoice.")
        } else {
            Text("Cost unavailable")
                .font(.caption).foregroundStyle(.secondary)
                .help("No usable charge was recorded. This does not mean the generation was free.")
        }
    }
}
