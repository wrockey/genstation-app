// ContentView+Batch.swift
import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#endif

extension ContentView {
    func reloadBatchFile() {
        appState.loadBatchPrompts()
    }
    
    func handleBatchFileSelection(_ result: Result<[URL], Error>) {
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    errorItem = AlertError(message: "No file selected.", fullMessage: nil)
                    return
                }
                do {
                    #if os(macOS)
                    let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                    let bookmarkData = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                    #else
                    let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
                    var bookmarkData: Data?
                    var coordError: NSError?
                    var innerCoordError: Error?
                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
                        if coordinatedURL.startAccessingSecurityScopedResource() {
                            defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                            do {
                                bookmarkData = try coordinatedURL.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                            } catch {
                                innerCoordError = error
                            }
                        } else {
                            innerCoordError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
                        }
                    }
                    if let coordError = coordError {
                        throw coordError
                    }
                    if let innerCoordError = innerCoordError {
                        throw innerCoordError
                    }
                    guard let bookmarkData = bookmarkData else {
                        throw NSError(domain: "BookmarkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create bookmark"])
                    }
                    #endif
                    AppStorageContext.defaults.set(bookmarkData, forKey: "batchFileBookmark")
                } catch {
                    Log.debug("Bookmark error: \(error)")
                    errorItem = AlertError(message: "Failed to save bookmark for batch file: \(error.localizedDescription)", fullMessage: nil)
                    return
                }
                var loadError: NSError?
                var innerLoadError: Error?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &loadError) { coordinatedURL in
                    if coordinatedURL.startAccessingSecurityScopedResource() {
                        defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                        do {
                            let text = try String(contentsOf: coordinatedURL)
                            appState.batchPrompts = text.components(separatedBy: .newlines)
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            appState.batchFileURL = url
                            appState.batchFilePath = url.path
                            #if os(macOS)
                            monitorFileChanges(at: url) // Start monitoring immediately
                            #endif
                        } catch {
                            innerLoadError = error
                        }
                    } else {
                        innerLoadError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
                    }
                }
                if let loadError = loadError {
                    errorItem = AlertError(message: "Failed to load batch file: \(loadError.localizedDescription)", fullMessage: nil)
                    return
                }
                if let innerLoadError = innerLoadError {
                    errorItem = AlertError(message: "Failed to load batch file: \(innerLoadError.localizedDescription)", fullMessage: nil)
                    return
                }
                appState.loadBatchPrompts()
                appState.batchFileVersion += 1
            case .failure(let error):
                let nsError = error as NSError
                if nsError.code == NSUserCancelledError ||
                   nsError.localizedDescription.lowercased().contains("cancel") {
                    return  // User cancelled — totally fine, do nothing
                }
                
                Log.debug("Batch file selection failed: \(error)")
                errorItem = AlertError(message: "Failed to select batch file: \(error.localizedDescription)", fullMessage: nil)
            }
        }

    
    func batchSubmit() {
        if appState.settings.outputPath.isEmpty {
            pendingAction = batchSubmit
            showSelectFolderAlert = true
            return
        }
        
        // NO reload – use current in-memory appState.batchPrompts (includes unsaved edits)
        guard !appState.batchPrompts.isEmpty else {
            errorItem = AlertError(message: "Batch is empty.", fullMessage: nil)
            return
        }
        
        // Safety check (unchanged)
        var offendingPrompts: [(line: Int, prompt: String, phrases: [String])] = []
        let start = batchStartIndex - 1
        let end = batchEndIndex - 1
        guard start >= 0, end < appState.batchPrompts.count, start <= end else {
            errorItem = AlertError(message: "Invalid prompt range.", fullMessage: nil)
            return
        }
        
        for i in start...end {
            let prompt = appState.batchPrompts[i]
            let (isSafe, offendingPhrases) = ContentView.isPromptSafe(prompt)
            if !isSafe {
                let lineNumber = i + 1
                offendingPrompts.append((line: lineNumber, prompt: prompt, phrases: offendingPhrases))
            }
        }
        
        if !offendingPrompts.isEmpty {
            appState.presentedModal = .contentFilterBlocked(offendingPrompts)
            return
        }
        
        isLoading = true
        appState.ui.isBatchRunning = true
        let total = (end - start) + 1
        appState.ui.batchTotalCount = total
        appState.ui.batchCurrentIndex = 0

        generationTask = Task {
            defer {
                DispatchQueue.main.async {
                    isLoading = false
                    appState.ui.isBatchRunning = false
                    appState.ui.batchTotalCount = 0
                    appState.ui.batchCurrentIndex = 0
                }
            }

            var failures: [(Int, String, String)] = []
            var completedCount = 0

            for i in start...end {
                try Task.checkCancellation()

                appState.prompt = appState.batchPrompts[i]

                // Request background execution per-prompt so each in-flight
                // HTTP request gets its own ~30s window if the app is backgrounded
                #if os(iOS)
                var bgTaskID: UIBackgroundTaskIdentifier = .invalid
                bgTaskID = await UIApplication.shared.beginBackgroundTask(withName: "BatchPrompt-\(i)") {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                    bgTaskID = .invalid
                }
                #endif

                do {
                    try await asyncGenerate()
                    completedCount += 1
                    appState.ui.batchCurrentIndex = completedCount
                    try await Task.sleep(for: .milliseconds(100))
                } catch is CancellationError {
                    #if os(iOS)
                    if bgTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                    }
                    #endif
                    break
                } catch {
                    failures.append((i + 1, appState.prompt, error.localizedDescription))
                }

                #if os(iOS)
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
                #endif
            }

            let wasCancelled = Task.isCancelled

            DispatchQueue.main.async {
                if wasCancelled {
                    successMessage = "Batch cancelled — \(completedCount) of \(total) completed"
                    showSuccessAlert = true
                } else if failures.isEmpty {
                    successMessage = "\(completedCount) images generated successfully"
                    showSuccessAlert = true
                } else if completedCount > 0 {
                    let failedLines = failures.map { "#\($0.0)" }.joined(separator: ", ")
                    successMessage = "\(completedCount) succeeded | \(failures.count) failed (lines \(failedLines))"
                    showSuccessAlert = true
                } else {
                    let failedText = failures.map { "\($0.0): \($0.1) - \($0.2)" }.joined(separator: "\n")
                    errorItem = AlertError(message: "Batch failed — all \(total) prompts errored:\n\(failedText)", fullMessage: nil)
                }
            }
        }
    }

    // ContentView.swift – Full restoreBatchFileAccessIfNeeded function
    func restoreBatchFileAccessIfNeeded() {
        guard appState.batchFileSecurityScopedURL == nil,
              let data = AppStorageContext.defaults.data(forKey: "batchFileBookmark")
        else { return }

        do {
            var isStale = false
            #if os(macOS)
            let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let resolutionOptions: URL.BookmarkResolutionOptions = []
            #endif
            let url = try URL(resolvingBookmarkData: data,
                              options: resolutionOptions,
                              bookmarkDataIsStale: &isStale)

            // Refresh bookmark if stale
            if isStale {
                #if os(macOS)
                let refreshOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
                if let freshData = try? url.bookmarkData(options: refreshOptions) {
                    AppStorageContext.defaults.set(freshData, forKey: "batchFileBookmark")
                    Log.debug("RESTORE: Refreshed stale bookmark with security scope")
                } else {
                    // Fallback
                    if let minimalFresh = try? url.bookmarkData(options: [.minimalBookmark]) {
                        AppStorageContext.defaults.set(minimalFresh, forKey: "batchFileBookmark")
                        Log.debug("RESTORE: Refreshed stale with minimal fallback")
                    }
                }
                #else
                if let freshData = try? url.bookmarkData(options: [.minimalBookmark]) {
                    AppStorageContext.defaults.set(freshData, forKey: "batchFileBookmark")
                }
                #endif
            }

            // Start access (critical for persistence across sessions)
            let accessing = url.startAccessingSecurityScopedResource()
            if !accessing {
                throw NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start security-scoped access."])
            }

            appState.batchFileSecurityScopedURL = url
            appState.batchFilePath = url.path
            appState.loadBatchPrompts()  // Reload prompts now that access is granted

            #if os(macOS)
            monitorFileChanges(at: url)  // Set up monitoring for external edits
            #endif
        } catch {
            Log.debug("Failed to restore batch file access: \(error.localizedDescription)")
            clearBatchFile()  // Clean up if restoration fails
        }
    }
}
