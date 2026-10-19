// ContentView+FileHandling.swift
import Foundation
import AVFoundation
import GenStationCore

extension ContentView {
    func handleOutputFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Log.debug("Selected URLs: \(urls)")
            guard let selectedURL = urls.first else 
            { errorItem = AlertError(message: "No folder selected.", fullMessage: nil)
                return }
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
                NSFileCoordinator().coordinate(readingItemAt: selectedURL, options: [], error: &coordError) { coordinatedURL in
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
                bookmarkData = try selectedURL.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                #endif
                AppStorageContext.defaults.set(bookmarkData, forKey: "outputDirBookmark")
                appState.settings.outputDirectory = selectedURL
                appState.settings.outputPath = selectedURL.path
            } catch {
                Log.debug("Bookmark error: \(error)")
                errorItem = AlertError(message: "Failed to create bookmark for output folder: \(error.localizedDescription)", fullMessage: nil)
            }
        case .failure(let error):
            Log.debug("Selection error: \(error)")
            errorItem = AlertError(message: "Failed to select output folder: \(error.localizedDescription)", fullMessage: nil)
        }
    }
    
    /// Saves generated media to the output folder (or Downloads / tmp as a
    /// fallback). Returns the saved path plus whether the configured output
    /// folder was NOT used (`usedFallback`) so callers — the MCP bridge in
    /// particular — can warn that the file may not be where the user expects.
    /// `usedFallback` is false when no custom folder is configured (Downloads is
    /// the normal destination then, not a fallback).
    func saveGeneratedMedia(data: Data, prompt: String, mode: Provider, modelUsed: String? = nil, batchIndex: Int? = nil, totalInBatch: Int? = nil, isVideo: Bool = false, fileExtension: String? = nil) -> (path: String, usedFallback: Bool)? {
        let fileManager = FileManager.default
        var outputDir = appState.settings.outputDirectory
        var useFallback = false
        var fallbackReason: String? = nil

        // If no custom dir, use Downloads
        if outputDir == nil {
            outputDir = AppStorageContext.fallbackOutputDirectory
            useFallback = true
            Log.debug("No output directory configured, using Downloads")
        }
        guard let dirURL = outputDir else {
            errorItem = AlertError(message: "No output directory available.", fullMessage: nil)
            return nil
        }

        Log.debug("Attempting to save media to: \(dirURL.path)")

        // Use the already-resolved URL from appState (resolved at startup)
        // Just need to start security-scoped access
        var resolvedDir = dirURL

        do {
            // Start security-scoped access for custom dir
            var didStart = false
            if !useFallback {
                didStart = resolvedDir.startAccessingSecurityScopedResource()
                if !didStart {
                    // Security scope failed — fall back to Downloads for THIS save only.
                    // Never delete the bookmark or clear the setting here: the failure can
                    // be transient (observed live: a code-signature change invalidated the
                    // bookmark and one failed save silently wiped the user's setting).
                    // If the user re-selects the folder, the new bookmark overwrites the
                    // old one anyway.
                    if !fileManager.fileExists(atPath: resolvedDir.path) {
                        fallbackReason = "Your output folder no longer exists (\(resolvedDir.path)). Please select a new output folder."
                        Log.debug("Output dir no longer exists; falling back to Downloads for this save.")
                    } else {
                        fallbackReason = "Your output folder couldn't be accessed (permission may need to be re-granted). Please re-select it."
                        Log.debug("Failed to start scoping for custom dir \(resolvedDir.path); falling back to Downloads for this save.")
                    }
                    useFallback = true
                    outputDir = AppStorageContext.fallbackOutputDirectory
                    resolvedDir = outputDir!
                }
            }
            defer { if didStart { resolvedDir.stopAccessingSecurityScopedResource() } }

            // If we fell back, warn the user about the original issue
            if let reason = fallbackReason {
                Log.debug("Fallback to Downloads triggered: \(reason)")
                if appState.ui.outputFolderFallbackMessage == nil {
                    appState.ui.outputFolderFallbackMessage = reason
                }
            }

            // Check sync status
            do {
                let values = try resolvedDir.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                    try fileManager.startDownloadingUbiquitousItem(at: resolvedDir)
                    errorItem = AlertError(message: "Folder syncing—try again soon.", fullMessage: nil)
                    return nil
                }
            } catch {
                Log.debug("Sync check failed: \(error)")
            }

            // List files for unique filename
            var existingFiles: [URL] = []
            var listError: NSError?
            var innerListError: Error?
            NSFileCoordinator().coordinate(readingItemAt: resolvedDir, options: [], error: &listError) { coordinatedURL in
                do {
                    existingFiles = try fileManager.contentsOfDirectory(at: coordinatedURL, includingPropertiesForKeys: nil)
                } catch {
                    innerListError = error
                }
            }
            if let listError = listError {
                throw listError
            }
            if let innerListError = innerListError {
                throw innerListError
            }

            // Generate filename
            let extensionStr = fileExtension ?? (isVideo ? "mp4" : "png")
            let generatedFiles = existingFiles.filter { $0.lastPathComponent.hasPrefix("generated_media_") && $0.pathExtension == extensionStr }
            let numbers = generatedFiles.compactMap {
                Int($0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "generated_media_", with: ""))
            }
            let nextNum = (numbers.max() ?? 0) + 1
            let filename = "generated_media_\(nextNum).\(extensionStr)"
            let fileURL = resolvedDir.appendingPathComponent(filename)
            
            // Write file
            var writeError: NSError?
            var innerWriteError: Error?
            let writeOptions: NSFileCoordinator.WritingOptions = fileManager.fileExists(atPath: fileURL.path) ? .forReplacing : []
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: writeOptions, error: &writeError) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL)
                } catch {
                    innerWriteError = error
                }
            }
            if let writeError = writeError {
                throw writeError
            }
            if let innerWriteError = innerWriteError {
                throw innerWriteError
            }
            return (fileURL.path, fallbackReason != nil)
        } catch {
            let nsError = error as NSError
            let message: String
            switch (nsError.domain, nsError.code) {
            case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError):
                message = "Disk is full. Free up space and try again."
            case (NSCocoaErrorDomain, NSFileWriteNoPermissionError):
                message = "Permission denied for output folder. Please reselect the folder or check permissions."
            default:
                message = "Failed to save media: \(error.localizedDescription)."
            }

            // Attempt temporary save
            let tempExtension = fileExtension ?? (isVideo ? "mp4" : "png")
            let tempURL = AppStorageContext.current.temporaryDirectory.appendingPathComponent("generated_media_\(Date().timeIntervalSince1970).\(tempExtension)")
            do {
                try data.write(to: tempURL)
                if fileManager.fileExists(atPath: tempURL.path) {
                    errorItem = AlertError(message: "\(message) Saved to temporary location: \(tempURL.path).", fullMessage: nil)
                    return (tempURL.path, true)
                } else {
                    errorItem = AlertError(message: "\(message) Temporary file was not created.", fullMessage: nil)
                    return nil
                }
            } catch {
                errorItem = AlertError(message: "\(message) Temporary save failed: \(error.localizedDescription).", fullMessage: nil)
                return nil
            }
        }
    }

    /// Image counterpart of `saveGeneratedMedia` — same return contract
    /// (`usedFallback` = the configured output folder was not used).
    func saveGeneratedImage(data: Data, prompt: String, mode: Provider, workflowName: String? = nil, modelUsed: String? = nil, batchIndex: Int? = nil, totalInBatch: Int? = nil) -> (path: String, usedFallback: Bool)? {
        let fileManager = FileManager.default
        var outputDir = appState.settings.outputDirectory
        var useFallback = false
        var fallbackReason: String? = nil

        // If no custom dir, use Downloads
        if outputDir == nil {
            outputDir = AppStorageContext.fallbackOutputDirectory
            useFallback = true
            Log.debug("No output directory configured, using Downloads")
        }
        guard let dirURL = outputDir else {
            errorItem = AlertError(message: "No output directory available.", fullMessage: nil)
            return nil
        }

        Log.debug("Attempting to save image to: \(dirURL.path)")

        // Use the already-resolved URL from appState (resolved at startup)
        // Just need to start security-scoped access
        var resolvedDir = dirURL

        do {
            // Start security-scoped access for custom dir
            var didStart = false
            if !useFallback {
                didStart = resolvedDir.startAccessingSecurityScopedResource()
                if !didStart {
                    // Security scope failed — fall back to Downloads for THIS save only.
                    // Never delete the bookmark or clear the setting here: the failure can
                    // be transient (observed live: a code-signature change invalidated the
                    // bookmark and one failed save silently wiped the user's setting).
                    // If the user re-selects the folder, the new bookmark overwrites the
                    // old one anyway.
                    if !fileManager.fileExists(atPath: resolvedDir.path) {
                        fallbackReason = "Your output folder no longer exists (\(resolvedDir.path)). Please select a new output folder."
                        Log.debug("Output dir no longer exists; falling back to Downloads for this save.")
                    } else {
                        fallbackReason = "Your output folder couldn't be accessed (permission may need to be re-granted). Please re-select it."
                        Log.debug("Failed to start scoping for custom dir \(resolvedDir.path); falling back to Downloads for this save.")
                    }
                    useFallback = true
                    outputDir = AppStorageContext.fallbackOutputDirectory
                    resolvedDir = outputDir!
                }
            }
            defer { if didStart { resolvedDir.stopAccessingSecurityScopedResource() } }

            // If we fell back, warn the user about the original issue
            if let reason = fallbackReason {
                Log.debug("Fallback to Downloads triggered: \(reason)")
                if appState.ui.outputFolderFallbackMessage == nil {
                    appState.ui.outputFolderFallbackMessage = reason
                }
            }
            
            // Check sync status
            do {
                let values = try resolvedDir.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                    try fileManager.startDownloadingUbiquitousItem(at: resolvedDir)
                    errorItem = AlertError(message: "Folder syncing—try again soon.", fullMessage: nil)
                    return nil
                }
            } catch {
                Log.debug("Sync check failed: \(error)")
            }
            
            // List files for unique filename
            var existingFiles: [URL] = []
            var listError: NSError?
            var innerListError: Error?
            NSFileCoordinator().coordinate(readingItemAt: resolvedDir, options: [], error: &listError) { coordinatedURL in
                do {
                    existingFiles = try fileManager.contentsOfDirectory(at: coordinatedURL, includingPropertiesForKeys: nil)
                } catch {
                    innerListError = error
                }
            }
            if let listError = listError {
                throw listError
            }
            if let innerListError = innerListError {
                throw innerListError
            }
            
            // Detect actual image format and determine save format
            let detectedFormat = detectImageFormat(data)
            let convertToJPEG = appState.settings.saveOutputAsJPEG && mode != .comfyUI
            let extensionStr: String
            if detectedFormat == "jpg" {
                extensionStr = "jpg"
            } else if convertToJPEG {
                extensionStr = "jpg"
            } else if mode == .comfyUI {
                extensionStr = "png"
            } else {
                extensionStr = "png"
            }

            // Generate filename — count across both jpg and png to avoid gaps
            let generatedFiles = existingFiles.filter {
                $0.lastPathComponent.hasPrefix("generated_image_") &&
                ($0.pathExtension == "jpg" || $0.pathExtension == "png")
            }
            let numbers = generatedFiles.compactMap {
                Int($0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "generated_image_", with: ""))
            }
            let nextNum = (numbers.max() ?? 0) + 1
            let filename = "generated_image_\(nextNum).\(extensionStr)"
            let fileURL = resolvedDir.appendingPathComponent(filename)

            // Compute creator
            var creatorToUse: String = mode.rawValue.capitalized
            switch mode {
            case .gemini:
                creatorToUse = appState.settings.selectedGeminiModel
            case .grok:
                creatorToUse = modelUsed ?? appState.settings.selectedGrokModel
            case .aimlapi:
                creatorToUse = modelUsed ?? appState.settings.selectedAIMLModel
            case .comfyUI:
                creatorToUse = workflowName ?? "ComfyUI"
            }
            if let idx = batchIndex, let tot = totalInBatch {
                creatorToUse += " #\(idx + 1) of \(tot)"
            }

            // Prepare image data — preserve native format, add metadata appropriately
            var finalData = data
            if detectedFormat == "jpg" {
                // Already JPEG — just add EXIF
                if !prompt.isEmpty {
                    finalData = addCommentToJPEG(inputData: data, prompt: prompt, creator: creatorToUse) ?? data
                }
                if !isJPEGData(finalData) {
                    if let image = PlatformImage(platformData: finalData) {
                        finalData = image.platformData(forType: "jpeg", compressionQuality: 0.95) ?? finalData
                    } else {
                        throw NSError(domain: "ImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to process JPEG data."])
                    }
                }
            } else if convertToJPEG {
                // Convert non-JPEG to JPEG with EXIF prompt
                finalData = addCommentToJPEG(inputData: data, prompt: prompt, creator: creatorToUse) ?? data
                // Verify conversion succeeded
                if !isJPEGData(finalData) {
                    if let image = PlatformImage(platformData: finalData) {
                        finalData = image.platformData(forType: "jpeg", compressionQuality: 0.95) ?? finalData
                    }
                }
            } else if isPNGData(data) {
                // PNG: add EXIF comment and keep as PNG (lossless)
                if !prompt.isEmpty {
                    finalData = addCommentToPNG(inputData: data, prompt: prompt, creator: creatorToUse) ?? data
                }
            } else if mode == .comfyUI {
                // ComfyUI non-PNG: convert to PNG
                if !isPNGData(data) {
                    if let image = PlatformImage(platformData: data) {
                        finalData = image.platformPngData() ?? data
                    } else {
                        throw NSError(domain: "ImageError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to process PNG data."])
                    }
                }
            } else {
                // WebP, TIFF, or unknown: convert to PNG, then add comment
                if let image = PlatformImage(platformData: data) {
                    finalData = image.platformPngData() ?? data
                }
                if !prompt.isEmpty {
                    finalData = addCommentToPNG(inputData: finalData, prompt: prompt, creator: creatorToUse) ?? finalData
                }
            }
            
            // Write file
            var writeError: NSError?
            var innerWriteError: Error?
            let writeOptions: NSFileCoordinator.WritingOptions = fileManager.fileExists(atPath: fileURL.path) ? .forReplacing : []
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: writeOptions, error: &writeError) { coordinatedURL in
                do {
                    try finalData.write(to: coordinatedURL)
                } catch {
                    innerWriteError = error
                }
            }
            if let writeError = writeError {
                throw writeError
            }
            if let innerWriteError = innerWriteError {
                throw innerWriteError
            }
            return (fileURL.path, fallbackReason != nil)
        } catch {
            let nsError = error as NSError
            let message: String
            switch (nsError.domain, nsError.code) {
            case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError):
                message = "Disk is full. Free up space and try again."
            case (NSCocoaErrorDomain, NSFileWriteNoPermissionError):
                message = "Permission denied for output folder. Please reselect the folder or check permissions."
            default:
                message = "Failed to save image: \(error.localizedDescription)."
            }

            // Attempt temporary save (use detected format for correct extension)
            let tempExt = (mode == .comfyUI) ? "png" : (detectImageFormat(data) == "jpg" ? "jpg" : "png")
            let tempURL = AppStorageContext.current.temporaryDirectory.appendingPathComponent("generated_image_\(Date().timeIntervalSince1970).\(tempExt)")
            do {
                try data.write(to: tempURL)
                if fileManager.fileExists(atPath: tempURL.path) {
                    errorItem = AlertError(message: "\(message) Saved to temporary location: \(tempURL.path).", fullMessage: nil)
                    return (tempURL.path, true)
                } else {
                    errorItem = AlertError(message: "\(message) Temporary file was not created.", fullMessage: nil)
                    return nil
                }
            } catch {
                errorItem = AlertError(message: "\(message) Temporary save failed: \(error.localizedDescription).", fullMessage: nil)
                return nil
            }
        }
    }
    // MARK: - Audio Detection

    /// Detects whether a video file contains audio tracks
    /// - Parameter path: File path to the video
    /// - Returns: true if the video has audio tracks, false otherwise
    func detectVideoHasAudio(at path: String) async -> Bool {
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)

        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            return !audioTracks.isEmpty
        } catch {
            Log.debug("Failed to detect audio tracks: \(error.localizedDescription)")
            return false
        }
    }
}
