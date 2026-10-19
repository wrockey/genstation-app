import Foundation

public enum JobRecovery {
    public enum Action: Equatable { case none, download, checkStatus, generateAgain }
    public static func action(assetURL: String?, fileExists: Bool, jobID: String?, pollingEndpoint: String?, status: GenerationStatus?, hasSubmission: Bool) -> Action {
        if let assetURL, !assetURL.isEmpty, !fileExists { return .download }
        if !fileExists, let jobID, !jobID.isEmpty, let pollingEndpoint, !pollingEndpoint.isEmpty,
           status != .completed && status != .expired { return .checkStatus }
        if hasSubmission && (status?.needsAttention ?? false) { return .generateAgain }
        return .none
    }
}
