// TextEditorView.swift – Major refactor for embedded use in Power Panel
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension Notification.Name {
    static let batchFileUpdated = Notification.Name("batchFileUpdated")
}

struct TextEditorView: View {
    let bookmarkData: Data?
    let isSheet: Bool  // True when presented as a sheet (iOS), false for panel mode

    init(bookmarkData: Data?, isSheet: Bool = false) {
        self.bookmarkData = bookmarkData
        self.isSheet = isSheet
    }

    @State private var fileURL: URL? = nil
    @State private var text: String = ""
    @State private var initialText: String = ""
    @State private var error: String? = nil
    @State private var platformTextView: (any PlatformTextView)? = nil
    @State private var showClearConfirm: Bool = false
    @State private var canUndo: Bool = false
    @State private var canRedo: Bool = false
    @State private var showSavedToast: Bool = false
    @State private var showUnsavedChangesAlert: Bool = false
    @State private var pendingFileVersion: Int? = nil  // Track version change that triggered unsaved warning
    @State private var showGenerateSheet: Bool = false  // LLM batch generation sheet

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if !isSheet {
                // Panel mode: custom toolbar with filename and buttons
                HStack {
                    Text(fileURL?.lastPathComponent ?? "Untitled Batch File")
                        .font(.title3.bold())
                        .foregroundColor(.primary)

                    Spacer()

                    HStack(spacing: 16) {
                        Button(action: { showGenerateSheet = true }) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                        }
                        .help("Generate batch prompts with AI")

                        Button(action: undoAction) {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .disabled(!canUndo)
                        .help("Undo")

                        Button(action: redoAction) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(!canRedo)
                        .help("Redo")

                        Button(action: { showClearConfirm = true }) {
                            Image(systemName: "trash")
                        }
                        .help("Clear editor")

                        Button(action: saveAndDismissIfSheet) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(hasUnsavedChanges ? .green : .primary)
                        }
                        .help(fileURL == nil ? "Save As…" : (hasUnsavedChanges ? "Save (unsaved changes)" : "Save"))
                    }
                }
                .padding()
                .background(Color.systemBackground)

                Divider()
            }

            // Main editor content
            content
                        .contentShape(Rectangle())  // Entire area tappable
                        .onTapGesture {
                            #if os(macOS)
                            makeTextViewFirstResponder()
                            #endif
                        }
                        .onChange(of: text) { _ in
                            updateUndoRedoStates()
                            updatePromptsFromText()
                        }
        }
        .navigationTitle(isSheet ? (fileURL?.lastPathComponent ?? "Untitled Batch File") : "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showGenerateSheet = true }) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                    }
                    .accessibilityLabel("Generate batch prompts")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: undoAction) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(!canUndo)
                    .accessibilityLabel("Undo")

                    Button(action: redoAction) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!canRedo)
                    .accessibilityLabel("Redo")

                    Button(action: { showClearConfirm = true }) {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Clear editor")

                    Button(action: saveAndDismissIfSheet) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundColor(hasUnsavedChanges ? .green : .primary)
                    }
                    .accessibilityLabel("Save and close")
                }
            }
        }
        #endif
        // Clear confirmation
        .alert("Clear editor?", isPresented: $showClearConfirm) {
            Button("Yes", role: .destructive) {
                text = ""
                updatePromptsFromText()
                platformTextView?.clear()
                updateUndoRedoStates()
            }
            Button("Cancel", role: .cancel) {}
        }
        // Error alert
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "Unknown")
        }
        // Saved toast
        .overlay(alignment: .top) {
            if showSavedToast {
                LiquidGlassToast(message: "Batch file saved")
                    .transition(.toastTransition)
                    .padding(.top, 20)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showSavedToast = false }
                        }
                    }
            }
        }
        // Single .onAppear – always load from appState.batchPrompts (source of truth)
        .onAppear {
                // Check if we should open a new untitled buffer
                if let newPrompts = appState.ui.batchNewFilePrompts {
                    appState.ui.batchNewFilePrompts = nil  // Consume the flag
                    text = newPrompts.joined(separator: "\n")
                    fileURL = nil
                    initialText = ""
                    appState.batchPrompts = newPrompts
                    appState.batchFilePath = ""
                    appState.batchFileURL = nil
                    AppStorageContext.defaults.removeObject(forKey: "batchFileBookmark")
                    updateUndoRedoStates()
                    return
                }

                // Always load editor content from in-memory state
                let loadedText = appState.batchPrompts.joined(separator: "\n")
                text = loadedText

                // Resolve bookmark to get fileURL (for saving) and track saved state
                if let data = bookmarkData, !data.isEmpty {
                    resolveBookmarkAndTrackSavedState(data)
                } else {
                    initialText = loadedText  // No file, so current state is "saved"
                }

                updateUndoRedoStates()

                #if os(macOS)
                // Force focus when panel opens
                DispatchQueue.main.async {
                    makeTextViewFirstResponder()
                }
                #endif
            }
        .onChange(of: text) { _ in
                            updateUndoRedoStates()  // Now uses coordinator or removes if not needed
                            updatePromptsFromText()
                        }
        // Sync when batchPrompts changes externally (e.g. from PromptSection generate)
        .onChange(of: appState.batchPrompts) { newPrompts in
            let currentPrompts = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard currentPrompts != newPrompts else { return }
            text = newPrompts.joined(separator: "\n")
        }
        // Reload when a new batch file is selected (even if editor is already open)
        .onChange(of: appState.batchFileVersion) { newVersion in
            // Check for unsaved changes before loading new file
            if hasUnsavedChanges {
                pendingFileVersion = newVersion
                showUnsavedChangesAlert = true
            } else {
                loadCurrentBookmark()
            }
        }
        // Unsaved changes confirmation
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Save First") {
                saveAction()
                // After save completes, load the new file
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    loadCurrentBookmark()
                }
                pendingFileVersion = nil
            }
            Button("Discard", role: .destructive) {
                loadCurrentBookmark()
                pendingFileVersion = nil
            }
            Button("Cancel", role: .cancel) {
                // Revert the version change so user stays on current file
                // The file won't reload, user keeps their unsaved work
                pendingFileVersion = nil
            }
        } message: {
            Text("You have unsaved changes. What would you like to do?")
        }
        // Batch generation sheet
        .sheet(isPresented: $showGenerateSheet) {
            BatchGeneratorView(existingPromptCount: currentPromptCount) { prompts, mode in
                insertGeneratedPrompts(prompts, mode: mode)
            }
            .environmentObject(appState)
        }
    }

    // MARK: - Batch Generation

    private var currentPromptCount: Int {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .count
    }

    private func insertGeneratedPrompts(_ prompts: [String], mode: BatchInsertMode) {
        let newText = prompts.joined(separator: "\n")

        switch mode {
        case .append:
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = newText
            } else {
                text = text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + newText
            }
        case .prepend:
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = newText
            } else {
                text = newText + "\n" + text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case .replace:
            text = newText
        }

        updatePromptsFromText()
        updateUndoRedoStates()
    }

    private var hasUnsavedChanges: Bool {
        let currentLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let savedLines = initialText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return currentLines != savedLines
    }

    private func loadCurrentBookmark() {
            let currentBookmarkData = AppStorageContext.defaults.data(forKey: "batchFileBookmark") ?? Data()
            if !currentBookmarkData.isEmpty {
                loadFromBookmark(currentBookmarkData)  // Your existing loadFromBookmark handles stale refresh + text loading
            } else {
                // No file selected
                text = ""
                initialText = ""
                fileURL = nil
                updatePromptsFromText()
            }
        }
    
    private func undoAction() {
        makeTextViewFirstResponder()
        platformTextView?.undoManager?.undo()
    }

    private func redoAction() {
        makeTextViewFirstResponder()
        platformTextView?.undoManager?.redo()
    }

    private func makeTextViewFirstResponder() {
        #if os(macOS)
        if let tv = platformTextView as? NSTextView, let window = tv.window {
            window.makeFirstResponder(tv)
        }
        #elseif os(iOS)
        if let tv = platformTextView as? UITextView {
            tv.becomeFirstResponder()
        }
        #endif
    }

    private var content: some View {
        Group {
            if let err = error {
                Text("Error: \(err)")
                    .foregroundColor(.red)
                    .padding()
            }

            #if os(macOS)
            CustomTextEditor(text: $text, platformTextView: $platformTextView, isBatchEditor: true)
            #else
            CustomTextEditor(text: $text, platformTextView: $platformTextView, isBatchEditor: true)
            #endif
        }
        .background(systemBackgroundColor)
    }

    private var systemBackgroundColor: Color {
        #if os(macOS)
        Color(NSColor.textBackgroundColor)
        #else
        Color(UIColor.systemBackground)
        #endif
    }

    private func updateUndoRedoStates() {
        canUndo = platformTextView?.undoManager?.canUndo ?? false
        canRedo = platformTextView?.undoManager?.canRedo ?? false
    }

    private func updatePromptsFromText() {
        appState.batchPrompts = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Loading
    private func loadFromBookmark(_ bookmarkData: Data) {
        do {
            var isStale = false
            
            // Resolution options – security scope only on macOS
            #if os(macOS)
            let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let resolutionOptions: URL.BookmarkResolutionOptions = []
            #endif
            
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData,
                                      options: resolutionOptions,
                                      bookmarkDataIsStale: &isStale)

            fileURL = resolvedURL
            Log.debug("Set fileURL after load: \(fileURL?.path ?? "nil")")
            appState.batchFilePath = resolvedURL.path
            appState.batchFileURL = resolvedURL

            // Refresh stale bookmark only if needed – platform-specific options
            if isStale {
                var bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark  // Good default on both platforms
                #if os(macOS)
                bookmarkOptions.insert(.withSecurityScope)
                #endif
                
                if let newBookmark = try? resolvedURL.bookmarkData(options: bookmarkOptions) {
                    AppStorageContext.defaults.set(newBookmark, forKey: "batchFileBookmark")
                }
            }

            loadText(from: resolvedURL)
        } catch {
            self.error = error.localizedDescription
            text = ""
            initialText = ""
            updatePromptsFromText()
            AppStorageContext.defaults.removeObject(forKey: "batchFileBookmark")
            appState.batchFilePath = ""
            appState.batchFileURL = nil
        }
    }

    /// Resolves bookmark to get fileURL and reads file to track saved state,
    /// but does NOT overwrite editor text (preserves in-memory appState.batchPrompts)
    private func resolveBookmarkAndTrackSavedState(_ bookmarkData: Data) {
        do {
            var isStale = false

            #if os(macOS)
            let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let resolutionOptions: URL.BookmarkResolutionOptions = []
            #endif

            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData,
                                      options: resolutionOptions,
                                      bookmarkDataIsStale: &isStale)

            fileURL = resolvedURL
            appState.batchFilePath = resolvedURL.path
            appState.batchFileURL = resolvedURL

            // Refresh stale bookmark if needed
            if isStale {
                var bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
                #if os(macOS)
                bookmarkOptions.insert(.withSecurityScope)
                #endif

                if let newBookmark = try? resolvedURL.bookmarkData(options: bookmarkOptions) {
                    AppStorageContext.defaults.set(newBookmark, forKey: "batchFileBookmark")
                }
            }

            // Read file content to track what's saved (for unsaved changes detection)
            // but don't overwrite editor text
            readFileForSavedState(from: resolvedURL)

        } catch {
            // Bookmark resolution failed - treat as no file
            self.error = error.localizedDescription
            initialText = text  // Current state becomes "saved" state
            AppStorageContext.defaults.removeObject(forKey: "batchFileBookmark")
            appState.batchFilePath = ""
            appState.batchFileURL = nil
        }
    }

    /// Reads file content to set initialText (for unsaved changes detection) without changing editor text
    private func readFileForSavedState(from url: URL) {
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            do {
                let fileContent = try withSecureAccess(to: coordinatedURL) {
                    try String(contentsOf: coordinatedURL, encoding: .utf8)
                }
                // Only set initialText (what's saved), don't change editor text
                initialText = fileContent
            } catch {
                // If we can't read the file, treat current state as saved
                initialText = text
            }
        }
        if coordError != nil {
            initialText = text
        }
    }

    private func loadText(from url: URL) {
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            do {
                let fileContent = try withSecureAccess(to: coordinatedURL) {
                    try String(contentsOf: coordinatedURL, encoding: .utf8)
                }
                text = fileContent
                initialText = fileContent  // Track loaded state for unsaved changes detection
                updatePromptsFromText()  // Sync loaded to appState
                updateUndoRedoStates()
                self.error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
        if let coordError = coordError {
            self.error = coordError.localizedDescription
        }
    }

    // MARK: - Saving

    private func saveAndDismissIfSheet() {
        if isSheet {
            // For sheet mode: save, show toast briefly, then dismiss
            saveActionWithCompletion {
                withAnimation { showSavedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    dismiss()
                }
            }
        } else {
            // For panel mode: just save (toast shown by saveAction)
            saveAction()
        }
    }

    private func saveActionWithCompletion(_ completion: @escaping () -> Void) {
        Log.debug("Save action with completion - fileURL exists: \(fileURL != nil)")

        if let existingURL = fileURL {
            // Direct save to existing file with security-scoped access
            let didStart = existingURL.startAccessingSecurityScopedResource()
            Log.debug("Started security-scoped access for save: \(didStart)")

            performSave(to: existingURL) { success in
                if didStart {
                    existingURL.stopAccessingSecurityScopedResource()
                }
                if success {
                    self.appState.batchFileVersion += 1
                    completion()
                }
            }
        } else {
            // No file yet - need to pick location first
            let suggestedName = "batch.txt"
            PlatformFileSaver.presentSavePanel(
                suggestedName: suggestedName,
                allowedTypes: [.plainText],
                callback: { result in
                    switch result {
                    case .success(let url):
                        self.performSave(to: url) { success in
                            if success {
                                self.appState.batchFileVersion += 1
                                completion()
                            }
                        }
                    case .failure(let err):
                        if !(err.localizedDescription.lowercased().contains("cancel")) {
                            self.error = err.localizedDescription
                        }
                    }
                }
            )
        }
    }

    // TextEditorView.swift – Full saveAction function + helper
    private func saveAction() {
        Log.debug("Save action - fileURL exists: \(fileURL != nil) (\(fileURL?.path ?? "nil"))")

        if let existingURL = fileURL {
            // File already exists - save directly with security-scoped access
            let didStart = existingURL.startAccessingSecurityScopedResource()
            Log.debug("Started security-scoped access for save: \(didStart)")

            performSave(to: existingURL) { success in
                if didStart {
                    existingURL.stopAccessingSecurityScopedResource()
                }
                if success {
                    self.appState.batchFileVersion += 1
                    withAnimation { self.showSavedToast = true }
                }
            }
        } else {
            // No file yet - show save picker
            let suggestedName = "batch.txt"
            presentSavePicker(suggestedName: suggestedName)
        }
    }

    private func presentSavePicker(suggestedName: String) {
        PlatformFileSaver.presentSavePanel(
            suggestedName: suggestedName,
            allowedTypes: [.plainText],
            callback: { result in
                switch result {
                case .success(let url):
                    self.performSave(to: url) { success in
                        if success {
                            self.appState.batchFileVersion += 1
                            self.showSavedToast = true
                        }
                    }
                case .failure(let err):
                    if !(err.localizedDescription.lowercased().contains("cancel")) {
                        self.error = err.localizedDescription
                    }
                }
            }
        )
    }

    // TextEditorView.swift – Full performSave function (unchanged from last reliable version, with minor log improvements)
    private func performSave(to url: URL, completion: @escaping (Bool) -> Void) {
        var coordError: NSError?
        let options: NSFileCoordinator.WritingOptions = fileURL == nil ? [] : [.forReplacing]

        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordError) { coordinatedURL in
            do {
                let didStart = coordinatedURL.startAccessingSecurityScopedResource()
                Log.debug("Write access started: \(didStart)")
                defer { if didStart { coordinatedURL.stopAccessingSecurityScopedResource() } }
                
                // Ensure parent directory exists (safe for both platforms)
                let parentDir = coordinatedURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parentDir.path) {
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    Log.debug("Created parent directory: \(parentDir.path)")
                }
                
                try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                
                DispatchQueue.main.async {
                    // Sync prompts from editor text
                    let newPrompts = self.text
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    self.appState.batchPrompts = newPrompts
                    
                    self.initialText = self.text  // Mark saved
                    
                    Log.debug("Saved to \(coordinatedURL.path) (overwrite: \(self.fileURL != nil))")
                    
                    // Always update state with the saved URL
                    self.fileURL = coordinatedURL
                    self.appState.batchFilePath = coordinatedURL.path
                    self.appState.batchFileURL = coordinatedURL
                    
                    // Always refresh bookmark after successful save
                    var bookmarkCreated = false
                    
                    let accessing = coordinatedURL.startAccessingSecurityScopedResource()
                    defer { if accessing { coordinatedURL.stopAccessingSecurityScopedResource() } }
                    
                    #if os(macOS)
                    // Use withSecurityScope without read-only restriction to allow saving
                    var bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]

                    if let bookmark = try? coordinatedURL.bookmarkData(options: bookmarkOptions) {
                        AppStorageContext.defaults.set(bookmark, forKey: "batchFileBookmark")
                        Log.debug("SAVE: Refreshed security-scoped bookmark (length: \(bookmark.count) bytes)")
                        bookmarkCreated = true
                    } else {
                        Log.debug("SAVE: Security-scoped refresh failed – falling back")
                    }
                    #else
                    var bookmarkOptions: URL.BookmarkCreationOptions = .minimalBookmark
                    if let bookmark = try? coordinatedURL.bookmarkData(options: bookmarkOptions) {
                        AppStorageContext.defaults.set(bookmark, forKey: "batchFileBookmark")
                        Log.debug("SAVE: Refreshed minimal bookmark (iOS) (length: \(bookmark.count) bytes)")
                        bookmarkCreated = true
                    } else {
                        Log.debug("SAVE: Minimal bookmark refresh failed (iOS)")
                    }
                    #endif
                    
                    if !bookmarkCreated {
                        bookmarkOptions = .minimalBookmark
                        if let minimalBookmark = try? coordinatedURL.bookmarkData(options: bookmarkOptions) {
                            AppStorageContext.defaults.set(minimalBookmark, forKey: "batchFileBookmark")
                            Log.debug("SAVE: Minimal bookmark refreshed as fallback (length: \(minimalBookmark.count) bytes)")
                        } else {
                            Log.debug("SAVE: Even minimal bookmark refresh failed")
                            self.error = "Saved file, but failed to refresh bookmark. Re-select if issues."
                        }
                    }
                    
                    self.appState.batchFileVersion += 1
                    NotificationCenter.default.post(name: .batchFileUpdated, object: nil)
                    self.showSavedToast = true
                    completion(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                }
                completion(false)
            }
        }
        
        if let coordError = coordError {
            DispatchQueue.main.async {
                self.error = coordError.localizedDescription
            }
            completion(false)
        }
    }
}
