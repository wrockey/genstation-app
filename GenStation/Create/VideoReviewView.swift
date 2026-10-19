import SwiftUI
import GenStationCore

struct VideoReview: Identifiable {
    let id: UUID
    let request: VideoJobRequest
}

struct VideoReviewModifier: ViewModifier {
    @ObservedObject var queue: JobQueue
    var enabled = true
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { enabled ? queue.pendingReview : nil }, set: { if enabled { queue.pendingReview = $0 } }), onDismiss: { queue.resolveReview(false) }) { review in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Review video generation").font(.title2.bold())
                        Text("\(review.request.provider.displayName) • \(review.request.modelId)")
                        Text(review.request.prompt)
                        Text(VideoSubmissionSummary.describe(payload: review.request.urlRequest.httpBody ?? Data()))
                        Text("Price unavailable. Your provider charges for this generation.")
                        Text("This starts a new generation and may incur another provider charge.")
                        Button("Generate video") { queue.resolveReview(true) }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel", role: .cancel) { queue.resolveReview(false) }
                    }.padding()
                }
            }.frame(minWidth: 320, minHeight: 420)
        }
    }
}
