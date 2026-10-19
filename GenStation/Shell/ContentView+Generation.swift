import SwiftUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
import AVFoundation
import GenStationCore

// MARK: - User-friendly Path Helper
/// Formats a saved file path for display to the user
/// - iOS: Shows just the folder name (arcane paths are meaningless to users)
/// - macOS: Shows the full path
func userFriendlyPath(_ path: String) -> String {
    #if os(iOS)
    // On iOS, just show the folder name
    let url = URL(fileURLWithPath: path)
    let folderName = url.deletingLastPathComponent().lastPathComponent
    return folderName.isEmpty ? "output folder" : folderName
    #else
    // On macOS, show full path (users understand file system)
    return path
    #endif
}

// MARK: - Auto-present Helper
/// Triggers presentation of generated image(s) based on settings and count
/// - Single image: Auto-present if enabled (unless batch mode is running)
/// - Batch (multiple): Show toast notification instead
@MainActor
private func triggerGenerationPresentation(imageCount: Int, appState: AppState) {
    guard imageCount > 0 else { return }

    // Skip auto-present during batch mode
    if appState.ui.isBatchRunning {
        return
    }

    if imageCount == 1 && appState.settings.autoPresentGeneratedImages {
        // Single image - trigger auto-present
        appState.ui.shouldPresentGeneratedImage = true
    } else if imageCount > 1 {
        // Batch - show toast
        appState.ui.generationToastMessage = "\(imageCount) images added to session"
        appState.ui.showGenerationToast = true
    }
}

extension ContentView {
    func submitPrompt() {
        if appState.settings.outputPath.isEmpty {
            pendingAction = submitPrompt
            showSelectFolderAlert = true
            return
        }
        
        let (isSafe, offendingPhrases) = ContentView.isPromptSafe(appState.prompt)
        if !isSafe {
            appState.presentedModal = .contentFilterBlocked([
                (line: 1, prompt: appState.prompt, phrases: offendingPhrases.sorted())
            ])
            return
        }
        
        switch appState.settings.provider {
        case .gemini:
            guard !appState.settings.apiKey.isEmpty else {
                errorItem = AlertError(message: "Gemini API key is missing.", fullMessage: nil)
                return
            }
        case .grok:
            guard !appState.settings.grokApiKey.isEmpty else {
                errorItem = AlertError(message: "Grok API key is missing.", fullMessage: nil)
                return
            }
        case .aimlapi:
            guard !appState.settings.aimlapiKey.isEmpty else {
                errorItem = AlertError(message: "AI/ML API key is missing.", fullMessage: nil)
                return
            }
        default:
            break
        }
        
        // Remote video jobs are queue-backed and non-blocking: enqueue, clear the
        // form, and never gate the UI on isLoading (WS-3; findings #11/#18).
        if appState.settings.usesVideoQueue {
            submitVideoPrompt()
            return
        }

        isLoading = true
        errorItem = nil
        appState.ui.outputImages = []
        appState.ui.outputTexts = []
        appState.ui.outputPaths = []
        appState.ui.currentOutputIndex = 0

        // Cancel any background video resume so it doesn't interfere
        videoResumeTask?.cancel()
        videoResumeTask = nil

        generationTask = Task {
            // Request extended background execution on iOS so generation completes
            // even if the user switches apps or the screen locks
            #if os(iOS)
            var bgTaskID: UIBackgroundTaskIdentifier = .invalid
            bgTaskID = await UIApplication.shared.beginBackgroundTask(withName: "ImageGeneration") {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
            #endif

            defer {
                #if os(iOS)
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
                #endif
                DispatchQueue.main.async {
                    isLoading = false
                }
            }

            do {
                try await asyncGenerate()
            } catch is CancellationError {
                // Handle cancellation
            } catch {
                DispatchQueue.main.async {
                    if let genError = error as? GenerationError {
                        switch genError {
                        case .queueFailed, .uploadFailed, .fetchFailed:
                            Log.debug("Detailed Error Message: \(genError.details ?? "")")
                            let details = genError.details ?? ""
                            let isMissingNode = details.contains("missing") || details.contains("not found")
                            let summary = isMissingNode
                                ? "ComfyUI error: Missing or unknown node type.\n\nTry exporting your workflow as API format: in ComfyUI, enable Dev Mode in Settings, then use Save (API Format)."
                                : "ComfyUI request failed."
                            let fullMessage = self.appState.settings.provider == .comfyUI ? details : genError.details
                            errorItem = AlertError(message: summary, fullMessage: fullMessage)
                        default:
                            errorItem = AlertError(message: genError.errorDescription ?? "Unknown error", fullMessage: genError.details)
                        }
                    } else {
                        errorItem = AlertError(message: error.localizedDescription, fullMessage: nil)
                    }
                }
            }
        }
    }
    
    /// Non-blocking submit for remote (AIML) video jobs: builds and enqueues the
    /// job, clears the prompt for the next one once the queue accepts it, and
    /// reports errors through the same alert flow — the Submit button never
    /// disables because a video job is running. Per-job progress/cancel lives
    /// in the Jobs panel.
    func submitVideoPrompt() {
        let promptSnapshot = appState.prompt
        errorItem = nil
        appState.ui.outputImages = []
        appState.ui.outputTexts = []
        appState.ui.outputPaths = []
        appState.ui.currentOutputIndex = 0

        // Cancel any background video resume so it doesn't interfere
        videoResumeTask?.cancel()
        videoResumeTask = nil

        // Create the job record up front (in .preparing) so it appears in the Jobs
        // panel — and is cancellable — during input-image upload and payload build,
        // before any HTTP request exists (finding C). The prompt is intentionally
        // NOT cleared here: it clears only after a successful POST (finding B).
        let jobID = appState.jobQueue.beginJob(modelId: appState.settings.selectedVideoModel, prompt: promptSnapshot)

        let task = Task {
            // Request extended background execution on iOS so the poll continues
            // even if the user switches apps or the screen locks
            #if os(iOS)
            var bgTaskID: UIBackgroundTaskIdentifier = .invalid
            bgTaskID = await UIApplication.shared.beginBackgroundTask(withName: "VideoGeneration") {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
            defer {
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
            #endif

            do {
                try await asyncGenerate(promptOverride: promptSnapshot, videoJobID: jobID, onVideoJobPosted: {
                    // POST succeeded and the pending history item is written — free
                    // the form for the next prompt (unless the user already typed
                    // something new). Finding B: never clear before the POST.
                    if appState.prompt == promptSnapshot {
                        appState.prompt = ""
                    }
                })
            } catch is CancellationError {
                // Cancelled from the Jobs panel — job record/history carry the state.
                appState.jobQueue.finishPreparing(jobID, error: CancellationError())
            } catch {
                // If the failure happened before the POST (upload/build), the job is
                // still .preparing — mark it failed so it doesn't linger. If
                // runPreparedJob already finished it, this is a no-op. The prompt
                // stays in the form (finding B).
                appState.jobQueue.finishPreparing(jobID, error: error)
                if let genError = error as? GenerationError {
                    errorItem = AlertError(message: genError.errorDescription ?? "Unknown error", fullMessage: genError.details)
                } else {
                    errorItem = AlertError(message: error.localizedDescription, fullMessage: nil)
                }
            }
        }
        appState.jobQueue.track(jobID, task: task)
    }

    /// - Parameters:
    ///   - promptOverride: prompt captured at submit time (non-blocking video path);
    ///     defaults to the live form prompt.
    ///   - videoJobID: for the remote video path, the pre-created (`.preparing`)
    ///     job whose record was made at submit time so it shows in the Jobs panel
    ///     during image upload / payload build.
    ///   - onVideoJobPosted: fired once the provider job exists and its pending
    ///     history item is written — the non-blocking submit path clears the form
    ///     there (only after a successful POST, finding B).
    func asyncGenerate(promptOverride: String? = nil,
                       videoJobID: UUID? = nil,
                       onVideoJobPosted: (() -> Void)? = nil) async throws {
        try Task.checkCancellation()
        if appState.settings.provider == .aimlapi,
           let issue = ReleaseModelPolicy.validateRequest(
               modelID: appState.settings.selectedAIMLModel,
               task: appState.settings.isVideoMode ? .video : .image,
               customPayload: appState.settings.customAIMLPayload,
               endpoint: appState.settings.customAIMLEndpoint) {
            throw GenerationError.apiError(issue)
        }

        // Apply selected styles to prompt (if any)
        let finalPrompt = StyleManager.applyStyles(
            Array(appState.ui.selectedStyles),
            to: promptOverride ?? appState.prompt
        )
        guard PromptSafetyPolicy.isPromptSafe(finalPrompt).isSafe else {
            throw GenerationError.apiError("The composed prompt was blocked by the content filter. No upload or generation was submitted.")
        }

        // Merge style negative prompts into a LOCAL copy of the AIML params for this
        // job — never mutate appState.settings.aimlAdvancedParams. A minutes-long
        // video poll (or the user editing params mid-job) must not race a shared
        // merge/restore dance (finding D). All AIML payload builders below read
        // `aimlParams`, not the live settings.
        var aimlParams = appState.settings.aimlAdvancedParams
        if appState.settings.provider == .aimlapi && !appState.ui.selectedStyles.isEmpty {
            let styleNegatives = StyleManager.combineNegativePrompts(Array(appState.ui.selectedStyles))
            if !styleNegatives.isEmpty {
                let existing = aimlParams.negativePrompt ?? ""
                aimlParams.negativePrompt = existing.isEmpty ? styleNegatives : existing + ", " + styleNegatives
            }
        }

        switch appState.settings.provider {
        case .gemini:
            guard GeminiClient.supportedImageModels.contains(appState.settings.selectedGeminiModel) else {
                throw GenerationError.apiError("This Gemini model is no longer supported. Refresh the model list and select an image model.")
            }
            if !(await showPrivacyNotice(for: .gemini)) {
                throw GenerationError.apiError("User declined privacy notice.")
            }
            var parts: [GeminiClient.Part] = [GeminiClient.Part(text: finalPrompt, inlineData: nil)]

            for slot in appState.ui.imageSlots {
                // Load full image from disk for upload
                guard let fullURL = slot.fullResolutionURL,
                      let fullImage = PlatformImage(contentsOfFile: fullURL.path) else {
                    if slot.fullResolutionURL == nil { continue }
                    throw GenerationError.apiError("A reference image could not be read. Add it again before generating.")
                }
                guard let processed = processImageForUpload(image: fullImage, originalData: slot.originalData, format: "jpeg", isBase64: true, convertToJPG: appState.settings.base64ConvertToJPG, scale50Percent: appState.settings.base64Scale50Percent) else { throw GenerationError.apiError("A reference image could not be prepared for upload. Add it again before generating.") }
                let base64 = processed.data.base64EncodedString()
                let inline = GeminiClient.InlineData(mimeType: processed.mimeType, data: base64)
                parts.append(GeminiClient.Part(text: nil, inlineData: inline))
            }

            let content = GeminiClient.Content(parts: parts)

            // Build generation config with user settings
            let geminiParams = appState.settings.geminiAdvancedParams
            // One predicate, shared with GeminiAdvancedSettingsView.supportsResolution, so a model
            // whose Image Resolution card is hidden cannot ship imageConfig.imageSize (drift ledger
            // § A.12). This narrows what is sent: any Gemini id that is neither a 3.x image model
            // nor `2.5-flash-image` stops carrying the key.
            let supportsImageSize = GeminiClient.supportsImageSize(
                modelID: appState.settings.selectedGeminiModel)
            let imageConfig = GeminiClient.GeminiImageConfig(
                aspectRatio: geminiParams.aspectRatio,
                imageSize: supportsImageSize ? geminiParams.geminiResolution : nil
            )
            let generationConfig = GeminiClient.GeminiGenerationConfig(
                responseModalities: ["TEXT", "IMAGE"],
                imageConfig: imageConfig
            )
            let requestBody = GeminiClient.GenerateContentRequest(
                contents: [content],
                generationConfig: generationConfig
            )

            let modelName = appState.settings.selectedGeminiModel
            let url = GeminiClient.generateContentURL(model: modelName, apiKey: appState.settings.apiKey)

            var request = URLRequest(url: url, timeoutInterval: 360)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(appState.settings.apiKey, forHTTPHeaderField: GeminiClient.apiKeyHeaderName)
            
            request.httpBody = try JSONEncoder().encode(requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw GenerationError.apiError(ProviderFailure.message(provider: .grok, status: status, body: data, phase: .submission))
            }
            
            Log.debug("Gemini response: HTTP \(httpResponse.statusCode), \(data.count) bytes")
            let responseDecoded = try JSONDecoder().decode(GeminiClient.NewGenerateContentResponse.self, from: data)

            // Check for prompt-level blocking first
            if let feedback = responseDecoded.promptFeedback, let blockReason = feedback.blockReason {
                let reasonMessage = GeminiClient.formatBlockReason(blockReason, safetyRatings: feedback.safetyRatings)
                await MainActor.run {
                    appState.ui.outputTexts = [reasonMessage]
                    appState.ui.outputImages = []
                    appState.ui.outputPaths = []
                }
                // Build detailed error message with safety ratings if available
                var errorDetails = "Reason: \(blockReason)"
                if let ratings = feedback.safetyRatings, !ratings.isEmpty {
                    let ratingDetails = ratings.map { "\($0.category): \($0.probability)" }.joined(separator: "\n")
                    errorDetails += "\n\nSafety Ratings:\n\(ratingDetails)"
                }
                throw GenerationError.apiError(errorDetails)
            }

            // Check for empty or missing candidates
            if responseDecoded.candidates?.isEmpty ?? true {
                await MainActor.run {
                    appState.ui.outputTexts = ["No response from model. The prompt may have been blocked or the model couldn't generate content."]
                    appState.ui.outputImages = []
                    appState.ui.outputPaths = []
                }
                throw GenerationError.apiError("No candidates in response")
            }

            // Check for candidate-level issues:
            // 1. Known blocking reasons (explicit list)
            // 2. Any non-STOP finish reason with a finishMessage (catches new/unknown blocking reasons)
            // 3. Empty content with a finishMessage
            if let candidate = responseDecoded.candidates?.first {
                let finishReason = candidate.finishReason ?? ""
                let hasContent = !(candidate.content?.parts?.isEmpty ?? true)
                let knownBlockReasons = ["SAFETY", "IMAGE_SAFETY", "IMAGE_OTHER", "RECITATION", "OTHER", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII"]

                // If we have a finishMessage and either: known block reason, non-STOP reason, or empty content
                if let finishMessage = candidate.finishMessage, !finishMessage.isEmpty {
                    if knownBlockReasons.contains(finishReason) || (finishReason != "STOP" && finishReason != "") || !hasContent {
                        let reasonMessage = GeminiClient.formatBlockReason(finishReason, safetyRatings: candidate.safetyRatings, finishMessage: finishMessage)
                        await MainActor.run {
                            appState.ui.outputTexts = [reasonMessage]
                            appState.ui.outputImages = []
                            appState.ui.outputPaths = []
                        }
                        // Include finishMessage in error details for "More Info" dialog
                        let errorDetails = "Reason: \(finishReason)\n\n\(finishMessage)"
                        throw GenerationError.apiError(errorDetails)
                    }
                }
                // Also check for known block reasons without finishMessage
                else if knownBlockReasons.contains(finishReason) {
                    let reasonMessage = GeminiClient.formatBlockReason(finishReason, safetyRatings: candidate.safetyRatings, finishMessage: nil)
                    await MainActor.run {
                        appState.ui.outputTexts = [reasonMessage]
                        appState.ui.outputImages = []
                        appState.ui.outputPaths = []
                    }
                    throw GenerationError.apiError("Reason: \(finishReason)")
                }
            }

            var images: [PlatformImage?] = []
            var texts: [String] = []
            var paths: [String?] = []

            for part in responseDecoded.candidates?.first?.content?.parts ?? [] where part.thought != true {
                var textOutput = ""
                if let text = part.text {
                    textOutput += text + "\n"
                } else if let inline = part.inlineData, let imgData = Data(base64Encoded: inline.data) {
                    let image = PlatformImage(platformData: imgData)
                    let path = saveGeneratedImage(data: imgData, prompt: finalPrompt, mode: .gemini)?.path
                    if let saved = path {
                        textOutput += "Image saved to \(userFriendlyPath(saved))\n"
                    }
                    images.append(image)
                    texts.append(textOutput)
                    paths.append(path)
                }
            }

            // Fallback: if no images and no text output, show an error
            if images.isEmpty && texts.isEmpty {
                // Check if there's a finishMessage we might have missed
                let fallbackMessage: String
                var errorDetails = "Empty response from model"
                if let candidate = responseDecoded.candidates?.first {
                    if let finishMessage = candidate.finishMessage, !finishMessage.isEmpty {
                        fallbackMessage = finishMessage
                        let reason = candidate.finishReason ?? "Unknown"
                        errorDetails = "Reason: \(reason)\n\n\(finishMessage)"
                    } else {
                        fallbackMessage = "No image generated. The model returned an empty response. Try rephrasing your prompt."
                    }
                } else {
                    fallbackMessage = "No image generated. The model returned an empty response. Try rephrasing your prompt."
                }
                await MainActor.run {
                    appState.ui.outputTexts = [fallbackMessage]
                    appState.ui.outputImages = []
                    appState.ui.outputPaths = []
                }
                throw GenerationError.apiError(errorDetails)
            }

            if images.isEmpty && !texts.isEmpty {
                images.append(nil)
                paths.append(nil)
            }
            
            await MainActor.run {
                appState.ui.outputImages = images
                appState.ui.outputTexts = texts
                appState.ui.outputPaths = paths
                appState.ui.currentOutputIndex = 0
            }
            
            let batchId = images.count > 1 ? UUID() : nil
            let total = images.count
            for i in 0..<total {
                let newItem = HistoryItem(
                    prompt: finalPrompt,
                    responseText: texts[i],
                    imagePath: paths[i],
                    date: Date(),
                    mode: appState.settings.provider,
                    task: .image,  // Gemini's generation path produces stills only.
                    workflowName: nil,
                    modelUsed: appState.settings.selectedGeminiModel,
                    batchId: batchId,
                    indexInBatch: i,
                    totalInBatch: total,
                    jobId: nil,
                    status: nil,
                    customAIMLPayload: nil,
                    customAIMLEndpoint: nil
                )
                appState.historyState.history.append(.item(newItem))
                appState.ui.sessionGeneratedIDs.append(newItem.id)  // Track in session gallery
            }
            appState.historyState.saveHistory()

            // Auto-present or show toast
            await MainActor.run {
                triggerGenerationPresentation(imageCount: images.compactMap { $0 }.count, appState: appState)
            }

        case .comfyUI:
            guard let workflow = appState.generation.comfyWorkflow else {
                throw GenerationError.noWorkflow
            }
            // Pre-submit structural validation: catch unconverted UI-format workflows
            // before any server traffic instead of surfacing an opaque server 400.
            if let shapeProblem = ComfyUIFormatConverter.validateAPIShape(workflow) {
                throw GenerationError.workflowNotConverted(shapeProblem)
            }
            let objectInfo = try await checkServerAvailability()

            let comfyServerURL = appState.settings.comfyServerURL
            // Fail fast on an unparseable server URL before doing any real work; the actual
            // per-request URLs are built by ComfyUIEndpoints at each call site below.
            guard ComfyUIEndpoints.promptURL(serverURL: comfyServerURL) != nil else {
                throw GenerationError.invalidServerURL
            }
            
            var mutableWorkflow = workflow
            
            // Find a seed-bearing node for batch seed variation (optional — workflow runs without one)
            // Priority: KSampler variants (have "seed" input), then RandomNoise (has "noise_seed" input)
            var seedNodeID: String? = nil
            var seedKey: String = "seed"
            for (nodeID, node) in mutableWorkflow {
                guard let nodeDict = node as? [String: Any], let classType = nodeDict["class_type"] as? String else { continue }
                if classType.contains("KSampler") {
                    seedNodeID = nodeID
                    seedKey = "seed"
                    break
                }
                if seedNodeID == nil && classType == "RandomNoise" {
                    seedNodeID = nodeID
                    seedKey = "noise_seed"
                }
            }
            if seedNodeID == nil {
                Log.debug("No sampler/noise node found — workflow will run as-is without seed variation for batching")
            }
            
            // Force batch_size to 1 on the latent-source node. Covers EmptyLatentImage and the
            // newer renamed variants (EmptySD3LatentImage, EmptyHunyuanLatentVideo, etc.).
            var hasEmptyLatent = false
            for (nodeID, node) in mutableWorkflow {
                guard let nodeDict = node as? [String: Any], let classType = nodeDict["class_type"] as? String else { continue }
                if classType.contains("Empty") && classType.contains("Latent") {
                    if var inputs = nodeDict["inputs"] as? [String: Any] {
                        inputs["batch_size"] = 1
                        var updatedNode = nodeDict
                        updatedNode["inputs"] = inputs
                        mutableWorkflow[nodeID] = updatedNode
                        hasEmptyLatent = true
                        Log.debug("Batch size forced to 1 in node \(nodeID) for per-run seeding")
                        break
                    }
                }
            }
            if !hasEmptyLatent {
                Log.debug("No EmptyLatentImage node found; assuming i2i or custom workflow.")
            }
            
            let clientId = UUID().uuidString
            guard let wsURL = ComfyUIEndpoints.webSocketURL(serverURL: comfyServerURL, clientID: clientId) else {
                throw GenerationError.invalidWebSocketURL
            }
            let session = URLSession(configuration: .default)
            webSocketTask = session.webSocketTask(with: wsURL)
            webSocketTask?.resume()
            isCancelled = false
            
            Task {
                var isComplete = false
                while let task = webSocketTask, !isCancelled {
                    try Task.checkCancellation()
                    
                    do {
                        let message = try await task.receive()
                        switch message {
                        case .string(let text):
                            if let data = text.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let type = json["type"] as? String {
                                if type == "progress",
                                   let value = json["data"] as? [String: Any],
                                   let current = value["value"] as? Int,
                                   let max = value["max"] as? Int {
                                    await MainActor.run {
                                        progressStep = current
                                        progressMax = max
                                        progress = max > 0 ? Double(current) / Double(max) : 0.0
                                    }
                                } else if type == "executing",
                                          let value = json["data"] as? [String: Any],
                                          let nodeId = value["node"] as? String {
                                    // Look up node name from workflow
                                    let nodeName = self.getNodeDisplayName(nodeId: nodeId)
                                    await MainActor.run {
                                        currentNodeName = nodeName
                                    }
                                    Log.debug("Executing node: \(nodeId) (\(nodeName ?? "unknown"))")
                                } else if type == "executing",
                                          let value = json["data"] as? [String: Any],
                                          value["node"] == nil {
                                    await MainActor.run {
                                        currentNodeName = nil
                                    }
                                    isComplete = true
                                } else if type == "execution_success" {
                                    await MainActor.run {
                                        currentNodeName = nil
                                    }
                                    isComplete = true
                                }
                            }
                        default: break
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        await MainActor.run {
                            let nsError = error as NSError
                            Log.debug("WebSocket error caught: domain=\(nsError.domain), code=\(nsError.code), desc=\(error.localizedDescription), isCancelled=\(isCancelled), isComplete=\(isComplete)")
                            if !((isCancelled || isComplete) && nsError.domain == NSPOSIXErrorDomain && nsError.code == 57) {
                                errorItem = AlertError(message: error.localizedDescription, fullMessage: nil)
                            }
                        }
                        break
                    }
                }
            }
            let selectedImageNodes = Array(appState.generation.selectedImageNodeIDs).sorted()

            if !selectedImageNodes.isEmpty && appState.ui.imageSlots.isEmpty {
                Log.debug("Warning: \(selectedImageNodes.count) image node(s) selected but no input images provided")
                await MainActor.run {
                    errorItem = AlertError(
                        message: "No input images",
                        fullMessage: "This workflow has \(selectedImageNodes.count) image input node(s) selected but no images are loaded. Add images or uncheck the image nodes in ComfyUI Advanced Settings."
                    )
                }
                return
            }

            let promptNodeID = appState.generation.comfyPromptNodeID
            let selectedPromptText = appState.generation.promptNodes.first(where: { $0.id == promptNodeID })?.promptText ?? ""
            let basePrompt = appState.prompt.isEmpty ? selectedPromptText : appState.prompt
            let effectivePrompt = StyleManager.applyStyles(
                Array(appState.ui.selectedStyles),
                to: basePrompt
            )

            // Prompt injection is best-effort — workflows may use subgraph nodes or
            // non-standard prompt nodes that we can't inject into. In that case we
            // continue and rely on additional inputs or the workflow's embedded prompt.
            var promptInjected = false
            if !effectivePrompt.isEmpty, !promptNodeID.isEmpty,
               var node = mutableWorkflow[promptNodeID] as? [String: Any],
               var inputs = node["inputs"] as? [String: Any] {
                for (key, value) in inputs {
                    let lowerKey = key.lowercased()
                    // Traditional text key check (applies to both String and link values)
                    let isTraditionalTextKey = (lowerKey.contains("prompt") && !lowerKey.contains("negativ")) ||
                                                lowerKey.contains("text") ||
                                                lowerKey.contains("positiv")
                    // "value" key check (only for String values — too generic for links)
                    let isValueKey = lowerKey.contains("value")

                    if value is String, isTraditionalTextKey || isValueKey {
                        inputs[key] = effectivePrompt
                        promptInjected = true
                    } else if let link = value as? [Any], link.count == 2, isTraditionalTextKey {
                        // Replace ComfyUI link with literal prompt text
                        inputs[key] = effectivePrompt
                        promptInjected = true
                    }
                }
                if promptInjected {
                    node["inputs"] = inputs
                    mutableWorkflow[promptNodeID] = node
                }
            }
            if !promptInjected {
                Log.debug("Prompt injection skipped — node '\(promptNodeID)' has no injectable text inputs. Using additional inputs or embedded prompt.")
            }

            // Inject additional text inputs
            for input in appState.generation.additionalInputs where input.inputType == .text {
                guard !input.boundNodeID.isEmpty,
                      let textValue = input.textValue,
                      !textValue.isEmpty else { continue }

                if var node = mutableWorkflow[input.boundNodeID] as? [String: Any],
                   var inputs = node["inputs"] as? [String: Any] {
                    // Use the specified input key, or try common text keys
                    let inputKey = input.boundInputKey.isEmpty ? "text" : input.boundInputKey
                    if inputs[inputKey] != nil {
                        inputs[inputKey] = textValue
                    } else {
                        // Try to find any string input key
                        for (key, value) in inputs {
                            if value is String {
                                inputs[key] = textValue
                                break
                            }
                        }
                    }
                    node["inputs"] = inputs
                    mutableWorkflow[input.boundNodeID] = node
                    Log.debug("Injected additional text input '\(input.displayName)' into node \(input.boundNodeID)")
                }
            }

            // Resolve all literal text before either primary or additional image uploads.
            let mappedInputs = appState.generation.savedWorkflowID.flatMap { id in WorkflowLibrary.shared.workflows.first { $0.id == id }?.exposedInputs } ?? []
            try WorkflowInputResolver.validateDefinitions(mappedInputs, graph: mutableWorkflow, objectInfo: objectInfo)
            try WorkflowInputResolver.checkPromptValues(in: mutableWorkflow, definitions: mappedInputs)
            try WorkflowPromptSafety.requireSafe(mutableWorkflow, selectedPromptNodeID: promptNodeID)

            var uploadedFilenames: [String] = []
            if !selectedImageNodes.isEmpty && !appState.ui.imageSlots.isEmpty {
                for i in 0..<min(selectedImageNodes.count, appState.ui.imageSlots.count) {
                    let slot = appState.ui.imageSlots[i]
                    
                    // Load the full-resolution image from disk (never from memory)
                    guard let fullURL = slot.fullResolutionURL,
                          let fullImage = PlatformImage(contentsOfFile: fullURL.path) else {
                        Log.debug("Warning: Could not load full image for slot \(i) – skipping upload")
                        continue
                    }
                    
                    // Process the full image for upload (PNG format for ComfyUI)
                    guard let processed = processImageForUpload(
                        image: fullImage,
                        originalData: slot.originalData,
                        format: "png"
                    ) else {
                        Log.debug("Warning: Failed to process image for upload in slot \(i)")
                        continue
                    }
                    
                    // Build multipart upload
                    guard let uploadImageURL = ComfyUIEndpoints.uploadImageURL(serverURL: comfyServerURL) else {
                        throw GenerationError.invalidServerURL
                    }
                    var uploadRequest = URLRequest(url: uploadImageURL)
                    uploadRequest.httpMethod = "POST"

                    let boundary = "Boundary-\(UUID().uuidString)"
                    uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

                    var body = Data()
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    let fileExtension = processed.mimeType == "image/jpeg" ? "jpg" : "png"
                    body.append("Content-Disposition: form-data; name=\"image\"; filename=\"input_\(i).\(fileExtension)\"\r\n".data(using: .utf8)!)
                    body.append("Content-Type: \(processed.mimeType)\r\n\r\n".data(using: .utf8)!)
                    body.append(processed.data)
                    body.append("\r\n".data(using: .utf8)!)
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    body.append("Content-Disposition: form-data; name=\"type\"\r\n\r\ninput\r\n".data(using: .utf8)!)
                    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                    
                    uploadRequest.httpBody = body
                    
                    do {
                        try Task.checkCancellation()
                        let (data, response) = try await URLSession.shared.data(for: uploadRequest)
                        
                        guard let httpResponse = response as? HTTPURLResponse,
                              (200...299).contains(httpResponse.statusCode) else {
                            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                            let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                            Log.debug("Upload failed with status \(statusCode): \(bodyString)")
                            throw GenerationError.uploadFailed("HTTP \(statusCode)")
                        }
                        
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let name = json["name"] as? String {
                            uploadedFilenames.append(name)
                            Log.debug("Successfully uploaded image for slot \(i): \(name)")
                        } else {
                            let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                            Log.debug("Upload succeeded but no filename returned: \(bodyString)")
                            // Still continue – some ComfyUI versions don't return "name"
                            uploadedFilenames.append("input_\(i).\(fileExtension)")
                        }
                        
                    } catch {
                        Log.debug("Upload error for slot \(i): \(error.localizedDescription)")
                        throw error
                    }
                }
                
                for i in 0..<uploadedFilenames.count {
                    let nodeID = selectedImageNodes[i]
                    if var node = mutableWorkflow[nodeID] as? [String: Any],
                       var inputs = node["inputs"] as? [String: Any] {
                        inputs["image"] = uploadedFilenames[i]
                        node["inputs"] = inputs
                        mutableWorkflow[nodeID] = node
                    } else {
                        throw GenerationError.invalidImageNode
                    }
                }
            }
            
            // Upload and inject additional image inputs
            for input in appState.generation.additionalInputs where input.inputType == .image {
                guard !input.boundNodeID.isEmpty,
                      let imageData = appState.generation.additionalInputImages[input.id],
                      let fullURL = imageData.fullResolutionURL,
                      let fullImage = PlatformImage(contentsOfFile: fullURL.path) else { continue }

                // Process image for upload
                guard let processed = processImageForUpload(
                    image: fullImage,
                    originalData: imageData.originalData,
                    format: "png"
                ) else {
                    Log.debug("Warning: Failed to process additional image input '\(input.displayName)'")
                    continue
                }

                // Build multipart upload
                guard let uploadImageURL = ComfyUIEndpoints.uploadImageURL(serverURL: comfyServerURL) else {
                    Log.debug("Warning: Invalid ComfyUI server URL — skipping additional image input '\(input.displayName)'")
                    continue
                }
                var uploadRequest = URLRequest(url: uploadImageURL)
                uploadRequest.httpMethod = "POST"

                let boundary = "Boundary-\(UUID().uuidString)"
                uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"image\"; filename=\"additional_\(input.id.uuidString).png\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: \(processed.mimeType)\r\n\r\n".data(using: .utf8)!)
                body.append(processed.data)
                body.append("\r\n".data(using: .utf8)!)
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"type\"\r\n\r\ninput\r\n".data(using: .utf8)!)
                body.append("--\(boundary)--\r\n".data(using: .utf8)!)

                uploadRequest.httpBody = body

                do {
                    try Task.checkCancellation()
                    let (data, response) = try await URLSession.shared.data(for: uploadRequest)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        Log.debug("Additional image upload failed with status \(statusCode)")
                        continue
                    }

                    var uploadedFilename = "additional_\(input.id.uuidString).png"
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let name = json["name"] as? String {
                        uploadedFilename = name
                    }

                    // Inject filename into the bound node
                    let inputKey = input.boundInputKey.isEmpty ? "image" : input.boundInputKey
                    if var node = mutableWorkflow[input.boundNodeID] as? [String: Any],
                       var inputs = node["inputs"] as? [String: Any] {
                        inputs[inputKey] = uploadedFilename
                        node["inputs"] = inputs
                        mutableWorkflow[input.boundNodeID] = node
                        Log.debug("Injected additional image input '\(input.displayName)' into node \(input.boundNodeID): \(uploadedFilename)")
                    }

                } catch {
                    Log.debug("Additional image upload error for '\(input.displayName)': \(error.localizedDescription)")
                }
            }

            // Backfill missing required inputs using object_info from server
            let (backfilledWorkflow, backfillInjected) = ComfyUIFormatConverter.backfillMissingDefaults(
                workflow: mutableWorkflow, objectInfo: objectInfo
            )
            mutableWorkflow = backfilledWorkflow
            if !backfillInjected.isEmpty {
                Log.debug("Backfilled \(backfillInjected.count) missing node inputs: \(backfillInjected.map { "\($0.classType).\($0.inputName)=\($0.value)" }.joined(separator: ", "))")
            }

            // Pre-submit required-input validation: anything still missing after the
            // backfill would be rejected by the server with an opaque 400 — report it
            // clearly instead. Only runs when object_info is available.
            if !objectInfo.isEmpty {
                // Only validate nodes the server would actually run: ComfyUI executes the
                // dependency chains of output nodes, so orphaned/disconnected nodes never
                // trigger a 400 and must not fail our pre-submit gate. (finding #1)
                let reachable = ComfyUIFormatConverter.reachableFromOutputs(workflow: mutableWorkflow)
                let stillMissing = ComfyUIFormatConverter.missingRequiredInputs(
                    workflow: mutableWorkflow, objectInfo: objectInfo, restrictTo: reachable
                )
                if !stillMissing.isEmpty {
                    throw GenerationError.missingWorkflowInputs(
                        "Missing required inputs:\n" + stillMissing.joined(separator: "\n")
                    )
                }
            }

            var outputImages: [PlatformImage?] = []
            var outputTexts: [String] = []
            var outputPaths: [String?] = []
            var videoHasAudioFlags: [Bool] = []  // Track audio status for videos
            // Per-batch-item task classification, appended alongside videoHasAudioFlags at
            // exactly the same two points below so the two arrays stay index-aligned. Uses
            // `isVideoFile` (not the broader `isVideoOutput`, which also covers animated
            // gif/webp) — the same flag that already drives `saveGeneratedMedia(isVideo:)`.
            var isVideoTaskFlags: [Bool] = []
            var failedBatchItems: [(index: Int, error: String)] = []
            var workflowOutputIDs: [UUID] = []
            var workflowJobIDs: [String] = []
            var workflowPromptIDs: [String] = []

            let batchSize = appState.settings.comfyBatchSize
            let workflowName = URL(fileURLWithPath: appState.settings.comfyJSONPath).deletingPathExtension().lastPathComponent

            // Extract the original seed from the mutableWorkflow once (for reference in output text if needed)
            var originalSeed: Int? = nil
            if let seedNodeID = seedNodeID,
               let seedNode = mutableWorkflow[seedNodeID] as? [String: Any],
               let inputs = seedNode["inputs"] as? [String: Any],
               let seed = inputs[seedKey] as? Int {
                originalSeed = seed
            }

            for batchIndex in 0..<batchSize {
                try Task.checkCancellation()
                var durableJob: AgentImageJob?
                defer { if let job = durableJob { appState.workflowJobs.finishTracking(job.id) } }
                do {
                    var runWorkflow = mutableWorkflow

                    var usedSeed: Int?
                    if let seedNodeID = seedNodeID {
                        if batchSize == 1 || batchIndex == 0 {
                            // Use the existing/user's seed from the workflow (no overwrite)
                            usedSeed = originalSeed ?? Int.random(in: 0...Int.max)
                            Log.debug("Using existing seed \(usedSeed!) for batch item \(batchIndex + 1)")
                        } else {
                            // Generate new random seed for batch items 2...n when batchSize > 1
                            usedSeed = Int.random(in: 0...Int.max)
                            if var seedNode = runWorkflow[seedNodeID] as? [String: Any],
                               var inputs = seedNode["inputs"] as? [String: Any] {
                                inputs[seedKey] = usedSeed
                                seedNode["inputs"] = inputs
                                runWorkflow[seedNodeID] = seedNode
                                Log.debug("Set new seed \(usedSeed!) for batch item \(batchIndex + 1)")
                            }
                        }
                    }

                    try WorkflowInputResolver.checkPromptValues(in: runWorkflow, definitions: mappedInputs)
                    try WorkflowPromptSafety.requireSafe(runWorkflow, selectedPromptNodeID: promptNodeID)
                    let transport = try ComfyUITransport(serverURL: comfyServerURL)
                    let savedWorkflow = appState.generation.savedWorkflowID.flatMap { id in WorkflowLibrary.shared.workflows.first { $0.id == id } }
                    durableJob = try appState.workflowJobs.begin(WorkflowRecoverySnapshot(
                        workflowID: savedWorkflow?.id, workflowRevision: savedWorkflow?.revision,
                        graphDigest: try WorkflowRecoverySnapshot.digest(runWorkflow), serverURL: transport.serverURL,
                        selectedOutputNodeID: appState.generation.comfyOutputNodeID, workflowName: workflowName,
                        displayPrompt: effectivePrompt))
                    let promptId = try await transport.submit(apiWorkflow: runWorkflow, clientID: clientId,
                        persistIntent: {
                            guard let job = durableJob else { throw AgentImageError("Workflow intent is missing.") }
                            try appState.workflowJobs.update(job)
                        }, persistPromptID: { id in
                            guard var job = durableJob else { throw AgentImageError("Workflow intent is missing.") }
                            job.workflow?.promptID = id; job.status = "queued"; durableJob = job
                            try appState.workflowJobs.update(job)
                        })
                    var retryCount = 0
                    let maxRetries = 3

                    var history: [String: Any]? = nil
                    var pollingStartTime = Date()
                    let timeoutSeconds = appState.settings.comfyGenerationTimeout
                    var networkErrorCount = 0

                    while history == nil {
                        try Task.checkCancellation()
                        try await Task.sleep(nanoseconds: 2_000_000_000)

                        // Check for timeout
                        let elapsed = Int(Date().timeIntervalSince(pollingStartTime))
                        if elapsed >= timeoutSeconds {
                            // Show timeout dialog and wait for user response
                            let shouldContinue = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                                Task { @MainActor in
                                    self.timeoutContinuation = continuation
                                    self.showTimeoutAlert = true
                                }
                            }
                            if !shouldContinue {
                                // User chose to cancel
                                throw CancellationError()
                            }
                            // User chose to keep waiting - reset the start time for another timeout period
                            pollingStartTime = Date()
                        }

                        do {
                            try Task.checkCancellation()
                            let entry = try await transport.history(promptID: promptId)
                            networkErrorCount = 0
                            if let entry, let status = entry["status"] as? [String: Any], status["completed"] as? Bool == true { history = entry }
                        } catch let error as URLError {
                            networkErrorCount += 1
                            Log.debug("History fetch network error (\(networkErrorCount)): \(error.localizedDescription)")
                            // After 3 consecutive network errors, offer retry dialog
                            if networkErrorCount >= 3 {
                                let shouldRetry = await showRetryDialog(message: "Lost connection to ComfyUI server:\n\(error.localizedDescription)\n\nRetry?")
                                if !shouldRetry {
                                    throw error
                                }
                                networkErrorCount = 0
                            }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch let error as GenerationError {
                            throw error
                        } catch {
                            throw error
                        }
                    }

                    guard let unwrappedHistory = history else {
                        throw GenerationError.noOutputImage
                    }
                    guard let outputs = unwrappedHistory["outputs"] as? [String: Any] else {
                        throw GenerationError.noOutputImage
                    }
                    // Prefer the user-selected output node; if it didn't produce media (e.g. it was
                    // bypassed, or newer ComfyUI assigned different keys), fall back to any output
                    // node that actually emitted images/gifs/videos.
                    func nodeHasMedia(_ node: [String: Any]) -> Bool {
                        return (node["images"] as? [[String: Any]])?.isEmpty == false ||
                               (node["gifs"] as? [[String: Any]])?.isEmpty == false ||
                               (node["videos"] as? [[String: Any]])?.isEmpty == false
                    }
                    let outputNode: [String: Any]
                    if let selected = outputs[appState.generation.comfyOutputNodeID] as? [String: Any], nodeHasMedia(selected) {
                        outputNode = selected
                    } else if let fallback = outputs.values.compactMap({ $0 as? [String: Any] }).first(where: nodeHasMedia) {
                        Log.debug("Selected output node had no media; using a fallback output node")
                        outputNode = fallback
                    } else {
                        // 'completed' can fire before output files are flushed to disk on recent
                        // ComfyUI servers (Comfy-Org/ComfyUI#11540). Re-poll history a few times
                        // before giving up.
                        var recovered: [String: Any]? = nil
                        for _ in 0..<3 {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            guard let rentry = try? await transport.history(promptID: promptId),
                                  let routs = rentry["outputs"] as? [String: Any] else { continue }
                            if let sel = routs[appState.generation.comfyOutputNodeID] as? [String: Any], nodeHasMedia(sel) {
                                recovered = sel; break
                            } else if let fb = routs.values.compactMap({ $0 as? [String: Any] }).first(where: nodeHasMedia) {
                                recovered = fb; break
                            }
                        }
                        if let node = recovered {
                            Log.debug("Recovered ComfyUI outputs on retry after completion")
                            outputNode = node
                        } else {
                            throw GenerationError.noOutputImage
                        }
                    }

                    // Check for different output keys: images, gifs, videos
                    // VHS_VideoCombine uses "gifs", other nodes may use "videos" or "images"
                    let mediaItems: [[String: Any]]
                    let isVideoOutput: Bool

                    if let gifs = outputNode["gifs"] as? [[String: Any]], !gifs.isEmpty {
                        mediaItems = gifs
                        isVideoOutput = true
                        Log.debug("Found video output in 'gifs' key")
                    } else if let videos = outputNode["videos"] as? [[String: Any]], !videos.isEmpty {
                        mediaItems = videos
                        isVideoOutput = true
                        Log.debug("Found video output in 'videos' key")
                    } else if let images = outputNode["images"] as? [[String: Any]], !images.isEmpty {
                        mediaItems = images
                        // Check if this is a video node type or if the file extension suggests video
                        let nodeClassType = appState.generation.outputNodes.first { $0.id == appState.generation.comfyOutputNodeID }?.classType ?? ""
                        let isVideoNode = GenerationState.videoOutputNodeTypes.contains(nodeClassType) ||
                                          nodeClassType.lowercased().contains("video") ||
                                          nodeClassType.lowercased().contains("animated")
                        // Also check file extension
                        let firstFilename = (images.first?["filename"] as? String)?.lowercased() ?? ""
                        let hasVideoExtension = firstFilename.hasSuffix(".mp4") || firstFilename.hasSuffix(".webm") ||
                                                firstFilename.hasSuffix(".gif") || firstFilename.hasSuffix(".webp") ||
                                                firstFilename.hasSuffix(".mov") || firstFilename.hasSuffix(".avi")
                        isVideoOutput = isVideoNode || hasVideoExtension
                        Log.debug("Found output in 'images' key, isVideoOutput: \(isVideoOutput)")
                    } else {
                        throw GenerationError.noOutputImage
                    }

                    Log.debug("Fetched media items count for batch \(batchIndex + 1): \(mediaItems.count), isVideo: \(isVideoOutput)")

                    guard let mediaDict = mediaItems.first else { continue }
                    guard let filename = mediaDict["filename"] as? String,
                          let subfolder = mediaDict["subfolder"] as? String,
                          let type = mediaDict["type"] as? String else { continue }

                    let descriptor = ComfyUIOutput(id: "selected:0", nodeID: appState.generation.comfyOutputNodeID,
                        filename: filename, subfolder: subfolder, type: type, kind: isVideoOutput ? "videos" : "images")
                    if var job = durableJob {
                        job.workflow?.outputs = [descriptor]; job.status = "downloading"; durableJob = job
                        try appState.workflowJobs.update(job)
                    }

                    // Fetch media with retry support
                    var viewData: Data?
                    retryCount = 0

                    while viewData == nil {
                        try Task.checkCancellation()
                        do {
                            viewData = try await transport.download(descriptor)
                        } catch let error as URLError {
                            retryCount += 1
                            if retryCount <= maxRetries {
                                let mediaType = isVideoOutput ? "video" : "image"
                                let shouldRetry = await showRetryDialog(message: "Failed to download \(mediaType) (attempt \(retryCount)/\(maxRetries)):\n\(error.localizedDescription)\n\nRetry?")
                                if !shouldRetry {
                                    throw error
                                }
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                            } else {
                                throw error
                            }
                        }
                    }

                    guard let mediaData = viewData else {
                        throw GenerationError.decodeFailed
                    }

                    // Handle video vs image output
                    if isVideoOutput {
                        // Determine video extension from filename
                        let originalExtension = (filename as NSString).pathExtension.lowercased()
                        let isAnimatedImage = originalExtension == "gif" || originalExtension == "webp"
                        let isVideoFile = originalExtension == "mp4" || originalExtension == "webm" || originalExtension == "mov" || originalExtension == "avi"

                        // Determine the extension to use for saving
                        let saveExtension: String
                        if isVideoFile {
                            saveExtension = originalExtension
                        } else if isAnimatedImage {
                            saveExtension = originalExtension
                        } else {
                            // Default to mp4 for unknown video formats
                            saveExtension = "mp4"
                        }

                        // Save as video/animation with correct extension
                        guard let savedPath = saveGeneratedMedia(
                            data: mediaData,
                            prompt: effectivePrompt,
                            mode: .comfyUI,
                            modelUsed: workflowName,
                            batchIndex: batchIndex,
                            totalInBatch: batchSize,
                            isVideo: isVideoFile,
                            fileExtension: saveExtension
                        )?.path else { throw AgentImageError("Workflow output could not be saved. Recover this job without resubmitting.") }

                        // Detect if video has audio tracks
                        var hasAudio = false
                        if isVideoFile {
                            hasAudio = await detectVideoHasAudio(at: savedPath)
                            Log.debug("ComfyUI video audio detection: hasAudio = \(hasAudio)")
                        }

                        // For animated formats, try to get first frame as thumbnail
                        let thumbnail: PlatformImage? = isAnimatedImage ? PlatformImage(platformData: mediaData) : nil

                        outputImages.append(thumbnail)
                        let mediaType = isVideoFile ? "video" : "animation"
                        let seedInfo = usedSeed.map { "seed: \($0)" } ?? "no seed node"
                        outputTexts.append("Batch \(mediaType) \(batchIndex + 1) generated with ComfyUI (\(seedInfo)). Saved to \(userFriendlyPath(savedPath))")
                        outputPaths.append(savedPath)
                        videoHasAudioFlags.append(hasAudio)
                        isVideoTaskFlags.append(isVideoFile)

                        Log.debug("Saved ComfyUI \(mediaType) output: \(filename) -> \(savedPath)")
                    } else {
                        // Handle as image
                        guard let platformImage = PlatformImage(platformData: mediaData) else {
                            throw GenerationError.decodeFailed
                        }

                        guard let savedPath = saveGeneratedImage(data: mediaData, prompt: effectivePrompt, mode: .comfyUI, workflowName: workflowName, batchIndex: batchIndex, totalInBatch: batchSize)?.path else { throw AgentImageError("Workflow output could not be saved. Recover this job without resubmitting.") }
                        outputImages.append(platformImage)
                        let seedInfo = usedSeed.map { "seed: \($0)" } ?? "no seed node"
                        outputTexts.append("Batch image \(batchIndex + 1) generated with ComfyUI (\(seedInfo)). Saved to \(userFriendlyPath(savedPath))")
                        outputPaths.append(savedPath)
                        videoHasAudioFlags.append(false)  // Images don't have audio
                        isVideoTaskFlags.append(false)
                    }

                    if var job = durableJob, let snapshot = job.workflow {
                        workflowOutputIDs.append(snapshot.assetID)
                        workflowJobIDs.append(job.id)
                        workflowPromptIDs.append(promptId)
                        job.workflow?.localPath = outputPaths.last ?? nil
                        job.workflow?.isVideo = isVideoTaskFlags.last ?? false
                        job.status = "saving"; durableJob = job
                        try appState.workflowJobs.update(job)
                    }

                    await MainActor.run {
                        appState.ui.outputImages = outputImages
                        appState.ui.outputTexts = outputTexts
                        appState.ui.outputPaths = outputPaths
                        appState.ui.currentOutputIndex = outputImages.count - 1
                        Log.debug("Updated UI with \(outputImages.count) images so far")
                    }

                } catch is CancellationError {
                    if var job = durableJob {
                        job.status = job.workflow?.promptID == nil ? "submission_unknown" : "recoverable"
                        job.message = "Stopped waiting locally. The server may continue; recovery will not generate again."
                        try? appState.workflowJobs.update(job)
                    }
                    throw CancellationError()
                } catch {
                    if var job = durableJob {
                        job.status = job.workflow?.promptID == nil ? "submission_unknown" : "recoverable"
                        if error is ComfyUISubmissionRejected { job.status = "failed"; job.billing = "not_submitted" }
                        job.message = ProviderFailure.redact(error.localizedDescription)
                        try? appState.workflowJobs.update(job)
                    }
                    // Track this failure but continue with remaining items
                    let errorMessage = (error as? GenerationError)?.errorDescription ?? error.localizedDescription
                    failedBatchItems.append((index: batchIndex + 1, error: errorMessage))
                    Log.debug("Batch item \(batchIndex + 1) failed: \(errorMessage)")

                    // If this is the only item or all items have failed so far, throw to stop
                    if batchSize == 1 || (failedBatchItems.count == batchIndex + 1 && outputImages.isEmpty) {
                        throw error
                    }
                    // Otherwise continue with next batch item
                }
            }

            // Report partial failures if any succeeded
            if !failedBatchItems.isEmpty && !outputImages.isEmpty {
                let failedIndices = failedBatchItems.map { String($0.index) }.joined(separator: ", ")
                let warningText = "Warning: \(failedBatchItems.count) of \(batchSize) images failed (items: \(failedIndices))"
                Log.debug(warningText)
                // Append warning to the last output text
                if !outputTexts.isEmpty {
                    outputTexts[outputTexts.count - 1] += "\n\n\(warningText)"
                    await MainActor.run {
                        appState.ui.outputTexts = outputTexts
                    }
                }
            }
            
            let batchId = outputImages.count > 1 ? UUID() : nil
            let total = outputImages.count
            guard workflowOutputIDs.count == total, workflowPromptIDs.count == total else {
                throw AgentImageError("Workflow output records are incomplete. Recover the existing jobs from Jobs.")
            }
            for i in 0..<total {
                let newItem = HistoryItem(
                    id: workflowOutputIDs[i],
                    prompt: finalPrompt,
                    responseText: outputTexts[i],
                    imagePath: outputPaths[i],
                    date: Date(),
                    mode: appState.settings.provider,
                    task: CreateTask(isVideo: i < isVideoTaskFlags.count ? isVideoTaskFlags[i] : false),
                    workflowName: workflowName,
                    modelUsed: nil,
                    batchId: batchId,
                    indexInBatch: i,
                    totalInBatch: total,
                    jobId: workflowPromptIDs[i],
                    status: .completed,
                    videoHasAudio: i < videoHasAudioFlags.count ? videoHasAudioFlags[i] : nil,
                    customAIMLPayload: nil, // Explicitly nil for ComfyUI mode
                    customAIMLEndpoint: nil // Explicitly nil for ComfyUI mode
                )
                appState.historyState.history.append(.item(newItem))
                appState.ui.sessionGeneratedIDs.append(newItem.id)  // Track in session gallery
            }
            try appState.historyState.saveHistoryNow()
            for id in workflowJobIDs { try appState.workflowJobs.markCompleted(id) }

            // Auto-present or show toast
            await MainActor.run {
                triggerGenerationPresentation(imageCount: outputImages.compactMap { $0 }.count, appState: appState)
            }

            isCancelled = true
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            progress = 0.0
            progressStep = 0
            progressMax = 0
            currentNodeName = nil

        case .grok:
            let grokVideoMode = appState.settings.isVideoMode
            let grokImageModel = appState.settings.selectedGrokModel
            let grokDuration = appState.settings.grokVideoDuration
            let grokVideoAspect = appState.settings.grokVideoAspectRatio
            let grokVideoResolution = appState.settings.grokVideoResolution
            let grokAudio = appState.settings.grokVideoAudio
            let grokKey = appState.settings.grokApiKey
            let grokAspect = appState.settings.grokAspectRatio
            let grokResolution = appState.settings.grokResolution
            let grokSlots = appState.ui.imageSlots
            if !(await showPrivacyNotice(for: .grok)) {
                throw GenerationError.apiError("User declined privacy notice.")
            }
            
            var imageDataURI: String?
            let loadedSlots = grokSlots.filter { $0.fullResolutionURL != nil }
            if !loadedSlots.isEmpty {
                guard (grokVideoMode || GrokClient.supportsEditing(model: grokImageModel)), loadedSlots.count == 1 else {
                    throw GenerationError.apiError(grokVideoMode ? "Provide at most one image to animate." : "Choose Grok Imagine Image 2.0 and provide one reference image for editing.")
                }
                guard let url = loadedSlots[0].fullResolutionURL,
                      let image = PlatformImage(contentsOfFile: url.path),
                      let processed = processImageForUpload(image: image, originalData: loadedSlots[0].originalData,
                          format: "jpeg", isBase64: true, convertToJPG: true,
                          scale50Percent: appState.settings.base64Scale50Percent) else {
                    throw GenerationError.apiError("The reference image could not be read. Add it again before editing.")
                }
                imageDataURI = "data:\(processed.mimeType);base64,\(processed.data.base64EncodedString())"
            }
            if grokVideoMode {
                let body = try GrokVideoClient.requestBody(prompt: finalPrompt,
                    duration: grokDuration, aspectRatio: grokVideoAspect,
                    resolution: grokVideoResolution, audio: grokAudio,
                    imageDataURI: imageDataURI)
                let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
                var request = URLRequest(url: GrokVideoClient.generationsURL, timeoutInterval: 300)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(grokKey)", forHTTPHeaderField: "Authorization")
                request.httpBody = data
                let jobID = videoJobID ?? appState.jobQueue.beginJob(modelId: GrokVideoClient.model, prompt: finalPrompt)
                try await appState.jobQueue.runPreparedJob(jobID: jobID, request: VideoJobRequest(
                    urlRequest: request, modelId: GrokVideoClient.model, prompt: finalPrompt,
                    pollingEndpoint: GrokVideoClient.pollingEndpoint,
                    submittedEndpoint: GrokVideoClient.generationsURL.absoluteString,
                    submittedPayload: String(data: data, encoding: .utf8), apiKey: grokKey,
                    provider: .grok), onPosted: { onVideoJobPosted?() })
                return
            }
            let bodyDict = GrokClient.imageRequestBody(
                model: grokImageModel,
                prompt: finalPrompt,
                aspectRatio: grokAspect,
                resolution: grokResolution,
                imageDataURI: imageDataURI
            )

            var request = URLRequest(url: imageDataURI == nil ? GrokClient.imageGenerationsURL : GrokClient.imageEditsURL, timeoutInterval: 360)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let auth = GrokClient.authorizationHeader(apiKey: grokKey)
            request.addValue(auth.value, forHTTPHeaderField: auth.name)
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
            } catch {
                throw GenerationError.encodingFailed(error.localizedDescription)
            }
            
            try Task.checkCancellation()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let bodyString = String(data: data, encoding: .utf8) ?? "No body"
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                // Logged as well as thrown. The thrown value reaches a modal alert and is gone the
                // moment it is dismissed, which made a reproducible 2026-07-28 validation failure
                // uninvestigable after the fact. The request keys go with it because a validation
                // error is almost always about *which* keys and values were sent — the prompt is
                // deliberately not logged.
                Log.error("Grok image generation failed — model=\(grokImageModel) "
                          + "status=\(status) "
                          + "sentKeys=\(bodyDict.keys.sorted().joined(separator: ",")) body=\(bodyString)")
                throw GenerationError.apiError(ProviderFailure.message(provider: .grok, status: status, body: data, phase: .submission))
            }

            let responseDecoded = try JSONDecoder().decode(OpenAICompatible.ImageResponse.self, from: data)
            if let error = responseDecoded.error {
                Log.error("Grok image generation returned an error object — "
                          + "model=\(grokImageModel) "
                          + "sentKeys=\(bodyDict.keys.sorted().joined(separator: ",")) "
                          + "message=\(error.message ?? "nil")")
                let formattedError = OpenAICompatible.formatError(error)
                await MainActor.run {
                    appState.ui.outputTexts = [formattedError]
                    appState.ui.outputImages = []
                    appState.ui.outputPaths = []
                }
                throw GenerationError.apiError(error.message ?? "Unknown error")
            }

            // Check for empty data array (model returned nothing)
            if responseDecoded.data.isEmpty {
                await MainActor.run {
                    appState.ui.outputTexts = ["No images generated. The model may have declined to generate content for this prompt."]
                    appState.ui.outputImages = []
                    appState.ui.outputPaths = []
                }
                throw GenerationError.apiError("Empty response from model")
            }

            var recoveredIDs: [Int: UUID] = [:]
            var images: [PlatformImage?] = []
            var texts: [String] = []
            var paths: [String?] = []
            
            let total = responseDecoded.data.count
            for (i, item) in responseDecoded.data.enumerated() {
                var textOutput = ""
                if let revised = item.revised_prompt {
                    textOutput += "Revised prompt: \(revised)\n"
                }
                
                var assetReadID: UUID?
                defer {
                    if let assetReadID {
                        let saved = recoveredIDs[i].flatMap { appState.historyState.findEntry(by: $0) }.map { entry in
                            entry.allItems.first?.status == .completed
                        } ?? false
                        appState.jobQueue.finishAssetRead(assetReadID, saved: saved)
                    }
                }
                if item.b64_json == nil, let sourceURL = item.url {
                    let recovery = HistoryItem(prompt: finalPrompt,
                        responseText: "Generated asset available. Download again if retrieval is interrupted.",
                        date: Date(), mode: .grok, task: .image, modelUsed: grokImageModel,
                        status: .failed, sourceAssetURL: sourceURL)
                    assetReadID = appState.jobQueue.beginAssetRead(recovery)
                    recoveredIDs[i] = recovery.id
                    appState.historyState.history.append(.item(recovery))
                    appState.historyState.saveHistory()
                }
                var imgData: Data?
                if let b64 = item.b64_json {
                    imgData = Data(base64Encoded: b64)
                } else if let imageUrl = item.url, let url = URL(string: imageUrl) {
                    Log.debug("Downloading original image asset")
                    let (downloadData, downloadResponse) = try await URLSession.shared.data(from: url)
                    if let httpResp = downloadResponse as? HTTPURLResponse {
                        Log.debug("Image download: HTTP \(httpResp.statusCode), \(downloadData.count) bytes")
                        guard (200...299).contains(httpResp.statusCode) else {
                            throw GenerationError.apiError("Image download failed (HTTP \(httpResp.statusCode))")
                        }
                    }
                    imgData = downloadData
                }

                if let data = imgData {
                    let image = PlatformImage(platformData: data)
                    let path = saveGeneratedImage(data: data, prompt: finalPrompt, mode: .grok, modelUsed: grokImageModel, batchIndex: i, totalInBatch: total)?.path
                    guard let savedPath = path else {
                        throw GenerationError.apiError("The generated image could not be saved. Check disk space and output-folder access. Use Download again in Jobs when a source URL is available.")
                    }
                    if let id = recoveredIDs[i], let index = appState.historyState.history.firstIndex(where: { $0.id == id }),
                       case .item(var recovery) = appState.historyState.history[index] {
                        recovery.imagePath = savedPath
                        recovery.status = .completed
                        recovery.responseText = "Original image saved"
                        appState.historyState.history[index] = .item(recovery)
                        appState.ui.sessionGeneratedIDs.append(id)
                    }
                    if let saved = path {
                        textOutput += "Image saved to \(userFriendlyPath(saved))\n"
                    }
                    images.append(image)
                    texts.append(textOutput)
                    paths.append(path)
                } else {
                    images.append(nil)
                    paths.append(nil)
                    texts.append(textOutput.isEmpty ? "No output for item \(i+1)" : textOutput)
                }
            }
            
            await MainActor.run {
                appState.ui.outputImages = images
                appState.ui.outputTexts = texts
                appState.ui.outputPaths = paths
                appState.ui.currentOutputIndex = 0
            }
            
            let batchId = images.count > 1 ? UUID() : nil
            for i in 0..<total {
                if recoveredIDs[i] != nil { continue }
                let newItem = HistoryItem(
                    prompt: finalPrompt,
                    responseText: texts[i],
                    imagePath: paths[i],
                    date: Date(),
                    mode: appState.settings.provider,
                    task: .image,  // Grok's generation path produces stills only.
                    workflowName: nil,
                    modelUsed: grokImageModel,
                    batchId: batchId,
                    indexInBatch: i,
                    totalInBatch: total,
                    jobId: nil,
                    status: nil,
                    customAIMLPayload: nil, // Explicitly nil for Grok mode
                    customAIMLEndpoint: nil // Explicitly nil for Grok mode
                )
                appState.historyState.history.append(.item(newItem))
                appState.ui.sessionGeneratedIDs.append(newItem.id)  // Track in session gallery
            }
            appState.historyState.saveHistory()

            // Auto-present or show toast
            await MainActor.run {
                triggerGenerationPresentation(imageCount: images.compactMap { $0 }.count, appState: appState)
            }

        case .aimlapi:
            if !(await showPrivacyNotice(for: .aimlapi)) {
                throw GenerationError.apiError("User declined privacy notice.")
            }

            // The release gate above already validated this selection. History lookup remains intact.
            let model = Catalog.resolve(appState.settings.selectedAIMLModel)

            let isI2I = model.id.lowercased().hasSuffix("gpt-image-1")
                ? !appState.ui.imageSlots.isEmpty
                : model.isI2I

            // Enforce requirement only if the model explicitly requires an input image
            if model.requiresInputImage && appState.ui.imageSlots.isEmpty {
                throw GenerationError.apiError("Image required for this model.")
            }
            if appState.ui.imageSlots.count > model.maxInputImages {
                throw GenerationError.apiError("Too many images for model (max: \(model.maxInputImages)).")
            }

            let preferBase64 = appState.settings.imageSubmissionMethod == .base64
            let usePublicURL = appState.settings.imageSubmissionMethod == .imgBB && model.acceptsPublicURL
            let useBinary = appState.settings.imageSubmissionMethod == .binary && model.acceptsBinary

            if appState.settings.isVideoMode {
                if appState.settings.customAIMLPayload == nil,
                   let issue = VideoRequestPolicy.parameterIssue(model: model, params: aimlParams, imageCount: appState.ui.imageSlots.count) {
                    throw GenerationError.apiError(issue)
                }
                if !appState.ui.imageSlots.isEmpty && !model.acceptsBase64 && !usePublicURL {
                    throw GenerationError.apiError("This model requires public image URLs. Select public image upload and configure ImgBB before generating.")
                }
                let urlString = appState.settings.customAIMLEndpoint ?? model.generationEndpoint
                
                guard let url = URL(string: urlString) else {
                    throw GenerationError.invalidURL
                }
                
                // Capture endpoint used for submission
                let submittedEndpoint = urlString // Store the exact endpoint used
                
                var request = URLRequest(url: url, timeoutInterval: 300)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.addValue("Bearer \(appState.settings.aimlapiKey)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Accept")
                request.addValue("identity", forHTTPHeaderField: "Accept-Encoding")

                // Initialize submittedPayload
                var submittedPayload: String? = nil
                
                var bodyDict: [String: Any]
                if let customPayload = appState.settings.customAIMLPayload,
                   let data = customPayload.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    bodyDict = parsed
                } else {
                    bodyDict = [
                        "model": appState.settings.selectedAIMLModel,
                        "prompt": finalPrompt
                    ]

                    // Add image placeholders only for I2I or I2V models using imageInputParam
                    if model.isI2I && !appState.ui.imageSlots.isEmpty {
                        let imageKey = model.imageInputParam.isEmpty ? "image" : model.imageInputParam
                        if model.acceptsMultiImages {
                            // All images go in an array under the same key
                            bodyDict[imageKey] = appState.ui.imageSlots.enumerated().map { "[image_slot_\($0.offset + 1)]" }
                        } else {
                            // First image uses imageInputParam
                            bodyDict[imageKey] = "[image_slot_1]"
                            // Second image uses secondImageParam if available
                            if let secondKey = model.secondImageParam, appState.ui.imageSlots.count > 1 {
                                bodyDict[secondKey] = "[image_slot_2]"
                            }
                        }
                    }
                    
                    // Add model-specific parameters from the model's descriptor table
                    let modelParams = ParamEncoder.encode(
                        ParamCatalog.descriptors(for: model),
                        params: aimlParams,
                        context: ParamCatalog.context(for: model, hasInputImages: !appState.ui.imageSlots.isEmpty)
                    )
                    bodyDict.merge(modelParams) { (_, new) in new }
                }
                
                // Handle image inputs only for I2V models
                if model.isI2I && !appState.ui.imageSlots.isEmpty {
                    var imageInputs: [String] = []  // ← This is used later — keep it!
                    
                    for slot in appState.ui.imageSlots {
                        // Load full image from disk
                        guard let fullURL = slot.fullResolutionURL,
                              let fullImage = PlatformImage(contentsOfFile: fullURL.path) else {
                            throw GenerationError.apiError("A video frame image could not be read. Add it again before generating.")
                        }
                        
                        // For video models with base64, always scale to avoid QUIC packet fragmentation issues
                        let forceScale = false
                        guard let processed = processImageForUpload(
                            image: fullImage,
                            originalData: slot.originalData,
                            format: "jpeg",
                            isBase64: preferBase64,
                            convertToJPG: appState.settings.base64ConvertToJPG,
                            scale50Percent: forceScale
                        ) else {
                            throw GenerationError.apiError("A video frame image could not be prepared for upload.")
                        }
                        
                        guard let encodedImage = PlatformImage(data: processed.data) else {
                            throw GenerationError.apiError("Invalid encoded video frame.")
                        }
                        let frameSize = encodedImage.size
                        if model.id == "minimax/h3-max" && (min(frameSize.width, frameSize.height) <= 300 ||
                            frameSize.width / frameSize.height <= 0.4 || frameSize.width / frameSize.height >= 2.5 || processed.data.count > 20_000_000) {
                            throw GenerationError.apiError("H3 Max frames need a short side above 300 pixels, aspect ratio between 2:5 and 5:2, and file size below 20 MB.")
                        }
                        if model.id.contains("veo-3.1") && min(frameSize.width, frameSize.height) < 720 {
                            throw GenerationError.apiError("Veo 3.1 frame images need a short side of at least 720 pixels.")
                        }
                        if usePublicURL {
                            Log.debug("Uploading video frame to ImgBB")
                            
                            guard !appState.settings.imgbbApiKey.isEmpty else {
                                throw GenerationError.apiError("ImgBB API key required for public image upload.")
                            }
                            guard ImgBBClient.isPlausibleKey(appState.settings.imgbbApiKey) else {
                                throw GenerationError.apiError("Invalid ImgBB API key format.")
                            }
                            if !(await showPrivacyNotice(for: .imgbb)) {
                                throw GenerationError.apiError("User declined ImgBB privacy notice.")
                            }

                            let uploadURL = ImgBBClient.uploadURL(apiKey: appState.settings.imgbbApiKey)
                            
                            var uploadRequest = URLRequest(url: uploadURL)
                            uploadRequest.httpMethod = "POST"
                            
                            let boundary = "Boundary-\(UUID().uuidString)"
                            uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                            
                            var body = Data()
                            body.append("--\(boundary)\r\n".data(using: .utf8)!)
                            body.append("Content-Disposition: form-data; name=\"image\"\r\n\r\n".data(using: .utf8)!)
                            body.append(processed.data.base64EncodedString().data(using: .utf8)!)
                            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                            
                            uploadRequest.httpBody = body
                            
                            let (uploadData, uploadResponseRaw) = try await URLSession.shared.data(for: uploadRequest)
                            
                            guard let httpResponse = uploadResponseRaw as? HTTPURLResponse,
                                  (200...299).contains(httpResponse.statusCode) else {
                                let bodyString = String(data: uploadData, encoding: .utf8) ?? "No body"
                                throw GenerationError.uploadFailed("ImgBB HTTP error: \(bodyString)")
                            }
                            
                            let uploadResponse = try JSONDecoder().decode(ImgBBClient.UploadResponse.self, from: uploadData)
                            guard uploadResponse.success,
                                  let imagePublicUrl = uploadResponse.data?.url else {
                                let errorMsg = uploadResponse.error?.message ?? "Unknown ImgBB error"
                                throw GenerationError.uploadFailed("ImgBB upload failed: \(errorMsg)")
                            }
                            
                            imageInputs.append(imagePublicUrl)
                            Log.debug("ImgBB upload successful: \(imagePublicUrl)")
                            
                        } else if model.acceptsBase64 {
                            let base64 = processed.data.base64EncodedString()
                            imageInputs.append("data:\(processed.mimeType);base64,\(base64)")
                        } else {
                            throw GenerationError.apiError("Model does not support image format.")
                        }
                    }
                    
                    // Replace image placeholders in bodyDict
                    let imageKey = model.imageInputParam.isEmpty ? "image" : model.imageInputParam

                    for (index, imageInput) in imageInputs.enumerated() {
                        let placeholder = "[image_slot_\(index + 1)]"

                        if model.acceptsMultiImages {
                            if var images = bodyDict[imageKey] as? [String] {
                                if index < images.count && images[index] == placeholder {
                                    images[index] = imageInput
                                    bodyDict[imageKey] = images
                                }
                            }
                        } else if index == 0 {
                            // First image – replace under imageInputParam
                            if let current = bodyDict[imageKey] as? String, current == placeholder {
                                bodyDict[imageKey] = imageInput
                            } else {
                                bodyDict[imageKey] = imageInput  // Fallback: force set
                            }
                        } else if index == 1, let secondKey = model.secondImageParam {
                            // Second image – replace under secondImageParam
                            if let current = bodyDict[secondKey] as? String, current == placeholder {
                                bodyDict[secondKey] = imageInput
                            } else {
                                bodyDict[secondKey] = imageInput  // Fallback: force set
                            }
                        }
                    }
                }
                
                if let issue = VideoRequestPolicy.payloadIssue(model: model, body: bodyDict) {
                    throw GenerationError.apiError(issue)
                }
                // Capture JSON payload
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: bodyDict, options: [.prettyPrinted, .sortedKeys])
                    submittedPayload = String(data: jsonData, encoding: .utf8)
                } catch {
                    Log.debug("Failed to capture submitted payload: \(error.localizedDescription)")
                }

                // Serialize bodyDict and set request body
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: bodyDict, options: [.prettyPrinted])
                    request.httpBody = jsonData
                } catch {
                    throw GenerationError.encodingFailed(error.localizedDescription)
                }

                // Hand off to the JobQueue: it POSTs immediately (not gated by the
                // concurrency cap), writes the pending history item, fires onPosted
                // (form clears only after a successful POST — findings A/B), then
                // acquires a poll slot and polls -> downloads -> saves. Awaiting here
                // keeps the error-alert flow; cancelling this task cancels the job.
                guard let pollingEndpoint = model.pollingEndpoint else {
                    throw GenerationError.apiError("No polling endpoint defined for model.")
                }
                let jobRequest = VideoJobRequest(
                    urlRequest: request,
                    modelId: model.id,
                    prompt: finalPrompt,
                    pollingEndpoint: pollingEndpoint,
                    submittedEndpoint: submittedEndpoint,
                    submittedPayload: submittedPayload,
                    apiKey: appState.settings.aimlapiKey
                )
                // The job record was created at submit time (in .preparing) so it
                // shows/cancels during upload; fall back to creating one if absent.
                let jobID = videoJobID
                    ?? appState.jobQueue.beginJob(modelId: appState.settings.selectedAIMLModel, prompt: finalPrompt)
                try await appState.jobQueue.runPreparedJob(jobID: jobID, request: jobRequest, onPosted: {
                    onVideoJobPosted?()
                })


                
                
                if !appState.settings.aimlapiKey.isEmpty {
                    balanceFetchTask?.cancel()
                    balanceFetchTask = Task {
                        do {
                            let balanceData = try await fetchBalance(apiKey: appState.settings.aimlapiKey)
                            if let balanceNum = balanceData["balance"] as? Double {
                                await MainActor.run {
                                    aimlBalance = balanceNum
                                    Log.debug("Updated AIMLAPI balance after video generation: \(balanceNum)")
                                }
                            }
                        } catch {
                            Log.debug("Error fetching balance after video generation: \(error.localizedDescription)")
                            await MainActor.run {
                                aimlBalance = nil
//                                errorItem = AlertError(message: "Failed to fetch balance after video generation: \(error.localizedDescription)", fullMessage: nil)
                            }
                        }
                    }
                }
            }
            else {
                // Mask-capable gpt-image models (gpt-image-1, gpt-image-2) edit via /v1/images/edits when
                // an input image is present; everything else (incl. gpt-image-1.5/-mini) uses /generations.
                // AIMLEndpoints.imageEndpoint is the single source of truth for that rule; useEditsEndpoint
                // is derived from its result (rather than re-deriving supportsMask && hasInputImages here)
                // so this site can't drift from AIMLEndpoints again. When it does not route to edits, fall
                // back to the registry's per-model generationEndpoint, not the shared /generations literal —
                // those differ per model.
                let defaultEndpoint = AIMLEndpoints.imageEndpoint(
                    supportsMask: model.supportsMask,
                    hasInputImages: !appState.ui.imageSlots.isEmpty
                )
                let useEditsEndpoint = defaultEndpoint == AIMLEndpoints.imagesEditsURL
                let defaultUrlString = useEditsEndpoint ? defaultEndpoint.absoluteString : model.generationEndpoint
                let urlString = appState.settings.customAIMLEndpoint ?? defaultUrlString

                guard let url = URL(string: urlString) else {
                    throw GenerationError.invalidURL
                }

                // *** Add capture of submitted endpoint ***
                let submittedEndpoint = urlString // Capture the actual endpoint used

                // Declare request early
                // Was: timeoutInterval: 120. klingai/image-o1 (and other reasoning-style image models)
                // legitimately exceed 120s; the video path already allows 300.
                var request = URLRequest(url: url, timeoutInterval: 360)
                request.httpMethod = "POST"
                request.addValue("Bearer \(appState.settings.aimlapiKey)", forHTTPHeaderField: "Authorization")

                // *** Initialize submittedPayload ***
                var submittedPayload: String? = nil

                if useBinary && isI2I && !appState.ui.imageSlots.isEmpty {
                    // Binary submission
                    let boundary = "Boundary-\(UUID().uuidString)"
                    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

                    var body = Data()

                    // NEW: If custom payload, parse and use it as the base for form fields; else use defaults
                    var formFields: [String: Any] = [:]
                    if let customPayload = appState.settings.customAIMLPayload,
                       let data = customPayload.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        formFields = parsed
                        // Capture as submittedPayload for history
                        submittedPayload = customPayload
                        Log.debug("Using custom payload for binary form fields")
                    } else {
                        // Defaults (existing)
                        formFields["model"] = appState.settings.selectedAIMLModel
                        formFields["prompt"] = finalPrompt

                        // Also add advanced params if no custom (from the descriptor table)
                        var modelParams = ParamEncoder.encode(
                            ParamCatalog.descriptors(for: model),
                            params: aimlParams,
                            context: ParamCatalog.context(for: model, hasInputImages: !appState.ui.imageSlots.isEmpty)
                        )
                        // /v1/images/edits accepts only a documented subset of params;
                        // undocumented fields (e.g. `moderation`) are rejected or
                        // ignored by the edits endpoint, so drop them here. The
                        // /generations JSON body keeps the full encoder output. (finding #9)
                        if useEditsEndpoint {
                            let allowedEditsParams: Set<String> = [
                                "model", "prompt", "size", "quality",
                                "background", "n", "output_format"
                            ]
                            modelParams = modelParams.filter { allowedEditsParams.contains($0.key) }
                        }
                        formFields.merge(modelParams) { (_, new) in new }
                        // Capture defaults as payload string (existing)
                        do {
                            let jsonData = try JSONSerialization.data(withJSONObject: formFields, options: [.prettyPrinted, .sortedKeys])
                            if let jsonString = String(data: jsonData, encoding: .utf8) {
                                submittedPayload = jsonString
                            }
                        } catch {
                            Log.debug("Failed to capture submitted payload: \(error.localizedDescription)")
                        }
                    }

                    // Append all form fields (from custom or defaults)
                    for (key, value) in formFields {
                        body.append("--\(boundary)\r\n".data(using: .utf8)!)
                        body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                        body.append("\(value)\r\n".data(using: .utf8)!)  // Assumes values are String/Int convertible; add type handling if needed
                    }

                    // When a mask is attached (mask-capable gpt-image edits), the mask must match the
                    // uploaded image's pixel dimensions, so send the image full-resolution as PNG —
                    // no JPEG conversion or 50% downscale, which would break mask alignment.
                    let maskActive = model.supportsMask && appState.ui.imageSlots.contains { $0.maskURL != nil }

                    // Append image(s) (existing; this will override any "image" in formFields if present)
                    for (index, slot) in appState.ui.imageSlots.enumerated() {
                        // Load full-resolution image from disk — never from memory
                        guard let fullURL = slot.fullResolutionURL,
                              let fullImage = PlatformImage(contentsOfFile: fullURL.path) else {
                            Log.debug("Skipping slot \(index): no full-resolution image available")
                            continue
                        }

                        // Process the full image for upload (binary mode). When a mask is active, drop the
                        // original-bytes passthrough (originalData: nil) so the image is re-encoded to PNG
                        // at the same pixel grid the mask was rendered against — dimensions must match.
                        guard let processed = processImageForUpload(
                            image: fullImage,
                            originalData: maskActive ? nil : slot.originalData,
                            format: maskActive ? "png" : "jpeg",
                            isBase64: false,
                            convertToJPG: maskActive ? false : appState.settings.base64ConvertToJPG,
                            scale50Percent: maskActive ? false : appState.settings.base64Scale50Percent
                        ) else {
                            Log.debug("Skipping slot \(index): failed to process image for upload")
                            continue
                        }

                        // Append to multipart body
                        body.append("--\(boundary)\r\n".data(using: .utf8)!)
                        let fileExtension = processed.mimeType == "image/jpeg" ? "jpg" : "png"
                        let fileName = "image_\(index).\(fileExtension)"

                        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
                        body.append("Content-Type: \(processed.mimeType)\r\n\r\n".data(using: .utf8)!)
                        body.append(processed.data)
                        body.append("\r\n".data(using: .utf8)!)
                    }

                    // Append a single inpainting mask part (binary PNG) for mask-capable gpt-image edits.
                    // The OpenAI /v1/images/edits endpoint takes one `mask` aligned to the (first) image.
                    if maskActive {
                        let masksPresent = appState.ui.imageSlots.compactMap { $0.maskURL }
                        if let maskURL = masksPresent.first, let maskData = try? Data(contentsOf: maskURL) {
                            if masksPresent.count > 1 {
                                Log.debug("Multiple slot masks present (\(masksPresent.count)); sending only the first as `mask`.")
                            }
                            body.append("--\(boundary)\r\n".data(using: .utf8)!)
                            body.append("Content-Disposition: form-data; name=\"mask\"; filename=\"mask.png\"\r\n".data(using: .utf8)!)
                            body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
                            body.append(maskData)
                            body.append("\r\n".data(using: .utf8)!)
                        } else {
                            Log.debug("maskActive but mask data could not be read; sending edit without mask.")
                        }
                    }

                    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                    request.httpBody = body

                    // If no custom payload was used, note it for history (existing)
                    if submittedPayload == nil {
                        submittedPayload = "Binary multipart submission (model: \(appState.settings.selectedAIMLModel), prompt: \(appState.prompt))"
                    }

                    Log.debug("Multipart body constructed: \(body.count) bytes")
                    
                    
                    
                } else {
                    // JSON submission
                    var bodyDict: [String: Any]
                    if let customPayload = appState.settings.customAIMLPayload,
                       let data = customPayload.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        bodyDict = parsed
                    } else {
                        bodyDict = [
                            "model": appState.settings.selectedAIMLModel,
                            "prompt": finalPrompt,
                            "response_format": "b64_json"
                        ]
                        // Add image placeholders for I2I models
                        if isI2I && !appState.ui.imageSlots.isEmpty {
                            let imageKey = model.imageInputParam.isEmpty ? "image" : model.imageInputParam
                            if model.acceptsMultiImages {
                                bodyDict[imageKey] = appState.ui.imageSlots.enumerated().map { "[image_slot_\($0.offset + 1)]" }
                            } else {
                                bodyDict[imageKey] = "[image_slot_1]"
                                if let secondKey = model.secondImageParam, appState.ui.imageSlots.count > 1 {
                                    bodyDict[secondKey] = "[image_slot_2]"
                                }
                            }
                        }
                        
                        // Add model-specific parameters from the model's descriptor table
                        let modelParams = ParamEncoder.encode(
                            ParamCatalog.descriptors(for: model),
                            params: aimlParams,
                            context: ParamCatalog.context(for: model, hasInputImages: !appState.ui.imageSlots.isEmpty)
                        )
                        bodyDict.merge(modelParams) { (_, new) in new }
                    }

                    // Handle image inputs
                    var imageInputs: [String] = []
                    if isI2I && !appState.ui.imageSlots.isEmpty {
                        for slot in appState.ui.imageSlots {
                            // Load full image from disk — NEVER from slot.image
                            guard let fullURL = slot.fullResolutionURL,
                                  let fullImage = PlatformImage(contentsOfFile: fullURL.path) else {
                                Log.debug("Skipping slot: no full-resolution image available")
                                continue
                            }
                            
                            // Process the full image for upload
                            guard let processed = processImageForUpload(
                                image: fullImage,
                                originalData: slot.originalData,
                                format: "jpeg",
                                isBase64: preferBase64,
                                convertToJPG: appState.settings.base64ConvertToJPG,
                                scale50Percent: appState.settings.base64Scale50Percent
                            ) else {
                                Log.debug("Skipping slot: failed to process image for upload")
                                continue
                            }
                            
                            if usePublicURL {
                                // --- ImgBB Upload (Public URL) ---
                                guard !appState.settings.imgbbApiKey.isEmpty else {
                                    throw GenerationError.apiError("ImgBB API key required for public image upload.")
                                }
                                guard ImgBBClient.isPlausibleKey(appState.settings.imgbbApiKey) else {
                                    throw GenerationError.apiError("Invalid ImgBB API key format.")
                                }
                                if !(await showPrivacyNotice(for: .imgbb)) {
                                    throw GenerationError.apiError("User declined ImgBB privacy notice.")
                                }

                                let uploadURL = ImgBBClient.uploadURL(apiKey: appState.settings.imgbbApiKey)
                                
                                var uploadRequest = URLRequest(url: uploadURL)
                                uploadRequest.httpMethod = "POST"
                                
                                let boundary = "Boundary-\(UUID().uuidString)"
                                uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                                
                                var body = Data()
                                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                                body.append("Content-Disposition: form-data; name=\"image\"\r\n\r\n".data(using: .utf8)!)
                                body.append(processed.data.base64EncodedString().data(using: .utf8)!)
                                body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                                
                                uploadRequest.httpBody = body
                                
                                Log.debug("Uploading image to ImgBB...")
                                let (uploadData, response) = try await URLSession.shared.data(for: uploadRequest)
                                
                                guard let httpResponse = response as? HTTPURLResponse,
                                      (200...299).contains(httpResponse.statusCode) else {
                                    let bodyString = String(data: uploadData, encoding: .utf8) ?? "No body"
                                    throw GenerationError.uploadFailed("ImgBB upload failed: HTTP error – \(bodyString)")
                                }
                                
                                let uploadResponse = try JSONDecoder().decode(ImgBBClient.UploadResponse.self, from: uploadData)
                                guard uploadResponse.success,
                                      let imagePublicUrl = uploadResponse.data?.url else {
                                    let errorMsg = uploadResponse.error?.message ?? "Unknown ImgBB error"
                                    throw GenerationError.uploadFailed("ImgBB upload failed: \(errorMsg)")
                                }
                                
                                imageInputs.append(imagePublicUrl)
                                Log.debug("ImgBB upload successful: \(imagePublicUrl)")
                                
                            } else if model.acceptsBase64 {
                                // --- Base64 (Private) ---
                                let base64 = processed.data.base64EncodedString()
                                imageInputs.append("data:\(processed.mimeType);base64,\(base64)")
                                
                            } else {
                                throw GenerationError.apiError("Model does not support selected image submission method.")
                            }
                        }
                        
                        // Replace placeholders in the JSON payload
                        let imageKey = model.imageInputParam.isEmpty ? "image" : model.imageInputParam
                        
                        for (index, imageInput) in imageInputs.enumerated() {
                            let placeholder = "[image_slot_\(index + 1)]"
                            
                            if model.acceptsMultiImages {
                                if var images = bodyDict[imageKey] as? [String],
                                   index < images.count && images[index] == placeholder {
                                    images[index] = imageInput
                                    bodyDict[imageKey] = images
                                }
                            } else if index == 0 {
                                // Single-image model
                                if let current = bodyDict[imageKey] as? String, current == placeholder {
                                    bodyDict[imageKey] = imageInput
                                } else {
                                    bodyDict[imageKey] = imageInput  // Force set if placeholder missing
                                }
                            } else if index == 1, let secondKey = model.secondImageParam {
                                // Second image uses secondImageParam key
                                if let current = bodyDict[secondKey] as? String, current == placeholder {
                                    bodyDict[secondKey] = imageInput
                                } else {
                                    bodyDict[secondKey] = imageInput
                                }
                            }
                        }
                    }

                    // Replace prompt placeholder
                    if bodyDict["prompt"] as? String == "[prompt]" {
                        bodyDict["prompt"] = finalPrompt
                    }

                    // Replace image placeholders in bodyDict
                    let imageKey = model.imageInputParam.isEmpty ? "image" : model.imageInputParam
                    for (index, imageInput) in imageInputs.enumerated() {
                        let placeholder = "[image_slot_\(index + 1)]"
                        if model.acceptsMultiImages {
                            if var images = bodyDict[imageKey] as? [String] {
                                if index < images.count, images[index] == placeholder {
                                    images[index] = imageInput
                                    bodyDict[imageKey] = images
                                }
                            }
                        } else if index == 0 {
                            if bodyDict[imageKey] as? String == placeholder {
                                bodyDict[imageKey] = imageInput
                            }
                        } else if index == 1, let secondKey = model.secondImageParam {
                            if bodyDict[secondKey] as? String == placeholder {
                                bodyDict[secondKey] = imageInput
                            }
                        }
                    }

                    // Kling v3 multi-prompt: split newline-separated prompts into shots
                    let lowerModelId = appState.settings.selectedAIMLModel.lowercased()
                    if lowerModelId.contains("v3") && lowerModelId.contains("kling"),
                       let prompt = bodyDict["prompt"] as? String {
                        let lines = prompt.components(separatedBy: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        if lines.count > 1 {
                            let shots = Array(lines.prefix(6))
                            let totalDuration = (bodyDict["duration"] as? Int) ?? 15
                            // Parse per-shot durations from trailing Ns, e.g. "scene description 5s"
                            let durationRegex = try? NSRegularExpression(pattern: "\\b(\\d+)s\\s*$")
                            var parsedDurations: [Int?] = shots.map { line in
                                guard let regex = durationRegex,
                                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                                      let range = Range(match.range(at: 1), in: line),
                                      let dur = Int(line[range]) else { return nil }
                                return max(dur, 3) // minimum 3s per shot
                            }
                            // Fill unspecified durations: split remaining time evenly
                            let specifiedTotal = parsedDurations.compactMap { $0 }.reduce(0, +)
                            let unspecifiedCount = parsedDurations.filter { $0 == nil }.count
                            let remainingTime = max(totalDuration - specifiedTotal, unspecifiedCount * 3)
                            let evenSplit = unspecifiedCount > 0 ? max(remainingTime / unspecifiedCount, 3) : 3
                            parsedDurations = parsedDurations.map { $0 ?? evenSplit }

                            let multiPrompt: [[String: Any]] = shots.enumerated().map { index, line in
                                // Strip the (Ns) suffix from the prompt text
                                var cleanLine = line
                                if let regex = durationRegex,
                                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                                    cleanLine = (line as NSString).replacingCharacters(in: match.range, with: "").trimmingCharacters(in: .whitespaces)
                                }
                                return [
                                    "index": index,
                                    "prompt": cleanLine,
                                    "duration": parsedDurations[index] ?? evenSplit
                                ]
                            }
                            bodyDict["multi_prompt"] = multiPrompt
                            bodyDict["multi_shot"] = true
                            bodyDict["shot_type"] = "customize"
                            bodyDict.removeValue(forKey: "prompt")
                            bodyDict.removeValue(forKey: "duration")
                        }
                    }

                    // *** Capture JSON payload ***
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: bodyDict, options: [.prettyPrinted, .sortedKeys])
                        submittedPayload = String(data: jsonData, encoding: .utf8)
                    } catch {
                        Log.debug("Failed to capture submitted payload: \(error.localizedDescription)")
                    }

                    // Serialize bodyDict and set request body
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: bodyDict, options: [.prettyPrinted])
                        request.httpBody = jsonData
                        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    } catch {
                        throw GenerationError.encodingFailed(error.localizedDescription)
                    }
                }

                request.addValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")

                try Task.checkCancellation()
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    // `friendlyError` deliberately collapses the API's response into one readable
                    // sentence for the alert — but a validation failure's whole diagnostic value is
                    // in the body it discards, and the alert is gone once dismissed. Log the raw
                    // body and the keys actually sent. This is what a 2026-07-28 live test needed
                    // and could not get: the alert said "Validation failed. Please check your
                    // request fields and values" and named neither the field nor the value.
                    // Values are logged, not just keys — the failures found that day were wrong
                    // *values* for the right keys (`resolution: "720p"` where the model publishes
                    // `["720P"]`). The prompt is never included.
                    // Read back from `request.httpBody` rather than a local: this is literally the
                    // bytes that went on the wire, so it cannot drift from what was sent.
                    let sentBody = request.httpBody
                        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    let sent = (sentBody ?? [:])
                        .filter { $0.key != "prompt" }
                        .map { "\($0.key)=\($0.value)" }
                        .sorted()
                        .joined(separator: " ")
                    Log.error("AI/ML image generation failed — status=\(status) "
                              + "model=\(appState.settings.selectedAIMLModel) endpoint=\(urlString) "
                              + "sent[\(sent)] body=\(String(data: data, encoding: .utf8) ?? "<undecodable>")")
                    throw GenerationError.apiError(AIMLEndpoints.friendlyError(status: status, body: data))
                }
                Log.debug("Image response: HTTP \(httpResponse.statusCode), \(data.count) bytes")

                let responseDecoded = try JSONDecoder().decode(OpenAICompatible.ImageResponse.self, from: data)

                // Log decoded response structure for debugging
                for (idx, respItem) in responseDecoded.data.enumerated() {
                    let hasB64 = respItem.b64_json != nil
                    let urlPreview = respItem.url.map { String($0.prefix(120)) } ?? "nil"
                    Log.debug("Response data[\(idx)]: url=\(urlPreview), b64_json=\(hasB64)")
                }

                if let error = responseDecoded.error {
                    let formattedError = OpenAICompatible.formatError(error)
                    await MainActor.run {
                        appState.ui.outputTexts = [formattedError]
                        appState.ui.outputImages = []
                        appState.ui.outputPaths = []
                    }
                    throw GenerationError.apiError(error.message ?? "Unknown error")
                }

                // Check for empty data array (model returned nothing)
                if responseDecoded.data.isEmpty {
                    await MainActor.run {
                        appState.ui.outputTexts = ["No images generated. The model may have declined to generate content for this prompt."]
                        appState.ui.outputImages = []
                        appState.ui.outputPaths = []
                    }
                    throw GenerationError.apiError("Empty response from model")
                }

                var recoveredIDs: [Int: UUID] = [:]
                var images: [PlatformImage?] = []
                var texts: [String] = []
                var paths: [String?] = []

                let total = responseDecoded.data.count
                for (i, item) in responseDecoded.data.enumerated() {
                    var textOutput = ""
                    if let revised = item.revised_prompt {
                        textOutput += "Revised prompt: \(revised)\n"
                    }

                    var assetReadID: UUID?
                    defer {
                        if let assetReadID {
                            let saved = recoveredIDs[i].flatMap { appState.historyState.findEntry(by: $0) }.map { entry in
                                entry.allItems.first?.status == .completed
                            } ?? false
                            appState.jobQueue.finishAssetRead(assetReadID, saved: saved)
                        }
                    }
                    if item.b64_json == nil, let sourceURL = item.url {
                        let recovery = HistoryItem(prompt: finalPrompt,
                            responseText: "Generated asset available. Download again if retrieval is interrupted.",
                            date: Date(), mode: .aimlapi, task: .image, modelUsed: appState.settings.selectedAIMLModel,
                            status: .failed, sourceAssetURL: sourceURL)
                        assetReadID = appState.jobQueue.beginAssetRead(recovery)
                        recoveredIDs[i] = recovery.id
                        appState.historyState.history.append(.item(recovery))
                        appState.historyState.saveHistory()
                    }
                    var imgData: Data?
                    if let b64 = item.b64_json {
                        imgData = Data(base64Encoded: b64)
                    } else if let imageUrl = item.url, let url = URL(string: imageUrl) {
                        Log.debug("Downloading original image asset")
                        let (downloadData, downloadResponse) = try await URLSession.shared.data(from: url)
                        if let httpResp = downloadResponse as? HTTPURLResponse {
                            Log.debug("Image download: HTTP \(httpResp.statusCode), \(downloadData.count) bytes, content-type: \(httpResp.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
                            guard (200...299).contains(httpResp.statusCode) else {
                                throw GenerationError.apiError("Image download failed (HTTP \(httpResp.statusCode))")
                            }
                        }
                        // Guard against non-image responses (e.g. error pages, text)
                        if downloadData.count < 100, let text = String(data: downloadData, encoding: .utf8) {
                            Log.debug("Image download returned small text response: \(text)")
                            throw GenerationError.apiError("Image download returned non-image data (\(downloadData.count) bytes)")
                        }
                        imgData = downloadData
                    }

                    if let data = imgData {
                        let image = PlatformImage(platformData: data)
                        let path = saveGeneratedImage(data: data, prompt: finalPrompt, mode: .aimlapi, modelUsed: appState.settings.selectedAIMLModel, batchIndex: i, totalInBatch: total)?.path
                        guard let savedPath = path else {
                            throw GenerationError.apiError("The generated image could not be saved. Check disk space and output-folder access. Use Download again in Jobs when a source URL is available.")
                        }
                        if let id = recoveredIDs[i], let index = appState.historyState.history.firstIndex(where: { $0.id == id }),
                           case .item(var recovery) = appState.historyState.history[index] {
                            recovery.imagePath = savedPath
                            recovery.status = .completed
                            recovery.responseText = "Original image saved"
                            appState.historyState.history[index] = .item(recovery)
                            appState.ui.sessionGeneratedIDs.append(id)
                        }
                        if let saved = path {
                            textOutput += "Image saved to \(userFriendlyPath(saved))\n"
                        }
                        images.append(image)
                        texts.append(textOutput)
                        paths.append(path)
                    } else {
                        images.append(nil)
                        paths.append(nil)
                        texts.append(textOutput.isEmpty ? "No output for item \(i+1)" : textOutput)
                    }
                }


                await MainActor.run {
                    appState.ui.outputImages = images
                    appState.ui.outputTexts = texts
                    appState.ui.outputPaths = paths
                    appState.ui.currentOutputIndex = 0
                }

                // Actual cost for the whole request (covers all N images) — attach to the first
                // item and add to the session total.
                let requestCostUSD = AIMLEndpoints.usdSpent(from: data)
                for (i, id) in recoveredIDs {
                    if let index = appState.historyState.history.firstIndex(where: { $0.id == id }),
                       case .item(var recovered) = appState.historyState.history[index] {
                        recovered.customAIMLPayload = submittedPayload
                        recovered.customAIMLEndpoint = submittedEndpoint
                        recovered.costUSD = i == 0 ? requestCostUSD : nil
                        appState.historyState.history[index] = .item(recovered)
                    }
                }
                if let c = requestCostUSD { appState.ui.sessionSpendUSD += c }
                let batchId = images.count > 1 ? UUID() : nil
                for i in 0..<total {
                    if recoveredIDs[i] != nil { continue }
                    let newItem = HistoryItem(
                        prompt: finalPrompt,
                        responseText: texts[i],
                        imagePath: paths[i],
                        date: Date(),
                        mode: appState.settings.provider,
                        task: .image,  // The `isVideoMode` branch above owns video.
                        workflowName: nil,
                        modelUsed: appState.settings.selectedAIMLModel,
                        batchId: batchId,
                        indexInBatch: i,
                        totalInBatch: total,
                        jobId: nil,
                        status: nil,
                        customAIMLPayload: submittedPayload, // Use captured payload
                        customAIMLEndpoint: submittedEndpoint, // Use captured endpoint
                        costUSD: (i == 0 ? requestCostUSD : nil)
                    )
                    appState.historyState.history.append(.item(newItem))
                    appState.ui.sessionGeneratedIDs.append(newItem.id)  // Track in session gallery
                }
                appState.historyState.saveHistory()

                // Auto-present or show toast
                await MainActor.run {
                    triggerGenerationPresentation(imageCount: images.compactMap { $0 }.count, appState: appState)
                }

                if !appState.settings.aimlapiKey.isEmpty {
                    balanceFetchTask?.cancel()
                    balanceFetchTask = Task {
                        do {
                            let balanceData = try await fetchBalance(apiKey: appState.settings.aimlapiKey)
                            if let balanceNum = balanceData["balance"] as? Double {
                                await MainActor.run {
                                    aimlBalance = balanceNum
                                    Log.debug("Updated AIMLAPI balance after image generation: \(balanceNum)")
                                }
                            }
                        } catch {
                            Log.debug("Error fetching balance after image generation: \(error.localizedDescription)")
                            await MainActor.run {
                                aimlBalance = nil
//                                errorItem = AlertError(message: "Failed to fetch balance after image generation: \(error.localizedDescription)", fullMessage: nil)
                            }
                        }
                    }
                }
            }

        }
    }
    
    func stopGeneration() {
        isCancelled = true
        generationTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        progress = 0.0
        progressStep = 0
        progressMax = 0
        currentNodeName = nil
        DispatchQueue.main.async {
            self.isLoading = false
        }
        
        if appState.settings.provider == .comfyUI {
            errorItem = AlertError(message: "Stopped waiting locally. ComfyUI may continue processing; recover the existing job from Jobs.", fullMessage: nil)
        }
    }
    
    private func checkServerAvailability() async throws -> [String: Any] {
        guard let url = ComfyUIEndpoints.objectInfoURL(serverURL: appState.settings.comfyServerURL) else {
            throw GenerationError.invalidServerURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw GenerationError.apiError("Server responded with status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            if let objectInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return objectInfo
            }
            return [:]
        } catch let error as GenerationError {
            throw error
        } catch {
            throw GenerationError.apiError("Failed to connect to server: \(error.localizedDescription)")
        }
    }

    // MARK: - ComfyUI Error Helpers

    /// Checks if node_errors contains any required_input_missing errors
    private func hasMissingInputErrors(_ nodeErrors: [String: Any]) -> Bool {
        for (_, errorInfo) in nodeErrors {
            guard let info = errorInfo as? [String: Any],
                  let errors = info["errors"] as? [[String: Any]] else { continue }
            for error in errors {
                if error["type"] as? String == "required_input_missing" {
                    return true
                }
            }
        }
        return false
    }

    /// Extracts the set of class_types from nodes that have missing input errors
    private func extractClassTypesWithMissingInputs(from nodeErrors: [String: Any], workflow: [String: Any]) -> Set<String> {
        var classTypes = Set<String>()
        for (nodeID, errorInfo) in nodeErrors {
            guard let info = errorInfo as? [String: Any],
                  let errors = info["errors"] as? [[String: Any]] else { continue }
            let hasMissing = errors.contains { $0["type"] as? String == "required_input_missing" }
            if hasMissing {
                // Get class_type from the error info first, fall back to workflow
                if let classType = info["class_type"] as? String {
                    classTypes.insert(classType)
                } else if let node = workflow[nodeID] as? [String: Any],
                          let classType = node["class_type"] as? String {
                    classTypes.insert(classType)
                }
            }
        }
        return classTypes
    }

    /// Formats a ComfyUI validation error response into a readable message
    private func formatPromptError(_ json: [String: Any]?) -> String? {
        guard let json = json,
              let nodeErrors = json["node_errors"] as? [String: Any],
              !nodeErrors.isEmpty else { return nil }

        var messages: [String] = []
        for (nodeID, errorInfo) in nodeErrors {
            guard let info = errorInfo as? [String: Any],
                  let errors = info["errors"] as? [[String: Any]],
                  let classType = info["class_type"] as? String else { continue }
            for error in errors {
                let type = error["type"] as? String ?? "unknown"
                let details = error["details"] as? String ?? error["message"] as? String ?? ""
                messages.append("Node \(nodeID) (\(classType)): \(type) — \(details)")
            }
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    @MainActor
    func showPrivacyNotice(for service: PrivacyService) async -> Bool {
        let key = "dontShow\(service.rawValue.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: " ", with: ""))Privacy"
        let dontShow = AppStorageContext.defaults.bool(forKey: key)
        Log.debug("Checking privacy notice for \(service.rawValue), dontShow=\(dontShow)")
        if dontShow {
            return true
        }
        
        return await withTimeout(seconds: 30) {
            await withCheckedContinuation { continuation in
                self.onPrivacyComplete = { consented, dontShow in
                    Log.debug("onPrivacyComplete for \(service.rawValue): consented=\(consented), dontShow=\(dontShow)")
                    self.onPrivacyComplete = nil
                    if dontShow {
                        AppStorageContext.defaults.set(true, forKey: key)
                        AppStorageContext.defaults.synchronize()
                    }
                    continuation.resume(returning: consented)
                    DispatchQueue.main.async {
                        self.privacyServiceToShow = nil
                    }
                }
                DispatchQueue.main.async {
                    self.privacyServiceToShow = service
                    Log.debug("Set privacyServiceToShow to \(service.rawValue)")
                }
            }
        } ?? false
    }
    
    func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
        let task = Task { await operation() }
        let timeout = Task {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            task.cancel()
            return nil as T? // Explicitly cast nil to T?
        }
        let result = await task.value
        timeout.cancel()
        return result
    }

    /// Gets a display name for a node from the workflow
    /// Returns the node's title if available, otherwise the class_type, or nil if not found
    func getNodeDisplayName(nodeId: String) -> String? {
        guard let workflow = appState.generation.comfyWorkflow,
              let node = workflow[nodeId] as? [String: Any] else {
            return nil
        }

        // Try to get title from _meta first
        if let meta = node["_meta"] as? [String: Any],
           let title = meta["title"] as? String {
            return title
        }

        // Fall back to class_type
        if let classType = node["class_type"] as? String {
            return classType
        }

        return nil
    }

    /// Shows a retry dialog for network errors and returns whether to retry
    func showRetryDialog(message: String) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                self.retryAlertMessage = message
                self.retryContinuation = continuation
                self.showRetryAlert = true
            }
        }
    }

    // MARK: - Image Description (Vision-to-Text)

    /// Core Gemini vision call — takes loaded image + data, returns description text
    @MainActor
    private func describeImageViaGemini(image: PlatformImage, imageData: Data) async throws -> String {
        guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
            throw NSError(domain: "GenStation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Gemini API key required for image description"])
        }

        guard let processed = processImageForUpload(
            image: image,
            originalData: imageData,
            format: "jpeg",
            isBase64: true,
            convertToJPG: true,
            scale50Percent: true
        ) else {
            throw NSError(domain: "GenStation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])
        }

        let promptText = """
        Describe this image in detail as a prompt for an AI image generation model.
        Include: subject, composition, style, colors, lighting, mood, and any notable details.
        Format as a single paragraph prompt, not a list.
        """

        let parts: [GeminiClient.Part] = [
            GeminiClient.Part(text: promptText, inlineData: nil),
            GeminiClient.Part(text: nil, inlineData: GeminiClient.InlineData(
                mimeType: processed.mimeType,
                data: processed.data.base64EncodedString()
            ))
        ]

        let generationConfig = GeminiClient.GeminiGenerationConfig(
            responseModalities: ["TEXT"],
            imageConfig: nil
        )

        let requestBody = GeminiClient.GenerateContentRequest(
            contents: [GeminiClient.Content(parts: parts)],
            generationConfig: generationConfig
        )

        let modelName = "gemini-2.0-flash"
        let url = GeminiClient.generateContentURL(model: modelName, apiKey: apiKey)

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GenStation", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
        }

        if httpResponse.statusCode != 200 {
            let bodyString = String(data: responseData, encoding: .utf8) ?? "No body"
            Log.debug("Gemini describe image failed: HTTP \(httpResponse.statusCode) - \(bodyString)")
            throw NSError(domain: "GenStation", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error: HTTP \(httpResponse.statusCode)", "body": bodyString])
        }

        let apiResponse = try JSONDecoder().decode(GeminiClient.NewGenerateContentResponse.self, from: responseData)

        if let blockReason = apiResponse.promptFeedback?.blockReason {
            let blockMessage = GeminiClient.formatBlockReason(blockReason, safetyRatings: apiResponse.promptFeedback?.safetyRatings)
            throw NSError(domain: "GenStation", code: 5, userInfo: [NSLocalizedDescriptionKey: blockMessage])
        }

        if let description = apiResponse.candidates?.first?.content?.parts?.first?.text, !description.isEmpty {
            return description
        } else {
            throw NSError(domain: "GenStation", code: 6, userInfo: [NSLocalizedDescriptionKey: "No description generated"])
        }
    }

    /// Describes a history item image using Gemini vision
    @MainActor
    func describeImage(item: HistoryItem) async {
        if item.imagePath?.hasSuffix(".mp4") == true {
            errorItem = AlertError(message: "Cannot describe videos. Please select an image.", fullMessage: nil)
            return
        }

        guard let imagePath = item.imagePath else {
            errorItem = AlertError(message: "No image path found", fullMessage: nil)
            return
        }

        let fileURL = URL(fileURLWithPath: imagePath)
        var imageData: Data?

        if let outputDir = appState.settings.outputDirectory {
            let didStart = outputDir.startAccessingSecurityScopedResource()
            defer { if didStart { outputDir.stopAccessingSecurityScopedResource() } }
            imageData = try? Data(contentsOf: fileURL)
        } else {
            imageData = try? Data(contentsOf: fileURL)
        }

        guard let data = imageData, let image = PlatformImage(data: data) else {
            errorItem = AlertError(message: "Failed to load image", fullMessage: nil)
            return
        }

        do {
            let description = try await describeImageViaGemini(image: image, imageData: data)
            appState.presentedModal = .imageDescription(description)
        } catch {
            let fullMessage = (error as NSError).userInfo["body"] as? String
            errorItem = AlertError(message: error.localizedDescription, fullMessage: fullMessage)
        }
    }

    /// Describes an input image slot using Gemini vision
    @MainActor
    func describeImage(slot: UIState.ImageSlot) async {
        guard let fullResURL = slot.fullResolutionURL else {
            errorItem = AlertError(message: "No image loaded in this slot", fullMessage: nil)
            return
        }

        guard let data = try? Data(contentsOf: fullResURL),
              let image = PlatformImage(data: data) else {
            errorItem = AlertError(message: "Failed to load image from slot", fullMessage: nil)
            return
        }

        do {
            let description = try await describeImageViaGemini(image: image, imageData: data)
            appState.presentedModal = .imageDescription(description)
        } catch {
            let fullMessage = (error as NSError).userInfo["body"] as? String
            errorItem = AlertError(message: error.localizedDescription, fullMessage: fullMessage)
        }
    }

    // MARK: - Pending Video Job Resume (Silent Auto-Check on Foreground)

    /// Silently checks all pending video jobs on foreground return.
    /// Does a single poll per job — downloads if completed, updates status if still
    /// in progress, marks failed if expired. No user alert; fully automatic.
    func checkPendingVideoJobs() {
        // Don't check if already generating or already resuming
        guard !isLoading, videoResumeTask == nil else { return }

        videoResumeTask = Task { @MainActor in
            defer { videoResumeTask = nil }

            // Age scan first (queue-owned): marks >24h jobs expired and posts
            // the ~20h expiry warning, both with user notifications.
            appState.jobQueue.scanPendingJobAges()

            let now = Date()
            var pending: [HistoryItem] = []
            for entry in appState.historyState.history {
                guard case .item(let item) = entry,
                      let jobId = item.jobId, !jobId.isEmpty,
                      let status = item.status, status.isInProgress,
                      (item.mode == .aimlapi || item.mode == .grok) else { continue }

                // scanPendingJobAges just expired anything older than 24h
                if item.mode == .aimlapi && now.timeIntervalSince(item.date) > JobQueue.maxJobAge { continue }
                // Skip items a live queue job is already polling
                if appState.jobQueue.activeJob(forHistoryItem: item.id) != nil { continue }
                pending.append(item)
            }

            guard !pending.isEmpty else { return }
            Log.debug("Auto-checking \(pending.count) pending video job(s)")
            // Silent resume is queue-owned now (JobQueue.resumePendingJobs);
            // behavior unchanged: one concurrent single-poll per pending job.
            await appState.jobQueue.resumePendingJobs(pending)
        }
    }
}

struct DetailedErrorView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Error Details")
                .font(.title2)
                .bold()

            ScrollView {
                Text(prettyPrintJSON(message) ?? message)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(DS.Radius.standard)
            }
            .frame(maxHeight: 400)
            Button("Copy to Clipboard") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message, forType: .string)
                            #elseif os(iOS)
                            UIPasteboard.general.string = message
                            #endif
                        }
                        .buttonStyle(.borderedProminent)
            
            Button("Close") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func prettyPrintJSON(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return String(data: prettyData, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
