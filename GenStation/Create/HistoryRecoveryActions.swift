import SwiftUI
import GenStationCore

struct HistoryRecoveryActions: View {
    let item: HistoryItem
    @EnvironmentObject var appState: AppState
    private var action: JobRecovery.Action {
        JobRecovery.action(assetURL: item.videoUrl ?? item.sourceAssetURL,
            fileExists: item.fileExists(appState: appState), jobID: item.jobId,
            pollingEndpoint: item.pollingEndpoint, status: item.status, hasSubmission: JobQueue.canRetry(item))
    }
    var body: some View {
        HStack {
            switch action {
            case .download:
                Button("Download again") { appState.jobQueue.redownload(item) }
            case .checkStatus:
                Button("Check status") { Task { await appState.jobQueue.resumePendingJobs([item]) } }
            case .generateAgain:
                Button("Generate again…") { appState.presentedModal = .jobs; appState.jobQueue.retry(item) }
            case .none: EmptyView()
            }
            if (action == .checkStatus || action == .download) && JobQueue.canRetry(item) && item.status?.isInProgress != true {
                Menu("More") {
                    Button("Generate again…") { appState.presentedModal = .jobs; appState.jobQueue.retry(item) }
                    Button("Provider settings") { appState.presentedModal = .apiKeySetup }
                }
            }
        }.disabled(appState.jobQueue.activeJob(forHistoryItem: item.id) != nil)
    }
}
