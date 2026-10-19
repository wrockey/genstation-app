// ContentView+Workflow.swift
import Foundation

extension ContentView {
    func handleComfyJSONSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                errorItem = AlertError(message: "No file selected.", fullMessage: nil)
                return
            }
            do {
#if os(macOS)
                let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
#else
                let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
#endif
                var bookmarkData: Data?
#if os(iOS)
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
#else
                bookmarkData = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
#endif
                AppStorageContext.defaults.set(bookmarkData, forKey: "comfyJSONBookmark")
            } catch {
                Log.debug("Bookmark error: \(error)")
                errorItem = AlertError(message: "Failed to save bookmark for file: \(error.localizedDescription)", fullMessage: nil)
                return
            }
            var loadError: NSError?
            var innerLoadError: Error?
            var json: [String: Any]?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &loadError) { coordinatedURL in
                if coordinatedURL.startAccessingSecurityScopedResource() {
                    defer { coordinatedURL.stopAccessingSecurityScopedResource() }

                    do {
                        let ext = coordinatedURL.pathExtension.lowercased()
                        if ext == "json" {
                            let data = try Data(contentsOf: coordinatedURL)
                            json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        } else if ext == "png" {
                            if let workflowStr = appState.generation.extractWorkflowFromPNG(url: coordinatedURL) {
                                if let data = workflowStr.data(using: .utf8) {
                                    json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                                } else {
                                    innerLoadError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert workflow string to data."])
                                }
                            } else {
                                innerLoadError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No embedded ComfyUI workflow found in the PNG."])
                            }
                        } else {
                            innerLoadError = NSError(domain: "FileTypeError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type. Please select a JSON or PNG file."])
                        }
                    } catch {
                        innerLoadError = error
                    }
                } else {
                    innerLoadError = NSError(domain: "AccessError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start accessing security-scoped resource."])
                }
            }
            if let loadError = loadError {
                errorItem = AlertError(message: "Failed to load workflow: \(loadError.localizedDescription)", fullMessage: nil)
                return
            }
            if let innerLoadError = innerLoadError {
                errorItem = AlertError(message: "Failed to load workflow: \(innerLoadError.localizedDescription)", fullMessage: nil)
                return
            }
            guard let json = json else {
                errorItem = AlertError(message: "Invalid workflow.", fullMessage: nil)
                return
            }

            // Prepare the workflow (UI format is auto-converted, fetching object_info
            // from the server first when the cache is missing or from another server).
            // The file-picker callback is synchronous, so the async prepare runs in a Task.
            let serverURL = appState.settings.comfyServerURL
            appState.generation.workflowImportToken += 1
            let importToken = appState.generation.workflowImportToken
            Task { @MainActor in
                do {
                    let prepared = try await ComfyUIFormatConverter.prepareWorkflowFetchingObjectInfoIfNeeded(
                        json: json, serverURL: serverURL
                    )
                    // Latest-wins: a newer import (or one still fetching object_info) bumps the
                    // token, so a slow fetch that finished late must not clobber the newer load.
                    guard importToken == appState.generation.workflowImportToken else {
                        Log.debug("Workflow import superseded by a newer one; discarding result")
                        return
                    }
                    if prepared.wasConverted {
                        Log.debug("Converted UI workflow to API format (\(prepared.workflow.count) nodes)")
                    }
                    finalizeWorkflowLoad(workflow: prepared.workflow, url: url)
                    if prepared.wasConverted {
                        appState.generation.showNonAPIFormatWarning = true
                    }
                } catch let prepError as ComfyUIFormatConverter.WorkflowPreparationError {
                    guard importToken == appState.generation.workflowImportToken else { return }
                    errorItem = AlertError(
                        message: prepError.errorDescription ?? "Failed to load workflow",
                        fullMessage: prepError.remediation
                    )
                } catch {
                    guard importToken == appState.generation.workflowImportToken else { return }
                    errorItem = AlertError(
                        message: "Failed to load workflow: \(error.localizedDescription)",
                        fullMessage: nil
                    )
                }
            }

        case .failure(let error):
            // Check if user just cancelled - that's fine, no error needed
            let nsError = error as NSError
            if nsError.code == NSUserCancelledError ||
               nsError.localizedDescription.lowercased().contains("cancel") {
                return  // User cancelled - close gracefully
            }

            Log.debug("Selection error: \(error)")
            errorItem = AlertError(message: "Failed to select workflow file: \(error.localizedDescription)", fullMessage: nil)
        }
    }

    /// Finalizes workflow loading
    private func finalizeWorkflowLoad(workflow: [String: Any], url: URL) {
        appState.generation.comfyWorkflow = workflow
        appState.generation.savedWorkflowID = nil
        appState.settings.comfyJSONURL = url
        appState.settings.comfyJSONPath = url.path

        appState.generation.processWorkflowForNodes(json: workflow)

        if let error = appState.generation.workflowError {
            errorItem = AlertError(message: error, fullMessage: nil)
        }
    }
}
