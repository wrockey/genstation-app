// Headless orchestration over the same HTTP transport used by the GUI.
import Foundation
import GenStationCore

struct ComfyUIRunResult {
    let data: Data
    let descriptor: ComfyUIOutput
    let promptID: String
    var isVideo: Bool { descriptor.isVideo }
    var filename: String { descriptor.filename }
}

enum ComfyUIRunError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let message): return message }
    }
}

@MainActor
enum ComfyUIRunner {
    static func run(apiWorkflow: [String: Any], serverURL: URL, timeout: TimeInterval,
                    outputNodeID: String? = nil,
                    beforeSubmit: () throws -> Void = {},
                    onSubmitted: (String) throws -> Void = { _ in },
                    onOutputs: ([ComfyUIOutput]) throws -> Void = { _ in },
                    shouldContinue: () -> Bool = { true }) async throws -> ComfyUIRunResult {
        let transport = try ComfyUITransport(serverURL: serverURL.absoluteString)
        let id = try await transport.submit(apiWorkflow: apiWorkflow, clientID: UUID().uuidString,
                                           persistIntent: beforeSubmit, persistPromptID: onSubmitted)
        return try await recover(promptID: id, serverURL: serverURL, timeout: timeout,
                                 outputNodeID: outputNodeID, onOutputs: onOutputs, shouldContinue: shouldContinue)
    }

    /// Structurally GET-only; a missing history entry never causes submission.
    static func recover(promptID: String, serverURL: URL, timeout: TimeInterval,
                        outputNodeID: String? = nil,
                        onOutputs: ([ComfyUIOutput]) throws -> Void = { _ in },
                        shouldContinue: () -> Bool = { true }) async throws -> ComfyUIRunResult {
        let transport = try ComfyUITransport(serverURL: serverURL.absoluteString)
        let outputs = try await waitForOutputs(promptID: promptID, serverURL: serverURL, timeout: timeout,
            outputNodeID: outputNodeID, shouldContinue: shouldContinue)
        try onOutputs(outputs)
        guard let first = outputs.first else { throw ComfyUIRunError.failed("No selected output is available.") }
        let data = try await transport.download(first)
        return ComfyUIRunResult(data: data, descriptor: first, promptID: promptID)
    }

    static func waitForOutputs(promptID: String, serverURL: URL, timeout: TimeInterval,
                              outputNodeID: String? = nil, outputNodeIDs: [String] = [],
                              shouldContinue: () -> Bool = { true }) async throws -> [ComfyUIOutput] {
        let transport = try ComfyUITransport(serverURL: serverURL.absoluteString)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            if let entry = try await transport.history(promptID: promptID),
               let status = entry["status"] as? [String: Any], status["completed"] as? Bool == true {
                let outputs = ComfyUITransport.outputs(in: entry, selectedNodeID: outputNodeID, selectedNodeIDs: outputNodeIDs)
                guard outputs.count <= 12 else { throw ComfyUIRunError.failed("Selected workflow output exceeds the 12-file limit. Choose fewer output nodes before a new run.") }
                guard !outputs.isEmpty else { throw ComfyUIRunError.failed("ComfyUI completed this job but returned no selected output files. Check the saved output selection; no generation was resubmitted.") }
                return outputs

            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw ComfyUIRunError.failed("No completed output is available for ComfyUI job \(promptID). The server may still be working or may have lost its history. No new workflow was submitted.")
    }
}
