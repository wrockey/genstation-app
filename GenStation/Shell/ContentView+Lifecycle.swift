//ContentView+Lifecycle.swift
import Foundation

extension ContentView {
    func performOnAppear() {
        // Wire the job queue to app state and the ContentView-coupled operations
        // (retry dialogs, media saving, recovered-video toast) before anything
        // can submit or resume a job.
        Task { @MainActor in
            appState.jobQueue.configure(appState: appState, bridge: JobQueueBridge(
                showRetryDialog: { message in await self.showRetryDialog(message: message) },
                saveGeneratedMedia: { data, prompt, modelUsed in
                    self.saveGeneratedMedia(data: data, prompt: prompt, mode: .aimlapi, modelUsed: modelUsed, isVideo: true)
                },
                saveRecoveredImage: { data, prompt, modelUsed, provider in
                    self.saveGeneratedImage(data: data, prompt: prompt, mode: provider, modelUsed: modelUsed)
                },
                detectVideoHasAudio: { path in await self.detectVideoHasAudio(at: path) },
                notifyRecovered: { message in
                    self.successMessage = message
                    self.showSuccessAlert = true
                }
            ))

            #if os(macOS)
            // Start the MCP server (WS-7) — agent access over the bundled
            // genstation-mcp helper. Idempotent; honors the Agent Access toggle.
            appState.mcpService.startIfEnabled(appState: appState, bridge: MCPBridge(
                saveAgentImage: { data, prompt, provider, model in
                    self.saveGeneratedImage(data: data, prompt: prompt, mode: provider, modelUsed: model)
                },
                saveImage: { data, prompt, modelUsed in
                    self.saveGeneratedImage(data: data, prompt: prompt, mode: .aimlapi, modelUsed: modelUsed)
                },
                saveWorkflowOutput: { data, prompt, isVideo, fileExtension in
                    self.saveGeneratedMedia(data: data, prompt: prompt, mode: .comfyUI, isVideo: isVideo, fileExtension: fileExtension)
                }
            ))
            #endif
        }

        // Heavy async loading (unchanged)
        Task {
            await loadHeavyResources()
        }
    }

    private func loadHeavyResources() async {
        // Resolve output directory bookmark FIRST so security scope is active
        // before history tries to load thumbnails
        let bookmarkData = AppStorageContext.defaults.data(forKey: "outputDirBookmark")
        Log.debug("iOS Bookmark: Found bookmark data: \(bookmarkData != nil), size: \(bookmarkData?.count ?? 0)")

        if let bookmarkData = bookmarkData {
            await resolveOutputDirBookmark(bookmarkData: bookmarkData)
        } else {
            let output = AppStorageContext.current.outputDirectory
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                appState.settings.outputDirectory = output
            } catch {
                appState.errorItem = AlertError(message: "Choose an output folder in Settings to save generated media.", fullMessage: nil)
            }
        }

        // Now load history (thumbnails will need the security scope)
        appState.historyState.loadHistory()
        appState.ui.loadCustomStyles()

        // Check for pending video jobs after history is loaded
        // (scenePhase .active may fire before history loads on cold launch)
        await MainActor.run {
            checkPendingVideoJobs()
        }

        if let bookmarkData = AppStorageContext.defaults.data(forKey: "comfyJSONBookmark") {
            await resolveComfyJSONBookmark(bookmarkData: bookmarkData)
        }

        if let bookmarkData = AppStorageContext.defaults.data(forKey: "batchFileBookmark") {
            await resolveBatchFileBookmark(bookmarkData: bookmarkData)
        }
    }

    private func resolveOutputDirBookmark(bookmarkData: Data) async {
        Log.debug("iOS Bookmark: Attempting to resolve output directory bookmark (\(bookmarkData.count) bytes)")
        var isStale = false
        do {
#if os(macOS)
            let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
#else
            let resolveOptions: URL.BookmarkResolutionOptions = []
#endif
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, bookmarkDataIsStale: &isStale)
            Log.debug("iOS Bookmark: Resolved to \(resolvedURL.path), isStale=\(isStale)")

            if isStale {
                // Stale bookmarks are refreshable: mint new bookmark data from the
                // resolved URL and keep going. Never delete the stored bookmark here —
                // a failed refresh still leaves the user able to retry next launch.
                Log.debug("Bookmark: stale, attempting refresh")
#if os(macOS)
                let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
#else
                let creationOptions: URL.BookmarkCreationOptions = []
#endif
                if let refreshed = try? resolvedURL.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    AppStorageContext.defaults.set(refreshed, forKey: "outputDirBookmark")
                    Log.debug("Bookmark: refreshed and re-saved")
                }
                let didStart = resolvedURL.startAccessingSecurityScopedResource()
                if didStart || FileManager.default.fileExists(atPath: resolvedURL.path) {
                    appState.settings.outputDirectory = resolvedURL
                } else {
                    DispatchQueue.main.async {
                        self.errorItem = AlertError(message: "Output folder couldn't be accessed. Please reselect it in General Options.", fullMessage: nil)
                    }
                }
            } else {
                // Start security scope access - this must be done to access files on iOS
                // We keep it active for the app session (balanced when user changes folder or app terminates)
                let didStart = resolvedURL.startAccessingSecurityScopedResource()
                Log.debug("iOS Bookmark: startAccessingSecurityScopedResource returned \(didStart)")

                let exists = FileManager.default.fileExists(atPath: resolvedURL.path)
                Log.debug("iOS Bookmark: File exists at path: \(exists)")

                if didStart || exists {
                    appState.settings.outputDirectory = resolvedURL
                    Log.debug("iOS Bookmark: Successfully set outputDirectory to \(resolvedURL.path)")
                } else {
                    throw NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "Resolved file does not exist at path: \(resolvedURL.path)"])
                }
            }
        } catch let err as NSError {
            Log.debug("iOS Bookmark: Error resolving - \(err.localizedDescription)")
            let errorMsg: String
            if err.code == 4 {
                errorMsg = "Output directory not found or moved. Please reselect the folder."
            } else {
                errorMsg = "Failed to resolve output directory: \(err.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.errorItem = AlertError(message: errorMsg, fullMessage: nil)
            }
            // Keep the stored bookmark: resolution failures can be transient (moved
            // volume, signature change) and the user re-picking overwrites it anyway.
        }
    }

    private func resolveComfyJSONBookmark(bookmarkData: Data) async {
        var isStale = false
        do {
#if os(macOS)
            let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
#else
            let resolveOptions: URL.BookmarkResolutionOptions = []
#endif
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, bookmarkDataIsStale: &isStale)
            
            // Coordinate access for existence check and loading
            var coordError: NSError?
            var innerCoordError: Error?
            var json: [String: Any]?
            NSFileCoordinator().coordinate(readingItemAt: resolvedURL, options: [], error: &coordError) { coordinatedURL in
                if coordinatedURL.startAccessingSecurityScopedResource() {
                    defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                    
                    do {
                        // Now check existence with scoped access active
                        if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                            appState.settings.comfyJSONURL = coordinatedURL
                            appState.settings.comfyJSONPath = coordinatedURL.path
                            
                            // Check sync status (for iCloud/iOS)
                            let values = try coordinatedURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                            if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                                try FileManager.default.startDownloadingUbiquitousItem(at: coordinatedURL)
                                innerCoordError = NSError(domain: "DownloadError", code: 0, userInfo: [NSLocalizedDescriptionKey: "File is downloading from provider—try again in a moment."])
                                return
                            }
                            
                            // Load and parse JSON (handle both JSON and PNG)
                            let ext = coordinatedURL.pathExtension.lowercased()
                            if ext == "json" {
                                let data = try Data(contentsOf: coordinatedURL)
                                json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                            } else if ext == "png" {
                                if let workflowStr = appState.generation.extractWorkflowFromPNG(url: coordinatedURL) {
                                    if let data = workflowStr.data(using: .utf8) {
                                        json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                                    } else {
                                        innerCoordError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert workflow string to data."])
                                    }
                                } else {
                                    innerCoordError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No embedded ComfyUI workflow found in the PNG."])
                                }
                            } else {
                                innerCoordError = NSError(domain: "FileTypeError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type."])
                            }
                            
                            guard let json = json else {
                                innerCoordError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid workflow."])
                                return
                            }
                            
                            if json.isEmpty {
                                innerCoordError = NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid or empty workflow."])
                                return
                            }
                            // The parsed workflow (`json`) is prepared after the coordinator
                            // block via the shared prepareWorkflow path so subgraph/group-node
                            // workflows are rejected (not silently truncated) and object_info is
                            // auto-fetched when missing — matching the import paths. (finding #8)
                        } else {
                            innerCoordError = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "Resolved file does not exist at path: \(coordinatedURL.path)"])
                        }
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
            
            if isStale {
#if os(macOS)
                let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
#else
                let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
#endif
                var refreshError: NSError?
                var innerRefreshError: Error?
                NSFileCoordinator().coordinate(readingItemAt: resolvedURL, options: [], error: &refreshError) { coordinatedURL in
                    let didStart = coordinatedURL.startAccessingSecurityScopedResource()
                    defer { if didStart { coordinatedURL.stopAccessingSecurityScopedResource() } }
                    do {
                        let newBookmarkData = try coordinatedURL.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                        AppStorageContext.defaults.set(newBookmarkData, forKey: "comfyJSONBookmark")
                    } catch {
                        innerRefreshError = error
                    }
                }
                if let refreshError = refreshError {
                    Log.debug("Coordination error during refresh: \(refreshError)")
                }
                if let innerRefreshError = innerRefreshError {
                    Log.debug("Failed to refresh bookmark: \(innerRefreshError)")
                }
            }

            // Route the restored workflow through the same shared preparation as the import
            // paths: UI-format is converted (auto-fetching object_info when needed) and
            // subgraph / group-node workflows are rejected with a surfaced error instead of
            // being silently truncated. (finding #8)
            guard let rawWorkflow = json else { return }
            let serverURL = appState.settings.comfyServerURL
            appState.generation.workflowImportToken += 1
            let importToken = appState.generation.workflowImportToken
            do {
                let prepared = try await ComfyUIFormatConverter.prepareWorkflowFetchingObjectInfoIfNeeded(
                    json: rawWorkflow, serverURL: serverURL
                )
                guard importToken == appState.generation.workflowImportToken else {
                    Log.debug("Restore: workflow import superseded by a newer one; discarding result")
                    return
                }
                appState.generation.comfyWorkflow = prepared.workflow
                appState.generation.savedWorkflowID = nil
                appState.generation.processWorkflowForNodes(json: prepared.workflow)

                // Restore persisted selectedImageNodeIDs (filter to only valid node IDs)
                let validNodeIDs = Set(appState.generation.imageNodes.map { $0.id })
                if !validNodeIDs.isEmpty,
                   let persistedData = appState.settings.comfySelectedImageNodeIDsJSON.data(using: .utf8),
                   let persistedIDs = try? JSONDecoder().decode([String].self, from: persistedData) {
                    let restoredIDs = Set(persistedIDs).intersection(validNodeIDs)
                    if !restoredIDs.isEmpty {
                        appState.generation.selectedImageNodeIDs = restoredIDs
                        Log.debug("Restored \(restoredIDs.count) persisted image node selections")
                    }
                }
                if let error = appState.generation.workflowError {
                    self.errorItem = AlertError(message: error, fullMessage: nil)
                }
            } catch let prepError as ComfyUIFormatConverter.WorkflowPreparationError {
                guard importToken == appState.generation.workflowImportToken else { return }
                // Don't leave a truncated/half-loaded graph behind — clear it and surface the error.
                appState.generation.comfyWorkflow = nil
                appState.generation.savedWorkflowID = nil
                var message = prepError.errorDescription ?? "Failed to load workflow"
                if let remediation = prepError.remediation { message += "\n\n\(remediation)" }
                self.errorItem = AlertError(message: message, fullMessage: nil)
            } catch {
                guard importToken == appState.generation.workflowImportToken else { return }
                appState.generation.comfyWorkflow = nil
                appState.generation.savedWorkflowID = nil
                self.errorItem = AlertError(message: "Failed to load workflow: \(error.localizedDescription)", fullMessage: nil)
            }
        } catch let err as NSError {
            Log.debug("Bookmark resolution error: \(err.localizedDescription) (code: \(err.code), path: \(appState.settings.comfyJSONURL?.path ?? "none"))")
            let errorMsg: String
            if err.code == 4 {
                errorMsg = "ComfyUI JSON file not found or moved. Please reselect the file."
            } else {
                errorMsg = "Failed to resolve or access ComfyUI JSON: \(err.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.errorItem = AlertError(message: errorMsg,  fullMessage: nil)
            }
            AppStorageContext.defaults.removeObject(forKey: "comfyJSONBookmark")
            appState.settings.comfyJSONURL = nil
            appState.settings.comfyJSONPath = ""
        }
    }

    private func resolveBatchFileBookmark(bookmarkData: Data) async {
        var isStale = false
        do {
#if os(macOS)
            let resolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
#else
            let resolveOptions: URL.BookmarkResolutionOptions = []
#endif
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: resolveOptions, bookmarkDataIsStale: &isStale)
            
            var coordError: NSError?
            var innerCoordError: Error?
            NSFileCoordinator().coordinate(readingItemAt: resolvedURL, options: [], error: &coordError) { coordinatedURL in
                if coordinatedURL.startAccessingSecurityScopedResource() {
                    defer { coordinatedURL.stopAccessingSecurityScopedResource() }
                    
                    do {
                        if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                            appState.batchFileURL = coordinatedURL
                            DispatchQueue.main.async {
                                appState.batchFilePath = coordinatedURL.path
                            }
                            
                            let values = try coordinatedURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                            if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                                try FileManager.default.startDownloadingUbiquitousItem(at: coordinatedURL)
                                innerCoordError = NSError(domain: "DownloadError", code: 0, userInfo: [NSLocalizedDescriptionKey: "File is downloading—try again soon."])
                                return
                            }
                            
                            let text = try String(contentsOf: coordinatedURL)
                            appState.batchPrompts = text.components(separatedBy: .newlines)
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        } else {
                            innerCoordError = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "Resolved file does not exist at path: \(coordinatedURL.path)"])
                        }
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
            
            if isStale {
#if os(macOS)
                let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
#else
                let bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
#endif
                var refreshError: NSError?
                var innerRefreshError: Error?
                NSFileCoordinator().coordinate(readingItemAt: resolvedURL, options: [], error: &refreshError) { coordinatedURL in
                    let didStart = coordinatedURL.startAccessingSecurityScopedResource()
                    defer { if didStart { coordinatedURL.stopAccessingSecurityScopedResource() } }
                    do {
                        let newBookmarkData = try coordinatedURL.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                        AppStorageContext.defaults.set(newBookmarkData, forKey: "batchFileBookmark")
                    } catch {
                        innerRefreshError = error
                    }
                }
                if let refreshError = refreshError {
                    Log.debug("Coordination error during refresh: \(refreshError)")
                }
                if let innerRefreshError = innerRefreshError {
                    Log.debug("Failed to refresh bookmark: \(innerRefreshError)")
                }
            }
        } catch let err as NSError {
            Log.debug("Bookmark resolution error for batch file: \(err.localizedDescription)")
            let errorMsg: String
            if err.code == 4 {
                errorMsg = "Batch file not found or moved. Please reselect the file."
            } else {
                errorMsg = "Failed to resolve or access batch file: \(err.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.errorItem = AlertError(message: errorMsg, fullMessage: nil)
            }
            AppStorageContext.defaults.removeObject(forKey: "batchFileBookmark")
            appState.batchFileURL = nil
            DispatchQueue.main.async {
                appState.batchFilePath = ""
            }
        }
    }
    
    func resetAppState() {
        appState.prompt = ""
        appState.ui.imageSlots = []
        appState.ui.outputImages = []
        appState.ui.outputTexts = []
        appState.ui.outputPaths = []
        appState.ui.currentOutputIndex = 0
        isLoading = false
        progress = 0.0
        isCancelled = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        errorItem = nil
        appState.batchFilePath = ""
        // startPrompt = "1"  // Commented as in original; remove if unused
        // endPrompt = ""     // Commented as in original; remove if unused
    }}
