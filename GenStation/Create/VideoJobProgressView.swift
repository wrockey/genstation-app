// VideoJobProgressView.swift
// Honest progress for remote video jobs: elapsed time + per-model typical
// range (registry metadata) + latest provider status. Replaces the fabricated
// pollCount/60 percent bar (WS-3 stage 3). Shared by the response area,
// LoadingView, and the Jobs panel rows.
import SwiftUI
import GenStationCore

enum VideoJobFormat {
    /// "1:42"
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "2–5 min"
    static func typicalRange(_ range: ClosedRange<TimeInterval>) -> String {
        "\(Int(range.lowerBound / 60))–\(Int(range.upperBound / 60)) min"
    }

    /// Last path component of a model id ("alibaba/wan-2-6-t2v" -> "wan-2-6-t2v")
    static func shortModelName(_ id: String) -> String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    /// "1:42 elapsed · wan-2-6-t2v usually takes 2–6 min · status: generating"
    /// Without a catalog estimate the line degrades to elapsed + status. That now also covers
    /// unregistered ids: `Catalog.model(for:)` returns nil for an id the catalog does not know,
    /// where the old token table would guess from a substring.
    static func progressLine(job: VideoJob, now: Date) -> String {
        var parts = ["\(elapsed(now.timeIntervalSince(job.startedAt ?? job.createdAt))) elapsed"]
        if let range = Catalog.model(for: job.modelId)?.typicalWallClock {
            parts.append("\(shortModelName(job.modelId)) usually takes \(typicalRange(range))")
        }
        if let status = job.providerStatus {
            parts.append("status: \(status.wireValue)")
        } else if job.state == .preparing {
            parts.append("preparing…")
        } else if job.state == .queued {
            parts.append("waiting for a slot")
        } else {
            parts.append("submitting…")
        }
        return parts.joined(separator: " · ")
    }
}

/// One line per active remote video job; renders nothing when the queue is idle.
struct VideoJobProgressView: View {
    @ObservedObject var queue: JobQueue

    var body: some View {
        let active = queue.jobs.filter { $0.kind == .generation && !$0.state.isFinished }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(active) { job in
                    TimelineView(.periodic(from: job.createdAt, by: 1)) { context in
                        Text(VideoJobFormat.progressLine(job: job, now: context.date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(DS.Radius.card)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
