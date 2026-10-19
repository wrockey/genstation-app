//HistoryView.swift
import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif
import SWCompression
import GenStationCore
@preconcurrency import Foundation

// Add this wrapper to safely capture UndoManager in closures
struct UndoManagerWrapper: @unchecked Sendable {
    let manager: UndoManager
}
    
extension View {
    /// Conditionally apply modifiers (ViewBuilder-safe!)
    @ViewBuilder
    func applyIf<TrueContent: View>(
        _ condition: @autoclosure () -> Bool,
        @ViewBuilder trueContent: (Self) -> TrueContent
    ) -> some View {
        if condition() {
            trueContent(self)
        } else {
            self
        }
    }
}

#if os(macOS)
private func createTarGzNative(from directoryURL: URL, to tarGzURL: URL) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "tar", "czf", tarGzURL.path,
        "-C", directoryURL.path,
        "."
    ]
    
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        Log.debug("Native tar failed: \(error)")
        return false
    }
}

private func extractTarGzNative(from tarGzURL: URL, to destinationURL: URL) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "tar", "xzf", tarGzURL.path,
        "-C", destinationURL.path
    ]
    
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        Log.debug("Native tar extract failed: \(error)")
        return false
    }
}
#endif

 
struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.undoManager) private var undoManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    var showTitle: Bool = true  // Whether to show "History" header (false when in sheet with navigationTitle)
    var onDescribeImage: ((HistoryItem) async -> Void)? = nil  // Callback for image-to-prompt feature
    @State private var fullHistoryItemId: UUID? = nil
    @State private var toastMessage: String? = nil
    @State private var showToast: Bool = false
    @State private var toastAction: (() -> Void)? = nil
    @State private var showClearHistoryConfirmation: Bool = false
    @State private var folderToRename: Folder? = nil
    @State private var proposedFolderName: String = ""
    @State private var isEditing: Bool = false
    @State private var isUpscaling: Bool = false
    @State private var upscaleProgress: Double = 0
    @State private var isImporting: Bool = false
    @State private var isExporting: Bool = false
    #if os(macOS)
    #if swift(>=5.7)
    @Environment(\.openWindow) private var openWindow
    #endif
    #endif
    @State private var activeEntry: HistoryEntry? = nil
    @State private var sharingInProgress = false
    @Environment(\.dismiss) private var dismiss
    private var hasSelectedAnything: Bool { !appState.historyState.multiSelection.isEmpty }
    
    @State private var showFABMenu: Bool = false
    
    
    private func allVisibleIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        let lowerSearch = searchText.lowercased()  // Trim if desired: .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let dateFormatter = DateFormatter()  // Create once for efficiency
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        func collect(from entries: [HistoryEntry], isParentExpanded: Bool = true) -> Bool {
            var hasVisible = false
            for entry in entries {
                switch entry {
                case .item(let item):
                    let isMatch = lowerSearch.isEmpty ||
                        item.prompt.lowercased().contains(lowerSearch) ||
                        dateFormatter.string(from: item.date).lowercased().contains(lowerSearch)
                    if isMatch && isParentExpanded {  // Only collect if visible and parent expanded
                        ids.insert(entry.id)  // Item IDs only
                        hasVisible = true
                    }
                case .folder(let folder):
                    let isExpanded = appState.historyState.expandedFolderIDs.contains(folder.id)
                    let childrenHasVisible = collect(from: folder.children, isParentExpanded: isExpanded)  // Propagate flag
                    let nameMatch = lowerSearch.isEmpty || folder.name.lowercased().contains(lowerSearch)
                    if (nameMatch || childrenHasVisible) && isParentExpanded {
                        // Do NOT insert folder.id -- skip for safety
                        hasVisible = true  // Still show folder for context
                    }
                }
            }
            return hasVisible
        }
        _ = collect(from: filteredHistory)  // Root always "expanded"
        return ids
    }
    private var saveSelectedToPhotosLabel: LocalizedStringKey {
        #if os(iOS)
        "Save Selected to Photos"
        #else
        "Export Selected…"
        #endif
    }
    
    private func visibleItemCount(in entries: [HistoryEntry]) -> Int {
        return entries
            .flatMap { entry -> [HistoryItem] in
                if case .item(let item) = entry {
                    return item.prompt.lowercased().contains(searchText.lowercased()) ||
                           dateFormatter.string(from: item.date).lowercased().contains(searchText.lowercased())
                           ? [item] : []
                }
                if case .folder(let folder) = entry {
                    return visibleItems(in: folder.children)
                }
                return []
            }
            .count
    }
    
    private func visibleItems(in entries: [HistoryEntry]) -> [HistoryItem] {
        var result: [HistoryItem] = []
        
        for entry in entries {
            switch entry {
            case .item(let item):
                if item.prompt.lowercased().contains(searchText.lowercased()) ||
                   dateFormatter.string(from: item.date).lowercased().contains(searchText.lowercased()) {
                    result.append(item)
                }
            case .folder(let folder):
                result += visibleItems(in: folder.children)
            }
        }
        return result
    }
    
    private func visibleSelectedItemCount() -> Int {
        let selectedEntries = appState.historyState.findEntries(with: appState.historyState.multiSelection)
        
        return selectedEntries
            .flatMap { entry -> [HistoryItem] in
                if case .item(let item) = entry {
                    return item.prompt.lowercased().contains(searchText.lowercased()) ||
                           dateFormatter.string(from: item.date).lowercased().contains(searchText.lowercased())
                           ? [item] : []
                }
                if case .folder(let folder) = entry {
                    return visibleItems(in: folder.children)
                }
                return []
            }
            .count
    }
    
 
    // ADD: Reusable folder toast
    private func addFolderWithToast() {
        appState.historyState.addFolder(undoManager: undoManager)
        toastMessage = "Folder added"
        toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
            undoManager?.undo()
        } : nil
        showToast = true
        hideToastAfterDelay()
    }
    
    private func triggerShare(for entry: HistoryEntry) async {
        sharingInProgress = true
        defer { sharingInProgress = false }
        
        switch entry {
        case .item(let item):
            await shareSingleItem(item)
        case .folder(let folder):
            await shareSingleFolder(folder)
        }
    }
    
    // MARK: - Import Duplicate Detection
    private struct ItemSignature: Hashable {
        let prompt: String
        let date: Date
        let modelUsed: String?
//        let fileName: String
        
        init(from item: HistoryItem) {
            self.prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            self.date = item.date
            self.modelUsed = item.modelUsed
//            self.fileName = URL(fileURLWithPath: item.imagePath ?? "").lastPathComponent
        }
    }
    
    private func shareSelectedIfPossible() {
        guard !appState.historyState.multiSelection.isEmpty else { return }
        guard !sharingInProgress else { return }
        sharingInProgress = true

        let selectedEntries = appState.historyState.findEntries(with: appState.historyState.multiSelection)

        Task {
            if let packageURL = await createSharePackage(for: selectedEntries) {
                await MainActor.run {
                    PlatformShareSheet.present(items: [packageURL])
                    sharingInProgress = false
                    appState.historyState.multiSelection.removeAll()
                }
            } else {
                await MainActor.run {
                    toastMessage = "Failed to prepare share package"
                    showToast = true
                    hideToastAfterDelay()
                    sharingInProgress = false
                }
            }
        }
    }
    
    // MARK: - Create .tar.gz – works on iOS & macOS, no external libs
 
    private func createSharePackage(for entries: [HistoryEntry]) async -> URL? {
        let fm = FileManager.default
        let tempBase = AppStorageContext.current.temporaryDirectory
        let dateString = Date().fileSafeString()
        let tempDir = tempBase.appendingPathComponent("GenStation_\(dateString)")
 
        // 1. Show immediate feedback
        isExporting = true
        await showToast("Preparing export…")
 
        do { try tempDir.createDirectoryWithStandardPermissions() } catch {
            isExporting = false
            await showToast("Failed to create temp folder")
            Log.debug("Failed to create temp dir: \(error)")
            return nil
        }
 
        var seenPaths = Set<String>()
        var allItems: [HistoryItem] = []
 
        // Collect all items (fast — no disk access yet)
        func collectItems(from entry: HistoryEntry) {
            switch entry {
            case .item(let item):
                if let path = item.imagePath, !seenPaths.contains(path) {
                    seenPaths.insert(path)
                    allItems.append(item)
                }
            case .folder(let folder):
                for child in folder.children {
                    collectItems(from: child)
                }
            }
        }
 
        for entry in entries { collectItems(from: entry) }
 
        // Build metadata JSON
        let containsOnlyFolders = !entries.contains { if case .item = $0 { true } else { false } }
        let container: ExportContainer
        if containsOnlyFolders {
            let exportFolders = entries.compactMap { entry -> ExportFolder? in
                if case .folder(let f) = entry {
                    var dummy: [HistoryItem] = []
                    return ExportFolder(from: f, itemsCollector: &dummy)
                }
                return nil
            }
            container = ExportContainer(folders: exportFolders)
        } else {
            var rootExportEntries: [ExportEntry] = []
            for entry in entries {
                var dummy: [HistoryItem] = []
                let exportEntry = ExportEntry(from: entry, itemsCollector: &dummy)
                rootExportEntries.append(exportEntry)
            }
            container = ExportContainer(rootEntries: rootExportEntries)
        }
 
        try? JSONEncoder().encode(container).write(to: tempDir.appendingPathComponent("history.json"))
 
        // 2. Copy files (this is the long part)
        let totalItems = allItems.count
        var copiedCount = 0
        if totalItems > 0 {
            await showToast("Copying 0/\(totalItems) images…")
        }

        for item in allItems {
            guard let srcPath = item.imagePath,
                  item.fileExists(appState: appState) else { continue }
 
            let srcURL = URL(fileURLWithPath: srcPath)
            var data: Data?
 
            if let outputDir = appState.settings.outputDirectory {
                let accessed = outputDir.startAccessingSecurityScopedResource()
                defer { if accessed { outputDir.stopAccessingSecurityScopedResource() } }
                let fileAccessed = srcURL.startAccessingSecurityScopedResource()
                defer { if fileAccessed { srcURL.stopAccessingSecurityScopedResource() } }
                data = try? Data(contentsOf: srcURL)
            } else {
                data = try? Data(contentsOf: srcURL)
            }
 
            guard let fileData = data else { continue }
 
            let finalName = srcURL.lastPathComponent
            var destURL = tempDir.appendingPathComponent(finalName)
            var copy = 1
            while fm.fileExists(atPath: destURL.path) {
                let name = srcURL.deletingPathExtension().lastPathComponent
                let ext = srcURL.pathExtension
                destURL = tempDir.appendingPathComponent("\(name)_\(copy).\(ext)")
                copy += 1
            }
 
            do {
                try fileData.write(to: destURL, options: .atomic)
                // Preserve permissions (optional, but nice)
                if let attrs = try? fm.attributesOfItem(atPath: srcURL.path),
                   let perms = attrs[.posixPermissions] as? NSNumber {
                    try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: destURL.path)
                } else {
                    destURL.setStandardPermissions(isDirectory: false)
                }
                copiedCount += 1
                let pct = Int(Double(copiedCount) / Double(totalItems) * 100)
                await showToast("Copying images... \(pct)% (\(copiedCount)/\(totalItems))")
            } catch {
                Log.debug("Failed to write exported file: \(error)")
            }
        }

        // 3. Final step: compress
        await showToast("Compressing package…")
 
        let tarGzURL = tempDir.deletingLastPathComponent()
            .appendingPathComponent("GenStation_\(dateString).tar.gz")
 
        if createTarGzWithPermissions(from: tempDir, to: tarGzURL) {
            try? fm.removeItem(at: tempDir)
            isExporting = false
            await showToast("Export ready!")
            return tarGzURL
        } else {
            isExporting = false
            await showToast("Failed to compress, sharing folder…")
            Log.debug("Tar.gz creation failed – falling back to raw folder")
            return tempDir
        }
    }
    private func createTarGzWithPermissions(from directoryURL: URL, to tarGzURL: URL) -> Bool {
        #if os(macOS)
        if createTarGzNative(from: directoryURL, to: tarGzURL) {
            return true
        } else {
            Log.debug("Native tar failed, falling back to SWCompression")
        }
        #endif
        
        let fm = FileManager.default
        var entries: [TarEntry] = []
        
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        ) else {
            Log.debug("Failed to enumerate directory")
            return false
        }
        
        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.relativePath(to: directoryURL)
            guard !relativePath.isEmpty else { continue }
            
            do {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                let isDir = values.isDirectory == true
                let mtime = values.contentModificationDate ?? Date()
                
                if isDir {
                    var dirPath = relativePath
                    if !dirPath.hasSuffix("/") { dirPath += "/" }
                    
                    var info = TarEntryInfo(name: dirPath, type: .directory)
                    info.permissions = Permissions(rawValue: 0o755)
                    info.modificationTime = mtime
                    entries.append(TarEntry(info: info, data: nil))
                } else {
                    guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
                        Log.debug("   Skipping empty/missing file: \(relativePath)")
                        continue
                    }
                    
                    var info = TarEntryInfo(name: relativePath, type: .regular)
                    info.permissions = Permissions(rawValue: 0o644)
                    info.modificationTime = mtime
                    entries.append(TarEntry(info: info, data: data))
                }
            } catch {
                Log.debug("   Skipping \(relativePath): \(error)")
            }
        }
        
        let tarData = TarContainer.create(from: entries)
        
        guard let gzData = try? GzipArchive.archive(data: tarData) else {
            Log.debug("Failed to gzip archive")
            return false
        }
        
        do {
            try gzData.write(to: tarGzURL, options: .atomic)
            Log.debug("Successfully created tar.gz with correct embedded permissions: \(tarGzURL.path)")
            return true
        } catch {
            Log.debug("Failed to write tar.gz: \(error)")
            return false
        }
    }
 
    
    func shareSingleFolder(_ folder: Folder) async {
        sharingInProgress = true
        defer { sharingInProgress = false }
        
        let entry = HistoryEntry.folder(folder)
        
        guard let packageURL = await createSharePackage(for: [entry]) else {
            await MainActor.run {
                toastMessage = "Failed to prepare folder"
                showToast = true
                hideToastAfterDelay()
            }
            return
        }
        
        await MainActor.run {
            PlatformShareSheet.present(items: [packageURL])
        }
    }
    
    func shareSingleItem(_ item: HistoryItem) async {
        sharingInProgress = true
        defer { sharingInProgress = false }
        
        let entry = HistoryEntry.item(item)
        
        guard let packageURL = await createSharePackage(for: [entry]) else {
            await MainActor.run {
                toastMessage = "Failed to prepare item for sharing"
                showToast = true
                hideToastAfterDelay()
            }
            return
        }
        
        await MainActor.run {
            PlatformShareSheet.present(items: [packageURL])
        }
    }
 
    #if os(iOS)
    private var isCompact: Bool {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        return isPhone // Only true for iPhone
    }
    #endif
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
    
    private var filteredHistory: [HistoryEntry] {
        let base = searchText.isEmpty ? appState.historyState.history : filterEntries(appState.historyState.history, with: searchText)
        return sortedEntries(base)
    }
 

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                headerWithSearch  // Inline title + search field
                historyList       // Direct tree/list content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            fabOverlay  // + FAB with popover menu
            
            // Toast overlay
            if showToast, let message = toastMessage {
                Group {
                    if let action = toastAction {
                        LiquidGlassToast(message: message, actionLabel: "Undo", action: {
                            action()
                            withAnimation { showToast = false }
                        })
                    } else {
                        LiquidGlassToast(message: message)
                    }
                }
                .transition(.toastTransition)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 50)
                .onAppear {
                    hideToastAfterDelay()
                }
            }
        }
        // Alerts/sheets applied directly
        .alert("Clear History", isPresented: $showClearHistoryConfirmation) {
            Button("Clear", role: .destructive) {
                appState.historyState.clearHistory(undoManager: undoManager)
                toastMessage = "History cleared"
                toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
                    undoManager?.undo()
                } : nil
                showToast = true
                hideToastAfterDelay()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all history entries but keep your files intact. Are you sure?")
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { folderToRename != nil },
            set: { if !$0 { folderToRename = nil } }
        )) {
            TextField("Folder Name", text: $proposedFolderName)
                .disableAutocorrection(true)
            Button("OK") {
                if let folder = folderToRename, !proposedFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                    appState.historyState.updateFolderName(with: folder.id, newName: proposedFolderName, undoManager: undoManager)
                }
                folderToRename = nil
                proposedFolderName = ""
            }
            Button("Cancel", role: .cancel) {
                folderToRename = nil
                proposedFolderName = ""
            }
        } message: {
            Text("Enter a new name for the folder.")
        }
        .onChange(of: appState.historyState.history) { _ in
            // Clear selection when history changes externally (e.g., delete/move),
            // but only if not in edit mode — avoids cascading state resets
            // that can knock iOS out of edit mode during selection
            if !isEditing {
                appState.historyState.multiSelection.removeAll()
            }
            activeEntry = nil
        }
        .onChange(of: appState.historyState.multiSelection) { newSelection in
            // Auto-enter edit mode if items are selected while not editing
            // (e.g., user selected items from full history item viewer)
            if !newSelection.isEmpty && !isEditingBinding.wrappedValue {
                withAnimation(DS.Anim.standard) {
                    isEditingBinding.wrappedValue = true
                }
            }
        }
        .onChange(of: appState.ui.requestFocusHistorySearch) { requested in
            if requested {
                appState.ui.requestFocusHistorySearch = false
                isSearchFocused = true
            }
        }
        .onChange(of: appState.ui.requestImportPackageURL) { url in
            if let url = url {
                appState.ui.requestImportPackageURL = nil
                Task {
                    await processImportedPackage(at: url)
                }
            }
        }
    #if os(iOS)
        // Responsive column sizing (iOS only - on macOS, the inspector handles sizing)
        .navigationSplitViewColumnWidth(min: minSidebarWidth, ideal: sidebarWidth, max: maxSidebarWidth)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            deviceOrientation = UIDevice.current.orientation
        }
    #endif
        
        
    }
    private var fabOverlay: some View {
        ZStack {
            // Dimmed backdrop when menu is open
            if showFABMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(DS.Anim.springFast) {
                            showFABMenu = false
                        }
                    }
                    .transition(.opacity)
            }

            VStack {
                Spacer()

                // Bottom selection bar (edit mode only)
                if isEditingBinding.wrappedValue {
                    selectionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 12) {
                        // Fan-out menu items (bottom = closest to FAB = most common)
                        if showFABMenu {
                            fabMenuItem(icon: "trash", label: "Clear History", color: .red) {
                                showClearHistoryConfirmation = true
                            }
                            .transition(fabItemTransition(index: 3))

                            fabMenuItem(icon: "tray.and.arrow.down.fill", label: "Import Package", color: .primary) {
                                importGenStationPackage()
                            }
                            .transition(fabItemTransition(index: 2))

                            fabMenuItem(icon: "folder.badge.plus", label: "Add Folder", color: .primary) {
                                addFolderWithToast()
                            }
                            .transition(fabItemTransition(index: 1))

                            fabMenuItem(icon: "checkmark.circle", label: "Select Items", color: .primary) {
                                isEditingBinding.wrappedValue = true
                            }
                            .transition(fabItemTransition(index: 0))
                        }

                        // Main FAB button
                        Button {
                            if isEditingBinding.wrappedValue {
                                withAnimation(DS.Anim.standard) {
                                    isEditingBinding.wrappedValue = false
                                    appState.historyState.multiSelection.removeAll()
                                }
                            } else {
                                withAnimation(DS.Anim.springFast) {
                                    showFABMenu.toggle()
                                }
                            }
                        } label: {
                            Image(systemName: isEditingBinding.wrappedValue ? "checkmark" : "plus")
                                .font(.system(size: 28, weight: .bold))
                                .rotationEffect(showFABMenu ? .degrees(45) : .zero)
                                .frame(width: 60, height: 60)
                                .background(Circle().fill(isEditingBinding.wrappedValue ? Color.green : Color.blue))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.15), radius: 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isEditingBinding.wrappedValue ? "Done editing" : showFABMenu ? "Close menu" : "Open menu")
                    }
                    .padding()
                }
            }
        }
    }

    private func fabMenuItem(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(DS.Anim.springFast) { showFABMenu = false }
            action()
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 20)
            }
            .foregroundColor(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.1), radius: 8)
        }
        .buttonStyle(.plain)
    }

    private func fabItemTransition(index: Int) -> AnyTransition {
        .scale(scale: 0.5, anchor: .bottomTrailing)
        .combined(with: .opacity)
        .animation(DS.Anim.springFast.delay(Double(index) * 0.04))
    }

    // MARK: - Selection Bar
    private var selectionBar: some View {
        HStack(spacing: 16) {
            // Selection count
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                Text("\(appState.historyState.multiSelection.count) selected")
                    .fontWeight(.medium)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 20) {
                // Save to Photos (iOS) / Export (macOS)
                Button {
                    Task {
                        #if os(iOS)
                        let selectedItems = appState.historyState.findEntries(with: appState.historyState.multiSelection)
                            .flatMap { $0.allItems }

                        let (success, total) = await PhotosLibraryHelper.saveToPhotosLibrary(
                            items: selectedItems,
                            appState: appState
                        )
                        await MainActor.run {
                            if success == total && success > 0 {
                                toastMessage = "Saved \(success) image\(success == 1 ? "" : "s") to Photos"
                            } else if success == 0 {
                                toastMessage = "No images were saved"
                            } else {
                                toastMessage = "Saved \(success)/\(total) to Photos"
                            }
                            showToast = true
                            hideToastAfterDelay()
                            appState.historyState.multiSelection.removeAll()
                        }
                        #elseif os(macOS)
                        await saveSelectedHistoryItemsToFolder()
                        appState.historyState.multiSelection.removeAll()
                        #endif
                    }
                } label: {
                    #if os(iOS)
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20))
                    #else
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 20))
                    #endif
                }
                .buttonStyle(.plain)
                .disabled(appState.historyState.multiSelection.isEmpty)
                .foregroundColor(appState.historyState.multiSelection.isEmpty ? .gray : .accentColor)
                .help(selectionBarSaveHelp)
                .accessibilityLabel("Save selected items")

                // Share (AirDrop package)
                Button {
                    shareSelectedIfPossible()
                    // Selection cleared after share completes in shareSelectedIfPossible
                } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .disabled(appState.historyState.multiSelection.isEmpty || sharingInProgress)
                .foregroundColor(appState.historyState.multiSelection.isEmpty || sharingInProgress ? .gray : .accentColor)
                .help("Share as GenStation package via AirDrop")
                .accessibilityLabel("Share via AirDrop")

                // Delete
                Button {
                    let entries = appState.historyState.findEntries(with: appState.historyState.multiSelection)
                    presentDeleteConfirmation(for: entries)
                    // Selection cleared after delete in presentDeleteConfirmation's onConfirm
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .disabled(appState.historyState.multiSelection.isEmpty)
                .foregroundColor(appState.historyState.multiSelection.isEmpty ? .gray : .red)
                .help("Delete selected items")
                .accessibilityLabel("Delete selected items")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.panel)
                .fill(Color.systemBackground)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: -2)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var selectionBarSaveHelp: String {
        #if os(iOS)
        return "Save selected images to Photos"
        #else
        return "Export selected images to folder"
        #endif
    }
    private var headerWithSearch: some View {
            VStack(spacing: 8) {
                // Title - only on iOS when not in sheet (macOS has header in PowerPanelContentView)
                #if os(iOS)
                if showTitle {
                    Text("History")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                #endif

                // Inline search field
                TextField("Search prompts or dates...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .padding(.horizontal)
                    .help("Search history by prompt text or date")
                    .accessibilityLabel("Search prompts or dates")
            }
            .padding(.vertical, 8)
            .background(Color.systemBackground)
        }


    // ADD: State for orientation (replaces screenSize)
    #if os (iOS)
    @State private var deviceOrientation = UIDevice.current.orientation
    #endif
    
    // NEW: Dynamic width calculation using orientation
    private var sidebarWidth: CGFloat {
        #if os(iOS)
        guard !isCompact else {
            return 375  // iPhone (compact): Keep original; no sidebar anyway
        }
        
        let bounds = UIScreen.main.bounds
        let isLandscape = deviceOrientation.isLandscape
        let screenWidth = isLandscape ? max(bounds.width, bounds.height) : min(bounds.width, bounds.height)
        
        if screenWidth < 800 {  // iPad mini portrait (~744pt)
            return 300
        } else if screenWidth < 950 {  // Regular iPad portrait (~810–834pt)
            return 370
        } else {  // Landscape or wider (~1024+pt)
            return 375
        }
        #else
        return 325  // macOS: Keep fixed
        #endif
    }
    
    private var minSidebarWidth: CGFloat {
        #if os(iOS)
        guard !isCompact else { return 300 }  // iPhone: Slightly narrower min
        
        let bounds = UIScreen.main.bounds
        let isLandscape = deviceOrientation.isLandscape
        let screenWidth = isLandscape ? max(bounds.width, bounds.height) : min(bounds.width, bounds.height)
        
        if screenWidth < 800 {  // iPad mini portrait
            return 280
        } else if screenWidth < 950 {  // Regular iPad portrait
            return 300
        } else {  // Landscape
            return 320
        }
        #else
        return 280  // macOS: Allow shrinking a bit
        #endif
    }
    
    private var maxSidebarWidth: CGFloat {
        #if os(iOS)
        guard !isCompact else { return 400 }  // iPhone: Not really resizable, but set reasonable
        
        let bounds = UIScreen.main.bounds
        let isLandscape = deviceOrientation.isLandscape
        let screenWidth = isLandscape ? max(bounds.width, bounds.height) : min(bounds.width, bounds.height)
        
        if screenWidth < 800 {  // iPad mini portrait: Don't allow too wide
            return 350
        } else if screenWidth < 950 {
            return 400
        } else {  // Landscape: More room
            return 450
        }
        #else
        return 400  // macOS: Cap to prevent over-expansion
        #endif
    }
    
    
    private func presentDeleteConfirmation(for entries: [HistoryEntry]) {
        let itemCount = entries.flatMap { $0.allItems }.count
        let folderCount = entries.filter { $0.isFolder }.count
        let hasFiles = entries.flatMap { $0.allItems }.contains { $0.fileExists(appState: appState) }
        
        let title: String
        let message: String
        
        if itemCount == 0 && folderCount > 0 {
            title = folderCount == 1 ? "Delete Empty Folder" : "Delete \(folderCount) Empty Folders"
            message = folderCount == 1
                ? "Are you sure you want to delete this empty folder from history?"
                : "Are you sure you want to delete these empty folders from history?"
        } else {
            title = itemCount == 1 ? "Delete Item" : "Delete \(itemCount) Items"
            message = itemCount == 1
                ? "Are you sure you want to delete this item from history?"
                : "Are you sure you want to delete these \(itemCount) items from history?"
        }
        
        let info = DeleteConfirmationInfo(
            title: title,
            message: message,
            hasDeletableFiles: hasFiles,
            onConfirm: { deleteFiles in
                // Remove deleted items from session gallery
                let deletedItemIds = Set(entries.flatMap { $0.allItems }.map { $0.id })
                appState.ui.sessionGeneratedIDs.removeAll { deletedItemIds.contains($0) }
                appState.ui.objectWillChange.send()

                appState.historyState.deleteEntries(entries, deleteFiles: deleteFiles, undoManager: undoManager)
                let visibleItemCount = visibleItemCount(in: entries)  // ← Updated helper
                let visibleFolderCount = entries.filter { $0.isFolder }.count
                
                toastMessage = {
                    if visibleItemCount > 0 && visibleFolderCount > 0 {
                        return "Deleted \(visibleItemCount) item\(visibleItemCount == 1 ? "" : "s") and \(visibleFolderCount) folder\(visibleFolderCount == 1 ? "" : "s")"
                    } else if visibleItemCount > 0 {
                        return visibleItemCount == 1 ? "Item deleted" : "\(visibleItemCount) items deleted"
                    } else if visibleFolderCount > 0 {
                        return visibleFolderCount == 1 ? "Folder deleted" : "\(visibleFolderCount) folders deleted"
                    } else {
                        return "Deleted"
                    }
                }()
                // Set undo action for toast
                toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
                    undoManager?.undo()
                } : nil
                showToast = true
                hideToastAfterDelay()
                appState.historyState.multiSelection.removeAll()
            }
        )
        
        appState.presentedModal = .deleteConfirmation(info)
    }
 

 
    
    private var overlayContent: some View {
        Group {
 
            if showToast, let message = toastMessage {
                Group {
                    if let action = toastAction {
                        LiquidGlassToast(message: message, actionLabel: "Undo", action: {
                            action()
                            withAnimation { showToast = false }
                        })
                    } else {
                        LiquidGlassToast(message: message)
                    }
                }
                .transition(.toastTransition)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 50)
                .onAppear {
                    hideToastAfterDelay()
                }
            }
        }
    }

    private func hideToastAfterDelay() {
        // Don't auto-hide while a long operation is in progress — progress updates drive the toast
        guard !isUpscaling && !isImporting && !isExporting else { return }
        // Longer delay (5s) when toast has undo action, shorter (2s) for simple toasts
        let delay: TimeInterval = toastAction != nil ? 5.0 : 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.3)) {
                showToast = false
                toastAction = nil
            }
        }
    }
    
    private var header: some View {
            #if os(macOS)
            HStack {
                Button(action: {
                    withAnimation(DS.Anim.smooth) {
                        columnVisibility = columnVisibility == .all ? .detailOnly : .all
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("Collapse history sidebar")
                .accessibilityLabel("Collapse history sidebar")

                if !isEditing {
                    Text("History")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .kerning(0.4)
                        .foregroundColor(.primary.opacity(0.9))
                        .help("View past generated images and videos")
                }

                Button(action: {
                    showClearHistoryConfirmation = true
                }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .disabled(filteredHistory.isEmpty)
                .help("Clear all history entries")
                .accessibilityLabel("Clear history")
        
                Spacer()
        
                Button(action: {
                    let actionName = undoManager?.undoActionName ?? ""
                    undoManager?.undo()
                    toastMessage = actionName.isEmpty ? "Action undone" : "Undid \(actionName)"
                    toastAction = nil
                    showToast = true
                    hideToastAfterDelay()
                }) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(undoManager?.canUndo == true ? .blue : .secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!(undoManager?.canUndo ?? false))
                .help("Undo last action")
                .accessibilityLabel("Undo")

                Button(action: {
                    let actionName = undoManager?.redoActionName ?? ""
                    undoManager?.redo()
                    toastMessage = actionName.isEmpty ? "Action redone" : "Redid \(actionName)"
                    toastAction = nil
                    showToast = true
                    hideToastAfterDelay()
                }) {
                    Image(systemName: "arrow.uturn.right")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(undoManager?.canRedo == true ? .blue : .secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!(undoManager?.canRedo ?? false))
                .help("Redo last action")
                .accessibilityLabel("Redo")
                commonActions(iconSize: 16, buttonTextSize: 13)
            }
            .padding(.horizontal)
           
            #else
            HStack(spacing: 24) {
                if isCompact {
                    if !isEditingBinding.wrappedValue {
                 
                            Text("History")
                                .font(.system(size: 24, weight: .semibold, design: .default))
                                .kerning(0.2)
                                .minimumScaleFactor(0.8)
                                .lineLimit(1)
                                .help("View past generated images and videos")
                        
                    }
        
                    Spacer()
        
                    if !isEditingBinding.wrappedValue {
                        Button(action: {
                            showClearHistoryConfirmation = true
                        }) {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 24))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .disabled(filteredHistory.isEmpty)
                        .help("Clear all history entries")
                        .accessibilityLabel("Clear history")
                    }
        
                    commonActions(iconSize: 20, buttonTextSize: 17)
        
                    Button(action: {
                        appState.presentedModal = nil // Dismiss sheet
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Close history view")
                    .accessibilityLabel("Close history view")
                }  else {
                    // If any other, but since !compact = native, ok
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .onAppear {
                let sizeClassString = sizeClass == .compact ? "compact" : sizeClass == .regular ? "regular" : "nil"
                Log.debug("Header: isCompact = \(isCompact), isPhone = \(UIDevice.current.userInterfaceIdiom == .phone), isPad = \(UIDevice.current.userInterfaceIdiom == .pad), sizeClass = \(sizeClassString)")
            }
            #endif
        }
       
    @ViewBuilder
    private func commonActions(iconSize: CGFloat = 16, buttonTextSize: CGFloat = 13) -> some View {
        Group {
            if !isEditingBinding.wrappedValue {
                Button {
                    importGenStationPackage()
                } label: {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: iconSize))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .help("Import a GenStation shared folder package")
                .accessibilityLabel("Import package")
            }
               
            Button(action: {
                appState.historyState.addFolder(undoManager: undoManager)
                toastMessage = "Folder added"
                toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
                    undoManager?.undo()
                } : nil
                showToast = true
                hideToastAfterDelay()
            }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: iconSize))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .help("Add new folder")
            .accessibilityLabel("Add folder")
    
            if isEditingBinding.wrappedValue {
                Button {
                    let entries = appState.historyState.findEntries(with: appState.historyState.multiSelection)
                    presentDeleteConfirmation(for: entries)
                } label: {
                    Image(systemName: "trash")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(appState.historyState.multiSelection.isEmpty ? .gray : .red.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .disabled(appState.historyState.multiSelection.isEmpty)
                .help("Delete selected items")
                .accessibilityLabel("Delete selected items")
    
                #if os(iOS)
                Button(action: {
                    if !appState.historyState.multiSelection.isEmpty {
                        appState.historyState.moveToTop(entriesWithIds: Array(appState.historyState.multiSelection), inFolderId: nil, undoManager: undoManager)
                        appState.historyState.multiSelection.removeAll()
                        toastMessage = "Moved to top"
                        toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
                            undoManager?.undo()
                        } : nil
                        showToast = true
                        hideToastAfterDelay()
                    }
                }) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: iconSize))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(appState.historyState.multiSelection.isEmpty ? .gray : .blue.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .disabled(appState.historyState.multiSelection.isEmpty)
                .help("Move selected items to top")
                .accessibilityLabel("Move selected items to top")

                Button(action: {
                    if !appState.historyState.multiSelection.isEmpty {
                        appState.historyState.moveToBottom(entriesWithIds: Array(appState.historyState.multiSelection), inFolderId: nil, undoManager: undoManager)
                        appState.historyState.multiSelection.removeAll()
                        toastMessage = "Moved to bottom"
                        toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
                            undoManager?.undo()
                        } : nil
                        showToast = true
                        hideToastAfterDelay()
                    }
                }) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: iconSize))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(appState.historyState.multiSelection.isEmpty ? .gray : .blue.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .disabled(appState.historyState.multiSelection.isEmpty)
                .help("Move selected items to bottom")
                .accessibilityLabel("Move selected items to bottom")
                #endif
    
                Button(action: {
                    if !appState.historyState.multiSelection.isEmpty {
                        func addRecursively(entry: HistoryEntry) {
                            switch entry {
                            case .item(let item):
                                addToInputImages(item: item)
                            case .folder(let folder):
                                for child in folder.children {
                                    addRecursively(entry: child)
                                }
                            }
                        }
                        for entry in appState.historyState.findEntries(with: appState.historyState.multiSelection) {
                            addRecursively(entry: entry)
                        }
                        appState.historyState.multiSelection.removeAll()
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: iconSize))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(appState.historyState.multiSelection.isEmpty || !appState.canAddImages || appState.maxImageSlots == 0 ? .gray : .blue.opacity(0.8))
                }
                .buttonStyle(.borderless)
                .disabled(appState.historyState.multiSelection.isEmpty || !appState.canAddImages || appState.maxImageSlots == 0)
                .help("Add selected images to input")
                .accessibilityLabel("Add selected items to input")
                #if os(macOS)
                Button(action: {
                    Task { await saveSelectedHistoryItemsToFolder() }
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(hasSelectedAnything ? .blue.opacity(0.8) : .gray)
                }
                .disabled(!hasSelectedAnything)
                .buttonStyle(.borderless)
                .help("Export selected images to macOS folder")
                .accessibilityLabel("Export selected macOS images")
                #endif
                
                Button {
                    shareSelectedIfPossible()
                } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: iconSize))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(hasSelectedAnything ? .green.opacity(0.8) : .gray)
                }                .disabled(!hasSelectedAnything || sharingInProgress)
                    .buttonStyle(.borderless)
                    .help("Bundle items for AirDrop to GenStation on another device")
                    .accessibilityLabel("AirDrop GenStation Package")
            }
            
            Button{
                isEditingBinding.wrappedValue.toggle()
 
            } label: {
                Image(systemName: isEditingBinding.wrappedValue ? "checkmark" : "square.and.pencil")
                    .font(.system(size: iconSize))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .help("Select multiple items")
            .accessibilityLabel("Select multiple items")
        }
        
    }
    

 
    // MARK: - Import GenStation Package
    private func importGenStationPackage() {
        PlatformFilePicker.presentOpenPanel(
                allowedTypes: [
                    .zip,          // Finder zip, any third-party zip
                    .gzip,         // Covers .gz and many mis-detected .tar.gz
                    .folder
                ],
                allowsMultiple: false,
                canChooseDirectories: true,
                message: "Select a GenStation package (.zip, folder, .tar.gz/.tgz)",
                prompt: "Import"
            ) { result in
            // No [weak self] needed — this is a SYNC closure
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await self.processImportedPackage(at: url)
                }
            case .failure(let error):
                Task {
                    await self.showToast("Import failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @MainActor
    private func processImportedPackage(at url: URL) async {
        let fm = FileManager.default
        var contentURL: URL
        var isDir: ObjCBool = false
        
        #if os(iOS)
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
        guard accessGranted else {
            await showToast("Security-scoped access denied")
            return
        }
        contentURL = url
        #else
        contentURL = url
        #endif
        
        guard fm.fileExists(atPath: contentURL.path, isDirectory: &isDir) else {
            await showToast("File not found")
            Log.debug("IMPORT ABORT: file does not exist")
            return
        }
        
        var tempDirToClean: URL? = nil
        defer {
            if let dir = tempDirToClean {
                try? fm.removeItem(at: dir)
            }
        }
        
        let finalContentURL: URL
        isImporting = true
        if isDir.boolValue {
            finalContentURL = contentURL
            await showToast("Opening folder…")
        } else {
            let ext = contentURL.pathExtension.lowercased()
            if ["tar", "gz", "tgz"].contains(ext) {
                await showToast("Decompressing archive…")
                
                // Create temp dir
                let tempDir = AppStorageContext.current.temporaryDirectory.appendingPathComponent("GenStationImport_\(UUID().uuidString)")
                do {
                    try tempDir.createDirectoryWithStandardPermissions()
                    tempDirToClean = tempDir
                } catch {
                    isImporting = false
                    await showToast("Failed to create temp directory: \(error.localizedDescription)")
                    return
                }

                #if os(macOS)
                if extractTarGzNative(from: contentURL, to: tempDir) {
                    Log.debug("🟢 Native extraction complete")
                } else {
                    Log.debug("⚠️ Native extract failed, falling back to SWCompression")
                    if !(await extractWithSWCompression(from: contentURL, to: tempDir, ext: ext)) {
                        isImporting = false
                        await showToast("Extraction failed")
                        return
                    }
                }
                #else
                if !(await extractWithSWCompression(from: contentURL, to: tempDir, ext: ext)) {
                    isImporting = false
                    await showToast("Extraction failed")
                    return
                }
                #endif
                
                // ----- Auto-detect wrapper folder -----
                var effectiveURL = tempDir
                do {
                    let allItems = try fm.contentsOfDirectory(atPath: tempDir.path)
                    let visibleItems = allItems.filter { !$0.hasPrefix(".") && $0 != "__MACOSX" && !$0.hasPrefix("._") }
                    if visibleItems.count == 1,
                       let singleName = visibleItems.first {
                        let singleURL = tempDir.appendingPathComponent(singleName)
                        var isDirObj: ObjCBool = false
                        if fm.fileExists(atPath: singleURL.path, isDirectory: &isDirObj), isDirObj.boolValue {
                            effectiveURL = singleURL
                            Log.debug("🟢 Detected wrapper folder → using inner: \(effectiveURL.path)")
                        }
                    }
                } catch {
                    Log.debug("Wrapper detection warning: \(error)")
                }
                
                finalContentURL = effectiveURL
                Log.debug("🟢 Extraction complete → \(finalContentURL.path)")
                await showToast("Package extracted, importing…")
            }
            else if ext == "zip" {
                // Create temp dir
                let tempDir = AppStorageContext.current.temporaryDirectory.appendingPathComponent("GenStationImport_\(UUID().uuidString)")
                do {
                    try tempDir.createDirectoryWithStandardPermissions()
                    tempDirToClean = tempDir
                } catch {
                    isImporting = false
                    await showToast("Failed to create temp directory: \(error.localizedDescription)")
                    return
                }

                // Read archive
                let archiveData: Data
                do {
                    archiveData = try Data(contentsOf: contentURL)
                    Log.debug("🟢 Read archive data: \(archiveData.count) bytes")
                } catch {
                    isImporting = false
                    await showToast("Failed to read archive: \(error.localizedDescription)")
                    return
                }

                // Extract zip
                let zipEntries: [ZipEntry]
                do {
                    await showToast("Parsing zip archive…")
                    zipEntries = try ZipContainer.open(container: archiveData)
                } catch {
                    isImporting = false
                    await showToast("Zip extraction failed: \(error.localizedDescription)")
                    return
                }

                let zipMediaCount = zipEntries.filter {
                    $0.info.type != .directory &&
                    ($0.data?.isEmpty == false) &&
                    !$0.info.name.contains("__MACOSX") &&
                    !$0.info.name.components(separatedBy: "/").contains(where: { $0.hasPrefix("._") })
                }.count
                var zipExtracted = 0
                await showToast("Extracting 0/\(zipMediaCount) files…")

                for entry in zipEntries {
                    // ----- Junk filtering -----
                    var name = entry.info.name
                    if name.hasPrefix("./") { name.removeFirst(2) }
                    if name.hasSuffix("/") { name.removeLast() }
                    if name.isEmpty { continue }

                    let pathComponents = name.components(separatedBy: "/")
                    if pathComponents.contains("__MACOSX") ||
                        pathComponents.contains(where: { $0.hasPrefix("._") }) {
                        Log.debug("   Skipped junk: \(entry.info.name)")
                        continue
                    }

                    // ----- Build entry URL (handles deep paths) -----
                    let entryPath = tempDir.appending(relativePath: name)

                    // Ensure parent directories exist
                    let parentDir = entryPath.deletingLastPathComponent()
                    do {
                        try parentDir.createDirectoryWithStandardPermissions()
                    } catch {
                        Log.debug("   Failed to create parent dir for \(name): \(error)")
                        continue
                    }

                    // Create dir or write file
                    if entry.info.type == .directory {
                        do {
                            try fm.createDirectory(at: entryPath, withIntermediateDirectories: false)
                            Log.debug("   Created dir: \(name)/")
                        } catch {
                            Log.debug("   Failed to create dir \(name): \(error)")
                        }
                    } else if let data = entry.data, !data.isEmpty {
                        do {
                            try entryPath.writeWithStandardPermissions(data,
                                isDirectory: entry.info.type == .directory)
                            zipExtracted += 1
                            let pct = Int(Double(zipExtracted) / Double(max(zipMediaCount, 1)) * 100)
                            await showToast("Extracting... \(pct)% (\(zipExtracted)/\(zipMediaCount))")
                            Log.debug("   Extracted file: \(name) (\(data.count) bytes)")
                        } catch {
                            Log.debug("   Failed to write \(name): \(error)")
                        }
                    } else {
                        Log.debug("   Skipped unsupported/empty: \(name) (\(entry.info.type))")
                    }
                }
                
                // ----- Auto-detect wrapper folder -----
                var effectiveURL = tempDir
                do {
                    let allItems = try fm.contentsOfDirectory(atPath: tempDir.path)
                    let visibleItems = allItems.filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
                    if visibleItems.count == 1,
                        let singleName = visibleItems.first {
                        let singleURL = tempDir.appendingPathComponent(singleName)
                        var isDirObj: ObjCBool = false
                        if fm.fileExists(atPath: singleURL.path, isDirectory: &isDirObj), isDirObj.boolValue {
                            effectiveURL = singleURL
                            Log.debug("🟢 Detected wrapper folder → using inner: \(effectiveURL.path)")
                        }
                    }
                } catch {
                    Log.debug("Wrapper detection warning: \(error)")
                }
                
                finalContentURL = effectiveURL
                Log.debug("🟢 Extraction complete → \(finalContentURL.path)")
                await showToast("Package extracted, importing…")
            } else {
                isImporting = false
                await showToast("Unsupported format – please extract first and select the folder")
                return
            }
        }
        
        // Security-scoped access
        var packageAccess = false
        #if os(macOS)
        packageAccess = finalContentURL.startAccessingSecurityScopedResource()
        defer { if packageAccess { finalContentURL.stopAccessingSecurityScopedResource() } }
        #endif
        
        guard let jsonURL = findHistoryJSON(in: finalContentURL) else {
            isImporting = false
            await showToast("No history.json found – not a valid GenStation package")
            return
        }
        await showToast("Reading history…")
        let packageRoot = jsonURL.deletingLastPathComponent()
        
        do {
            await showToast("Reading history…")
            let data = try Data(contentsOf: jsonURL)
            let container = try JSONDecoder().decode(ExportContainer.self, from: data)
            
            // Use configured output directory, or fall back to Downloads
            let outputDir: URL
            let usingFallback: Bool
            if let configuredDir = appState.settings.outputDirectory {
                outputDir = configuredDir
                usingFallback = false
            } else if let downloadsDir = AppStorageContext.fallbackOutputDirectory {
                outputDir = downloadsDir
                usingFallback = true
            } else {
                isImporting = false
                await showToast("No output directory available")
                return
            }

            let outputAccess = usingFallback ? false : outputDir.startAccessingSecurityScopedResource()
            defer { if outputAccess { outputDir.stopAccessingSecurityScopedResource() } }
            
            var importedEntries = try container.toHistoryEntries()
            
            // Dedup internals first (so skipped only counts matches against existing history)
            var internalSignatures = Set<ItemSignature>()
            var internalSkipped = 0  // Optional: for debug/logging only, not used in toast

            func dedupInternals(_ entry: HistoryEntry) -> HistoryEntry? {
                switch entry {
                case .item(let item):
                    let sig = ItemSignature(from: item)
                    if internalSignatures.contains(sig) {
                        internalSkipped += 1
                        return nil
                    }
                    internalSignatures.insert(sig)
                    return entry
                case .folder(var folder):
                    folder.children = folder.children.compactMap { dedupInternals($0) }
                    return .folder(folder)
                }
            }

            importedEntries = importedEntries.compactMap { dedupInternals($0) }

            // Optional: Log internals for debug
            if internalSkipped > 0 {
                Log.debug("Ignored \(internalSkipped) internal duplicates in package")
            }
            
            // 1. Build set of existing item signatures
            var existingSignatures = Set<ItemSignature>()
            func collect(from entries: [HistoryEntry]) {
                for entry in entries {
                    if case .item(let item) = entry {
                        existingSignatures.insert(ItemSignature(from: item))
                    } else if case .folder(let folder) = entry {
                        collect(from: folder.children)
                    }
                }
            }
            collect(from: appState.historyState.history)
            
            // Move oldHistory capture BEFORE modifications
            let oldHistory = appState.historyState.history
            
            // 2. Merge/import with deduplication and path fixing
            var skipped = 0
            var added = 0
            
            func mergeOrInsert(_ newEntry: inout HistoryEntry, into existingEntries: inout [HistoryEntry], existingSignatures: inout Set<ItemSignature>, skipped: inout Int, added: inout Int) {
                switch newEntry {
                case .item(var newItem):
                    let sig = ItemSignature(from: newItem)
                    if existingSignatures.contains(sig) {
                        skipped += 1
                        return
                    }
                    existingSignatures.insert(sig)
                    
                    newItem.id = UUID()
                    
                    // Fix path: copy image
                    if let oldPath = newItem.imagePath {
                        let filename = URL(fileURLWithPath: oldPath).lastPathComponent
                        let sourceURL = packageRoot.appendingPathComponent(filename)
                        if fm.fileExists(atPath: sourceURL.path),
                           let imageData = try? Data(contentsOf: sourceURL),
                           !imageData.isEmpty {
                            let ext = sourceURL.pathExtension.lowercased()
                            let newName = "imported_\(UUID().uuidString).\(ext.isEmpty ? "jpg" : ext)"
                            let destURL = outputDir.appendingPathComponent(newName)
                            do {
                                try imageData.write(to: destURL, options: .atomic)
                                newItem.imagePath = destURL.path
                            } catch {
                                newItem.imagePath = nil
                                skipped += 1
                                return
                            }
                        } else {
                            newItem.imagePath = nil
                            skipped += 1
                            return
                        }
                    }
                    
                    newEntry = .item(newItem)
                    existingEntries.insert(newEntry, at: 0)
                    added += 1
                    
                case .folder(var newFolder):
                    newFolder.id = UUID()
                    
                    // Look for existing folder with same name at this level
                    if let idx = existingEntries.firstIndex(where: {
                        if case .folder(let f) = $0 { return f.name == newFolder.name }
                        return false
                    }), case .folder(var existingFolder) = existingEntries[idx] {
                        
                        // Merge children recursively into existing
                        for var child in newFolder.children {
                            mergeOrInsert(&child, into: &existingFolder.children, existingSignatures: &existingSignatures, skipped: &skipped, added: &added)
                        }
                        
                        existingEntries[idx] = .folder(existingFolder)
                        
                    } else {
                        // No match, insert new, but process children
                        var cleanedChildren: [HistoryEntry] = []
                        for var child in newFolder.children {
                            mergeOrInsert(&child, into: &cleanedChildren, existingSignatures: &existingSignatures, skipped: &skipped, added: &added)
                        }
                        newFolder.children = cleanedChildren
                        newEntry = .folder(newFolder)
                        existingEntries.insert(newEntry, at: 0)
                    }
                }
            }
            
            await showToast("Merging \(importedEntries.count) entries into history…")
            var targetHistory = appState.historyState.history
            let totalEntries = importedEntries.count
            for (i, var entry) in importedEntries.enumerated() {
                mergeOrInsert(&entry, into: &targetHistory, existingSignatures: &existingSignatures, skipped: &skipped, added: &added)
                if totalEntries > 10 && (i + 1) % 5 == 0 {
                    let pct = Int(Double(i + 1) / Double(totalEntries) * 100)
                    await showToast("Importing... \(pct)% (\(i + 1)/\(totalEntries))")
                }
            }

            appState.historyState.history = targetHistory
            appState.historyState.saveHistory()

            // 3. Feedback toast
            isImporting = false
            var msg = "Imported \(added) new entr\(added == 1 ? "y" : "ies")"
            if skipped > 0 { msg += " – skipped \(skipped) duplicate\(skipped == 1 ? "" : "s")" }
            toastMessage = msg

            // Undo support
            if let undoManager = undoManager {
                let wrapper = UndoManagerWrapper(manager: undoManager)
                wrapper.manager.registerUndo(withTarget: appState.historyState) { target in
                    let historyBeforeUndo = target.history
                    target.history = oldHistory
                    target.objectWillChange.send()
                    target.saveHistory()
                    wrapper.manager.registerUndo(withTarget: target) { redoTarget in
                        redoTarget.history = historyBeforeUndo
                        redoTarget.objectWillChange.send()
                        redoTarget.saveHistory()
                    }
                }
                wrapper.manager.setActionName("Import Package")
                toastAction = { undoManager.undo() }
            } else {
                toastAction = nil
            }
            showToast = true
            hideToastAfterDelay()
        } catch {
            isImporting = false
            await showToast("Import failed: \(error.localizedDescription)")
        }
    }
 
    
    private func fixImagePaths(in entries: inout [HistoryEntry], packageRoot: URL, outputDir: URL, success: inout Int, fail: inout Int) {
        let fm = FileManager.default
        for i in 0..<entries.count {
            switch entries[i] {
            case .item(var item):
                if let oldPath = item.imagePath {
                    let filename = URL(fileURLWithPath: oldPath).lastPathComponent
                    
                    var sourceImageURL = packageRoot.appendingPathComponent(filename)
                    
                    Log.debug("\n Attempting to find image: \(filename)")
                    Log.debug("   Primary location: \(sourceImageURL.path)")
                    
                    if !fm.fileExists(atPath: sourceImageURL.path) {
                        Log.debug("   Not found in root – searching entire package…")
                        
                        if let enumerator = fm.enumerator(at: packageRoot, includingPropertiesForKeys: nil) {
                            for case let candidateURL as URL in enumerator {
                                if candidateURL.lastPathComponent == filename {
                                    sourceImageURL = candidateURL
                                    Log.debug("   FOUND via search: \(sourceImageURL.path)")
                                    break
                                }
                            }
                        }
                    }
                    
                    if fm.fileExists(atPath: sourceImageURL.path),
                       let imageData = try? Data(contentsOf: sourceImageURL),
                       !imageData.isEmpty {
                        
                        Log.debug("   Successfully read \(imageData.count) bytes")
                        
                        let ext = sourceImageURL.pathExtension.lowercased()
                        let newName = "imported_\(UUID().uuidString).\(ext.isEmpty ? "jpg" : ext)"
                        let destURL = outputDir.appendingPathComponent(newName)
                        
                        do {
                            try imageData.write(to: destURL, options: .atomic)
                            item.imagePath = destURL.path
                            Log.debug("   Copied to output folder as \(destURL.lastPathComponent)")
                            success += 1
                        } catch {
                            Log.debug("   Failed to write to output folder: \(error)")
                            item.imagePath = nil
                            fail += 1
                        }
                    } else {
                        Log.debug("   Could not read image data (missing/corrupt/empty)")
                        item.imagePath = nil
                        fail += 1
                    }
                }
                entries[i] = .item(item)
            case .folder(var folder):
                fixImagePaths(in: &folder.children, packageRoot: packageRoot, outputDir: outputDir, success: &success, fail: &fail)
                entries[i] = .folder(folder)
            }
        }
    }
 
    private func findHistoryJSON(in folderURL: URL) -> URL? {
        let fm = FileManager.default
        // Direct history.json in the root
        let directURL = folderURL.appendingPathComponent("history.json")
        if fm.fileExists(atPath: directURL.path) {
            return directURL
        }
        
        // Search one level deep (handles extracted folders and some zip quirks)
        guard let contents = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return nil
        }
        
        for item in contents {
            if item.lastPathComponent == "history.json" {
                return item
            }
            // If there's a subfolder, check inside it too (e.g., "__MACOSX" or random wrapper folder)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: item.path, isDirectory: &isDir) && isDir.boolValue {
                let nested = item.appendingPathComponent("history.json")
                if fm.fileExists(atPath: nested.path) {
                    return nested
                }
            }
        }
        
        return nil
    }
 
    @MainActor
    private func showToast(_ message: String) {
        toastMessage = message
        toastAction = nil
        showToast = true
        hideToastAfterDelay()
    }
    
 
 
    private func showToast(_ message: String) async {
        await MainActor.run {
            toastMessage = message
            toastAction = nil
            showToast = true
            hideToastAfterDelay()
        }
    }
    
    
    
    private var historyList: some View {
        let shareEntryProvider: (HistoryEntry) async -> Void = { entry in
            await self.triggerShare(for: entry)
        }
 
        let entryRowProvider: (HistoryEntry) -> AnyView = { entry in
            AnyView(self.entryRow(for: entry))
        }
 
        let copyPromptProvider: (String) -> Void = { prompt in
            self.copyPromptToClipboard(prompt)
            self.toastMessage = "Prompt copied to clipboard"
            self.showToast = true
            self.hideToastAfterDelay()
        }
 
        let addToInputProvider: (HistoryItem) -> Void = { item in
            self.addToInputImages(item: item)
        }
 
        let shareFolderProvider: (Folder) async -> Void = { folder in
            await self.shareSingleFolder(folder)
        }
 
        return AnyView(
            Group {
#if os(iOS)
                List {
                    if filteredHistory.isEmpty {
                        Text("No history yet.")
                            .foregroundColor(.secondary)
                            .help("No generation history available yet")
                            .padding()
                    } else {
                    ForEach(filteredHistory) { entry in
                        TreeNodeView(
                            entry: entry,
                            appState: appState,
                            selectedIDs: $appState.historyState.multiSelection,
                            searchText: $searchText,
                            activeEntry: $activeEntry,
                            entryRowProvider: entryRowProvider,
                            copyPromptProvider: copyPromptProvider,
                            folderId: nil,
                            isEditing: isEditingBinding,
                            toastMessage: $toastMessage,
                            showToast: $showToast,
                            toastAction: $toastAction,
                            addToInputProvider: addToInputProvider,
                            undoManager: undoManager,
                            sharingInProgress: $sharingInProgress,
                            shareFolderProvider: shareFolderProvider,
                            shareEntryProvider: shareEntryProvider,
                            folderToRename: $folderToRename,
                            proposedFolderName: $proposedFolderName,
                            getMoveDestinations: getMoveDestinations,
                            visibleItemCountProvider: { self.visibleSelectedItemCount() },
                            shareSelectedIfPossible: shareSelectedIfPossible
                        )
                    }
                }
                }
                .environment(\.editMode, Binding(
                    get: { isEditing ? .active : .inactive },
                    set: { isEditing = ($0 == .active) }
                ))
                .onChange(of: appState.historyState.history) { _ in
                    Log.debug("History @Published changed")
                }
#else
                
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        if filteredHistory.isEmpty {
                            Text("No history yet.")
                                .foregroundColor(.secondary)
                                .help("No generation history available yet")
                                .padding()
                        } else {
                            ForEach(filteredHistory) { entry in
                                TreeNodeView(
                                    entry: entry,
                                    appState: appState,
                                    selectedIDs: $appState.historyState.multiSelection,
                                    searchText: $searchText,
                                    activeEntry: $activeEntry,
                                    entryRowProvider: entryRowProvider,
                                    copyPromptProvider: copyPromptProvider,
                                    folderId: nil,
                                    isEditing: isEditingBinding,
                                    toastMessage: $toastMessage,
                                    showToast: $showToast,
                                    toastAction: $toastAction,
                                    addToInputProvider: addToInputProvider,
                                    undoManager: undoManager,
                                    sharingInProgress: $sharingInProgress,
                                    shareFolderProvider: shareFolderProvider,
                                    shareEntryProvider: shareEntryProvider,
                                    folderToRename: $folderToRename,
                                    proposedFolderName: $proposedFolderName,
                                    getMoveDestinations: getMoveDestinations,
                                    visibleItemCountProvider: { self.visibleSelectedItemCount() },
                                    saveSelectedHistoryItemsToFolder: {
                                        await saveSelectedHistoryItemsToFolder()
                                    },
                                    shareSelectedIfPossible: shareSelectedIfPossible
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
#endif
            }
        )
        
    }
    
    private var isEditingBinding: Binding<Bool> {
        $isEditing
    }
    
    private var selectedFolders: [Folder] {
        appState.historyState.findEntries(with: appState.historyState.multiSelection)
            .compactMap { entry in
                if case .folder(let folder) = entry {
                    return folder
                }
                return nil
            }
    }
    
    private func parentFolders(for ids: Set<UUID>) -> Set<UUID?> {
        var parents = Set<UUID?>()
        for id in ids {
            parents.insert(appState.historyState.findParentFolderId(for: id, in: appState.historyState.history))
        }
        return parents
    }
    
    private func getMoveDestinations(for ids: Set<UUID>) -> (showHome: Bool, folders: [HistoryState.FolderOption]) {
        let parents = parentFolders(for: ids)
        let hasCommonParent = parents.count == 1
        let commonParentId = hasCommonParent ? parents.first : nil
        let showHome = !hasCommonParent || commonParentId != nil
        let folders = (hasCommonParent && commonParentId != nil) ? appState.historyState.allFolders().filter { $0.id != commonParentId } : appState.historyState.allFolders()
        return (showHome, folders)
    }
 
    @ViewBuilder
    private func entryRow(for entry: HistoryEntry) -> some View {
        switch entry {
        case .item(let item):
            itemRow(for: item)
        case .folder(let folder):
            HStack {
                if isEditingBinding.wrappedValue {
                    Image(systemName: appState.historyState.isEffectivelySelected(for: folder.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                }
                Image(systemName: "folder.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.gray)
                    .help("Folder icon")
                Text(folder.name)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isEditingBinding.wrappedValue {
                    var allDescendantIDs = Set<UUID>()
                    entry.collectAllIDs(into: &allDescendantIDs)
                    if appState.historyState.multiSelection.contains(folder.id) {
                        appState.historyState.multiSelection.subtract(allDescendantIDs)
                    } else {
                        appState.historyState.multiSelection.subtract(allDescendantIDs)
                        appState.historyState.multiSelection.insert(folder.id)
                    }
                }
            }
        }
    }
 
    private func loadSubmission(item: HistoryItem) {
        guard item.mode == .aimlapi else {
            toastMessage = "Load submission only available for AI/ML API mode"
            showToast = true
            hideToastAfterDelay()
            return
        }

        // Set prompt
        appState.prompt = item.prompt

        // Determine model ID from item.modelUsed or parse from payload
        var modelId: String?
        var json: [String: Any] = [:]
        if let payload = item.customAIMLPayload,
           let data = payload.data(using: .utf8),
           let parsedJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = parsedJson
            modelId = json["model"] as? String
        }
        // Not an `else if`: a payload that parses but carries no "model" key still has a known
        // model, because `modelUsed` is written on every AI/ML submission. The else-if made that
        // fallback unreachable, so such an item aborted at the "No model specified" toast below.
        if modelId == nil, let usedModel = item.modelUsed {
            modelId = usedModel
        }

        let canonicalId: String
        if let rawModelId = modelId {
            // history_v2.json is never rewritten (design § 4.3, Stage 4 owns that surface), so the
            // stored id is canonicalized here, on read, through the same alias index everything
            // else uses. An id the catalog does not know passes through unchanged.
            canonicalId = Catalog.canonicalID(for: rawModelId) ?? rawModelId
            appState.settings.selectedAIMLModel = canonicalId
        } else {
            toastMessage = "No model specified in submission data"
            showToast = true
            hideToastAfterDelay()
            return
        }

        // `resolve`, not `model(for:)`. Re-run is the one path where an id may legitimately be
        // unknown to the current catalog: § 4.4 deletes ids the live API no longer serves, and every
        // one of those is already stored in history under `modelUsed`. An unknown id synthesizes an
        // empty table, decodes to plain defaults, and the sheet still opens — which is what the two
        // deleted "Model not found in registry" toasts here used to guard. That guard was not merely
        // empirically unused, it was PROVABLY unreachable: by the time this method reaches either of
        // those old guard points, `rawModelId` is guaranteed non-empty (the function already returned
        // early at the "No model specified" toast above otherwise), and the old `enhancedModelFor`
        // returned nil only for a nil or empty id. Deleting the toasts removed zero real coverage.
        // What replaced that guard as the live risk is alias drift — a spelling a real user's on-disk
        // history used no longer indexing to its row — which Task 19 owns closing, not this method.
        let model = Catalog.resolve(canonicalId)
        let descriptors = ParamCatalog.descriptors(for: model)

        // If no payload, reconstruct default JSON for parsing
        if item.customAIMLPayload == nil {
            var bodyDict: [String: Any] = [
                "model": canonicalId,
                "prompt": "[prompt]"
            ]
            let defaultParams = ModelParameters() // Defaults will be applied by the decode below
            bodyDict.merge(ParamEncoder.encode(descriptors,
                                               params: defaultParams,
                                               context: ParamCatalog.context(for: model, hasInputImages: false))) { (_, new) in new }
            json = bodyDict
        }

        // Reconstruct the parameters from the stored payload using the model's descriptors, which
        // supply each row's own default for a key the payload does not carry. This is the only path
        // that can replay a past generation — history stores the submitted payload and no params —
        // so `HistoryReRunTests` pins it against every payload shape in the live history file.
        var newParams = ModelParameters()
        ParamDecoder.decode(descriptors, from: json, into: &newParams)

        // Set advanced params to populate UI, endpoint, and clear payload asynchronously to handle potential resets on model change
        DispatchQueue.main.async {
            appState.settings.customAIMLPayload = nil
            appState.settings.aimlAdvancedParams = newParams
            appState.presentedModal = .advancedSettings
        }
        toastMessage = "Submission loaded"
        showToast = true
        hideToastAfterDelay()
    }
    
    
    private func itemRow(for item: HistoryItem) -> some View {
        let exists = item.fileExists(appState: appState)
        var creator: String? = nil
        if let mode = item.mode {
            creator = mode == .gemini
                ? (item.modelUsed ?? appState.settings.selectedGeminiModel)  // best of both worlds
                : mode == .grok
                    ? (item.modelUsed ?? appState.settings.selectedGrokModel)
                    : mode == .aimlapi
                        ? (item.modelUsed ?? appState.settings.selectedAIMLModel)
                        : (item.workflowName ?? "ComfyUI")
 
            if let idx = item.indexInBatch, let tot = item.totalInBatch {
                creator! += " #\(idx + 1) of \(tot)"
            }
        }
 
        return HStack(spacing: 12) {
            if isEditingBinding.wrappedValue {
                Image(systemName: appState.historyState.isEffectivelySelected(for: item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(.gray)
                    .font(.system(size: 20))
            }
            ZStack {
                LazyThumbnailView(item: item)
                if item.imagePath?.hasSuffix(".mp4") ?? false {
                    Image(systemName: "film.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Circle())
                        .offset(x: 15, y: 15)
                        .help("Video content")
                        .accessibilityLabel("Video indicator")
                }
            }
            .frame(width: 50, height: 50)
 
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.prompt.prefix(50) + (item.prompt.count > 50 ? "..." : ""))
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundColor(exists ? .primary : .secondary)
                        .italic(exists ? false : true)
                        .help("Prompt: \(item.prompt)")
                        .accessibilityLabel("Prompt: \(item.prompt)")
                    if item.agentGenerated == true {
                        AgentBadge()
                    }
                }
                Text(dateFormatter.string(from: item.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("Date: \(dateFormatter.string(from: item.date))")
                if item.hasVideoContent {
                    HistoryCostLabel(item: item)
                }
                if let creator = creator {
                    Text(creator)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Generated with: \(creator)")
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditingBinding.wrappedValue {
                // If parent is selected, deselect parent and select this item
                if let parentID = appState.historyState.findParentFolderId(for: item.id, in: appState.historyState.history),
                   appState.historyState.multiSelection.contains(parentID) {
                    if let parentEntry = appState.historyState.findEntry(by: parentID) {
                        var parentDescendants = Set<UUID>()
                        parentEntry.collectAllIDs(into: &parentDescendants)
                        appState.historyState.multiSelection.subtract(parentDescendants)
                    }
                    appState.historyState.multiSelection.insert(item.id)
                } else if appState.historyState.multiSelection.contains(item.id) {
                    appState.historyState.multiSelection.remove(item.id)
                } else {
                    appState.historyState.multiSelection.insert(item.id)
                }
            } else {
                #if os(macOS)
                #if swift(>=5.7)
                openWindow(id: "history-viewer", value: item.id)
                #else
                fullHistoryItemId = item.id
                #endif
                #else
                appState.presentedModal = .fullHistoryItem(item.id)
                #endif
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            // Long press enters edit mode and selects this item
            if !isEditingBinding.wrappedValue {
                withAnimation(DS.Anim.standard) {
                    isEditingBinding.wrappedValue = true
                    appState.historyState.multiSelection.insert(item.id)
                }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
            }
        }
        #if os(iOS)
        .onDrag {
            Log.debug("DEBUG: Drag initiated for item \(item.id)")
            var payload: String
            var idsToDrag: [UUID]
            if isEditingBinding.wrappedValue && !appState.historyState.multiSelection.isEmpty {
                idsToDrag = Array(appState.historyState.multiSelection).sorted { $0.uuidString < $1.uuidString }
            } else {
                idsToDrag = [item.id]
            }
            payload = idsToDrag.map { $0.uuidString }.joined(separator: ",")
            return NSItemProvider(object: payload as NSString)
        }
        #endif
        .contextMenu {
            HistoryDraftActions(item: item)
            Group {
                if !isEditingBinding.wrappedValue {
                    // === NON-EDITING MODE ===
                    
                    Button("Copy Prompt") {
                        copyPromptToClipboard(item.prompt)
                        toastMessage = "Prompt copied to clipboard"
                        showToast = true
                        hideToastAfterDelay()
                    }
                    
                    if item.mode == .aimlapi, item.customAIMLPayload != nil || item.customAIMLEndpoint != nil {
                        Button("Load Submission") {
                            loadSubmission(item: item)
                        }
                    }
                    
                    Button("Add to Input") {
                        addToInputImages(item: item)
                    }
                    .disabled(!appState.canAddImages || appState.maxImageSlots == 0)

                    Button("Describe Image") {
                        toastMessage = "Analyzing image..."
                        showToast = true
                        hideToastAfterDelay()
                        Task {
                            await onDescribeImage?(item)
                        }
                    }
                    .disabled(onDescribeImage == nil || !item.fileExists(appState: appState) || item.imagePath?.hasSuffix(".mp4") == true)

                    if UpscaleService.isSupported() && !(item.imagePath?.hasSuffix(".mp4") == true) {
                        Button("Upscale 4x") {
                            guard !isUpscaling else { return }
                            isUpscaling = true
                            upscaleProgress = 0
                            toastMessage = "Upscaling 4x..."
                            showToast = true
                            Task {
                                do {
                                    _ = try await UpscaleService.upscaleHistoryItem(
                                        item,
                                        appState: appState,
                                        progressHandler: { progress in
                                            Task { @MainActor in
                                                upscaleProgress = progress
                                                toastMessage = "Upscaling... \(Int(progress * 100))%"
                                                showToast = true
                                            }
                                        }
                                    )
                                    isUpscaling = false
                                    toastMessage = "Upscaled image saved!"
                                    showToast = true
                                    hideToastAfterDelay()
                                } catch {
                                    isUpscaling = false
                                    toastMessage = error.localizedDescription
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                            }
                        }
                        .disabled(!item.fileExists(appState: appState) || isUpscaling)
                    }

                    Divider()

                    // Move to... menu
                    Menu("Move to...") {
                        let (showHome, folders) = getMoveDestinations(
                            for: isEditingBinding.wrappedValue ? appState.historyState.multiSelection : [item.id]
                        )
 
                        if showHome {
                            Button("Home") {
                                let idsToMove = isEditingBinding.wrappedValue ? Array(appState.historyState.multiSelection) : [item.id]
                                let success = appState.historyState.moveToFolder(
                                    entriesWithIds: idsToMove,
                                    toFolderId: nil,
                                    undoManager: undoManager
                                )
 
                                if success {
                                    appState.historyState.multiSelection.removeAll()
                                    toastMessage = "Moved item(s) to Home"
                                    toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
                                        undoManager?.undo()
                                    } : nil
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                            }
                        }
 
                        ForEach(folders) { folderOption in
                            Button(folderOption.name) {
                                let idsToMove = isEditingBinding.wrappedValue ? Array(appState.historyState.multiSelection) : [item.id]
                                let success = appState.historyState.moveToFolder(
                                    entriesWithIds: idsToMove,
                                    toFolderId: folderOption.id,
                                    undoManager: undoManager
                                )
 
                                if success {
                                    appState.historyState.multiSelection.removeAll()
                                    toastMessage = "Moved item(s) to \"\(folderOption.name)\""
                                    toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
                                        undoManager?.undo()
                                    } : nil
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                            }
                        }
                    }
                    .disabled(isEditingBinding.wrappedValue ? appState.historyState.multiSelection.isEmpty : false)
 
                    Button("Delete", role: .destructive) {
                        presentDeleteConfirmation(for: [.item(item)])
                    }
 
                    Divider()
                    
                    Button {
                        Task {
                            #if os(iOS)
                            // iOS: Save to Photos Library
                            let (success, total) = await PhotosLibraryHelper.saveToPhotosLibrary(
                                items: [item],
                                appState: appState
                            )
                            await MainActor.run {
                                if success == total && success > 0 {
                                    toastMessage = "Saved \(success) image\(success == 1 ? "" : "s") to Photos!"
                                } else if success == 0 {
                                    toastMessage = "Failed to save image"
                                } else {
                                    toastMessage = "Saved \(success)/\(total) to Photos"
                                }
                                showToast = true
                                hideToastAfterDelay()
                            }
                            
                            #elseif os(macOS)
                            // macOS: Save to folder using NSSavePanel
                            activeEntry = .item(item)  // Tell save function which item was tapped
                            await saveSelectedHistoryItemsToFolder()
                            #endif
                        }
                    } label: {
                        #if os(iOS)
                        Label("Save to Photos", systemImage: "photo.on.rectangle")
                        #elseif os(macOS)
                        Label("Export…", systemImage: "folder.badge.plus")
                        #endif
                    }
                    
                    Button {
                        Task { await shareSingleItem(item) }
                    } label: {
                        Label("AirDrop GenStation Package…", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .disabled(sharingInProgress)
 
                } else {
                    // === EDIT MODE: Show Select All / Deselect All ===
                    Divider()
 
                    Button("Select All") {
                                        appState.historyState.multiSelection.formUnion(allVisibleIDs())
                                    }
                                    .disabled({
                                        let visibleSet = allVisibleIDs()
                                        return appState.historyState.multiSelection.intersection(visibleSet).count == visibleSet.count
                                    }())
 
                    Button("Deselect All") {
                        appState.historyState.multiSelection.removeAll()
                    }
                    .disabled(appState.historyState.multiSelection.isEmpty)
                    Divider()
                    Button("Add to Input") {
                        // Gather all selected HistoryItems (including from inside folders)
                        let selectedEntries = appState.historyState.findEntries(with: appState.historyState.multiSelection)
                        let itemsToAdd = selectedEntries.flatMap { $0.allItems }
                        
                        guard !itemsToAdd.isEmpty else {
                            toastMessage = "No valid items to add"
                            showToast = true
                            hideToastAfterDelay()
                            return
                        }
                        
                        for item in itemsToAdd {
                            addToInputImages(item: item)
                        }
                    }
                    .disabled(!appState.canAddImages || appState.maxImageSlots == 0 || appState.historyState.multiSelection.isEmpty)
 
                    Divider()
                    
                    Menu("Move to...") {
                        let (showHome, folders) = getMoveDestinations(for: appState.historyState.multiSelection)
                        if showHome {
                            Button("Home") {
                                let success = appState.historyState.moveToFolder(
                                    entriesWithIds: Array(appState.historyState.multiSelection),
                                    toFolderId: nil,
                                    undoManager: undoManager
                                )
                                if success {
                                    appState.historyState.multiSelection.removeAll()
                                    toastMessage = "Moved item(s) to Home"
                                    toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
                                        undoManager?.undo()
                                    } : nil
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                            }
                        }
                        ForEach(folders) { folder in
                            Button(folder.name) {
                                let success = appState.historyState.moveToFolder(
                                    entriesWithIds: Array(appState.historyState.multiSelection),
                                    toFolderId: folder.id,
                                    undoManager: undoManager
                                )
                                if success {
                                    appState.historyState.multiSelection.removeAll()
                                    toastMessage = "Moved item(s) to \(folder.name)"
                                    toastAction = undoManager?.canUndo == true ? { [weak undoManager] in
                                        undoManager?.undo()
                                    } : nil
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                            }
                        }
                    }
                    .disabled(appState.historyState.multiSelection.isEmpty)
                    
                    Button("Delete Selected", role: .destructive) {
                        let entries = appState.historyState.findEntries(with: appState.historyState.multiSelection)
                        presentDeleteConfirmation(for: entries)
                    }
                    .disabled(appState.historyState.multiSelection.isEmpty)
                    
                    Divider()
                    Button {
                        Task {
                            #if os(iOS)
                            let selectedItems = appState.historyState.findEntries(with: appState.historyState.multiSelection)
                                .flatMap { $0.allItems }
                            
                            let (success, total) = await PhotosLibraryHelper.saveToPhotosLibrary(
                                items: selectedItems,
                                appState: appState
                            )
                            await MainActor.run {
                                if success == total && success > 0 {
                                    toastMessage = "Saved \(success) image\(success == 1 ? "" : "s") to Photos!"
                                } else if success == 0 {
                                    toastMessage = "No images were saved"
                                } else {
                                    toastMessage = "Saved \(success)/\(total) to Photos"
                                }
                                showToast = true
                                hideToastAfterDelay()
                            }
                            
                            #elseif os(macOS)
                            await saveSelectedHistoryItemsToFolder()
                            #endif
                        }
                    } label: {
                        #if os(iOS)
                        Label(saveSelectedToPhotosLabel, systemImage: "photo.on.rectangle")
                        #elseif os(macOS)
                        Label("Export Selected…", systemImage: "folder.badge.plus")
                        #endif
                    }
                    .disabled(isEditingBinding.wrappedValue ? appState.historyState.multiSelection.isEmpty : false)
 
                    Button {
                        shareSelectedIfPossible()
                    } label: {
                        Label("AirDrop GenStation Package", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .disabled(appState.historyState.multiSelection.isEmpty || sharingInProgress)
 
 
                }
            }
        }
    }
    
 
    private func copyPromptToClipboard(_ prompt: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = prompt
        #endif
    }
    
    private func fileExists(for item: HistoryItem) -> Bool {
        item.fileExists(appState: appState)
    }
    
    private func addToInputImages(item: HistoryItem) {
        guard appState.canAddImages, appState.maxImageSlots > 0 else {
            toastMessage = "Input images not supported in this mode."
            showToast = true
            hideToastAfterDelay()
            return
        }

        // Check if we're at max capacity
        let atMaxCapacity = appState.ui.imageSlots.count >= appState.maxImageSlots

        // Find first empty slot (no image loaded) if at max capacity
        let emptySlotIndex = atMaxCapacity ? appState.ui.imageSlots.firstIndex(where: { $0.path.isEmpty }) : nil

        // If at max capacity and no empty slots to replace, reject
        if atMaxCapacity && emptySlotIndex == nil {
            toastMessage = appState.maxImageSlots == 1
                ? "This model accepts one image. Remove the current input image before adding another."
                : "All \(appState.maxImageSlots) input slots are full. Remove an input image before adding another."
            appState.errorItem = AlertError(message: toastMessage ?? "Remove an input image before adding another.", fullMessage: nil)
            showToast = true
            hideToastAfterDelay()
            return
        }

        guard let path = item.imagePath else { return }
        let fileURL = URL(fileURLWithPath: path)

        Task {
            guard let fullImage = await LazyThumbnailView.loadFullImage(for: item, appState: appState) else {
                await MainActor.run {
                    toastMessage = "Failed to load image"
                    showToast = true
                    hideToastAfterDelay()
                }
                return
            }

            let thumbnail = fullImage.downscaled(toMaxPixels: 512)

            let tempURL = AppStorageContext.current.temporaryDirectory
                .appendingPathComponent("hist_\(UUID().uuidString).\(fileURL.pathExtension)")

            if let data = fullImage.pngData() {
                try? data.write(to: tempURL)
            }

            let newSlot = UIState.ImageSlot(
                thumbnail: thumbnail,
                fullResolutionURL: tempURL,
                originalData: fullImage.pngData()
            )

            await MainActor.run {
                // Recheck after asynchronous loading: another addition or a model switch may
                // have filled the slots while this image was being read.
                let currentEmpty = appState.ui.imageSlots.firstIndex(where: { $0.path.isEmpty })
                guard appState.canAddImages, appState.maxImageSlots > 0,
                      currentEmpty != nil || appState.ui.imageSlots.count < appState.maxImageSlots else {
                    try? FileManager.default.removeItem(at: tempURL)
                    toastMessage = appState.maxImageSlots == 1
                        ? "This model accepts one image. Remove the current input image before adding another."
                        : "Input slots are full. Remove an input image before adding another."
                    appState.errorItem = AlertError(message: toastMessage ?? "Remove an input image before adding another.", fullMessage: nil)
                    showToast = true
                    hideToastAfterDelay()
                    return
                }
                if let index = currentEmpty {
                    // Replace the empty slot
                    appState.ui.imageSlots[index] = newSlot
                    toastMessage = "Image replaced in input"
                } else {
                    // Add as new slot
                    appState.ui.imageSlots.append(newSlot)
                    toastMessage = "Item added to input"
                }
                showToast = true
                hideToastAfterDelay()
            }
        }
    }
 
    
    private func filterEntries(_ entries: [HistoryEntry], with search: String) -> [HistoryEntry] {
        entries.compactMap { entry in
            switch entry {
            case .item(let item):
                if item.prompt.lowercased().contains(search.lowercased()) ||
                    dateFormatter.string(from: item.date).lowercased().contains(search.lowercased()) {
                    return entry
                } else {
                    return nil
                }
            case .folder(let folder):
                let filteredChildren = filterEntries(folder.children, with: search)
                if !filteredChildren.isEmpty || folder.name.lowercased().contains(search.lowercased()) {
                    var newFolder = folder
                    newFolder.children = filteredChildren
                    return .folder(newFolder)
                } else {
                    return nil
                }
            }
        }
    }
    
    private func sortedEntries(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        var folders: [Folder] = []
        var items: [HistoryItem] = []
        for entry in entries {
            switch entry {
            case .folder(var folder):
                folder.children = sortedEntries(folder.children)
                folders.append(folder)
            case .item(let item):
                items.append(item)
            }
        }
        folders.sort { $0.name.lowercased() < $1.name.lowercased() }
        items.sort { $0.date > $1.date }
        return folders.map { .folder($0) } + items.map { .item($0) }
    }
    
#if os(macOS)
@MainActor
   private func saveSelectedHistoryItemsToFolder() async {
        // 1. Get the entries to process
        let selectedEntries: [HistoryEntry]
        if isEditingBinding.wrappedValue && !appState.historyState.multiSelection.isEmpty {
            selectedEntries = appState.historyState.findEntries(with: appState.historyState.multiSelection)
        } else if let active = activeEntry {
            selectedEntries = [active]
        } else {
            toastMessage = "No items selected"
            showToast = true
            hideToastAfterDelay()
            return
        }
 
        // Flatten to all descendant items (ignores folders, includes their contents)
        let items = selectedEntries.flatMap { $0.allItems }
 
        guard !items.isEmpty else {
            toastMessage = "No valid images to save"
            showToast = true
            hideToastAfterDelay()
            return
        }
 
        // 2. Resume security-scoped access to output directory (fall back to Downloads if not set)
        let outputDir: URL
        let usingFallback: Bool
        if let configuredDir = appState.settings.outputDirectory {
            outputDir = configuredDir
            usingFallback = false
        } else if let downloadsDir = AppStorageContext.fallbackOutputDirectory {
            outputDir = downloadsDir
            usingFallback = true
        } else {
            toastMessage = "No output directory available"
            showToast = true
            hideToastAfterDelay()
            return
        }
        let dirAccessStarted = usingFallback ? false : outputDir.startAccessingSecurityScopedResource()
        defer { if dirAccessStarted { outputDir.stopAccessingSecurityScopedResource() } }
 
        var successCount = 0
        var failedCount = 0
 
        if items.count == 1 {
            // SINGLE IMAGE: Use NSSavePanel for "Save As..."
            await saveSingleItem(items[0], outputDir: outputDir, success: &successCount, failed: &failedCount)
        } else {
            // MULTIPLE IMAGES: Use NSOpenPanel as folder picker
            await saveMultipleItems(items, outputDir: outputDir, success: &successCount, failed: &failedCount)
        }
 
        // 3. Show feedback toast
       if successCount + failedCount > 0 {
               let message: String
               if failedCount == 0 {
                   message = "Saved \(successCount) item\(successCount == 1 ? "" : "s") successfully!"
               } else if successCount == 0 {
                   message = "Failed to save any items"
               } else {
                   message = "Saved \(successCount)/\(items.count) items (\(failedCount) failed)"
               }
               toastMessage = message
               showToast = true
               hideToastAfterDelay()
           }
    }
 
// MARK: - Single Item Save (NSSavePanel)
    private func saveSingleItem(_ item: HistoryItem, outputDir: URL, success: inout Int, failed: inout Int) async {
        guard let srcPath = item.imagePath,
              item.fileExists(appState: appState) else {
            failed += 1
            return
        }
        
        let srcURL = URL(fileURLWithPath: srcPath)
        let filename = srcURL.lastPathComponent
        let isVideo = srcURL.pathExtension.lowercased() == "mp4"

        let savePanel = NSSavePanel()
        savePanel.title = isVideo ? "Save Video" : "Save Image"
        savePanel.prompt = "Save"
        savePanel.nameFieldStringValue = filename

        if isVideo {
            savePanel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        } else {
            savePanel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        }

        guard savePanel.runModal() == .OK, let destURL = savePanel.url else {
            return  // User cancelled
        }

        await showToast(isVideo ? "Saving video…" : "Saving image…")

        do {
            try FileManager.default.copyItem(at: srcURL, to: destURL)
            success += 1
            // Reveal in Finder
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destURL.deletingLastPathComponent().path)
        } catch {
            Log.debug("Failed to save \(filename): \(error)")
            failed += 1
        }
    }
 
    // MARK: - Multiple Items Save (NSOpenPanel as Folder Picker)
    private func saveMultipleItems(_ items: [HistoryItem], outputDir: URL, success: inout Int, failed: inout Int) async {
    let openPanel = NSOpenPanel()  // Use NSOpenPanel for folder selection
    openPanel.title = "Choose Folder to Save \(items.count) Items"
    openPanel.prompt = "Select"
    openPanel.canChooseFiles = false              // No files
    openPanel.canChooseDirectories = true         // Folders only
    openPanel.allowsMultipleSelection = false
    openPanel.allowedContentTypes = []              // Any type
    openPanel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    
    guard openPanel.runModal() == .OK, let destinationFolder = openPanel.url else {
        return  // User cancelled
    }
    
    await showToast("Saving \(items.count) items…")

    let fm = FileManager.default
    for item in items {
        guard let srcPath = item.imagePath,
              item.fileExists(appState: appState) else {
            failed += 1
            continue
        }

        let srcURL = URL(fileURLWithPath: srcPath)
        let filename = srcURL.lastPathComponent
        var destURL = destinationFolder.appendingPathComponent(filename)

        // Avoid collisions: append (1), (2), etc.
        var counter = 1
        while fm.fileExists(atPath: destURL.path) {
            let nameWithoutExt = destURL.deletingPathExtension().lastPathComponent
            let ext = destURL.pathExtension
            let newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
            destURL = destinationFolder.appendingPathComponent(newName)
            counter += 1
        }

        do {
            try fm.copyItem(at: srcURL, to: destURL)
            success += 1
        } catch {
            Log.debug("Failed to save \(filename): \(error)")
            failed += 1
        }
    }
    
    // Reveal the folder in Finder
    if success > 0 {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destinationFolder.path)
    }
}
#endif
    
    private func createTarGz(from directoryURL: URL, to tarGzURL: URL) -> Bool {
        let fm = FileManager.default
        var entries: [TarEntry] = []
        
        // Show toast immediately when compression starts
        Task { @MainActor in
            showToast("Creating export package…")
        }
        
        if let enumerator = fm.enumerator(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let fileURL as URL in enumerator {
                let relativePath = fileURL.relativePath(to: directoryURL)
                guard !relativePath.isEmpty else { continue }
                
                let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if let isDir = values?.isDirectory, isDir {
                    var dirPath = relativePath
                    if !dirPath.hasSuffix("/") { dirPath += "/" }
                    let info = TarEntryInfo(name: dirPath, type: .directory)
                    entries.append(TarEntry(info: info, data: nil))
                } else {
                    if let data = try? Data(contentsOf: fileURL) {
                        let info = TarEntryInfo(name: relativePath, type: .regular)
                        entries.append(TarEntry(info: info, data: data))
                    }
                }
            }
        }
        
        let tarData = TarContainer.create(from: entries)
        guard let gzData = try? GzipArchive.archive(data: tarData) else {
            Task { @MainActor in
                showToast("Failed to compress package")
            }
            Log.debug("Failed to gzip tar data")
            return false
        }
        
        do {
            try gzData.write(to: tarGzURL)
            Task { @MainActor in
                showToast("Export package ready!")
            }
            Log.debug("Created tar.gz at: \(tarGzURL.path) (\(gzData.count) bytes)")
            return true
        } catch {
            Task { @MainActor in
                showToast("Failed to save package")
            }
            Log.debug("Failed to write tar.gz: \(error)")
            return false
        }
    }
    
    private let mediaExtensions = ["jpg", "jpeg", "png", "webp", "heic", "gif", "mp4", "mov", "webm"]

    private func isMediaFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        let filename = name.components(separatedBy: "/").last ?? name  // Last component only
        return mediaExtensions.contains { filename.hasSuffix(".\($0)") } &&
               !filename.hasPrefix("._") &&
               !lower.contains("__macosx/") &&  // Handles paths like "folder/__MACOSX/..."
               !filename.hasSuffix(".json")
    }
    
    private func extractWithSWCompression(from archiveURL: URL, to destinationURL: URL, ext: String) async -> Bool {
        let fm = FileManager.default
        do {
            let archiveData = try Data(contentsOf: archiveURL)
            Log.debug("🟢 Read archive data: \(archiveData.count) bytes")
            
            var tarData = archiveData
            if ext == "gz" || ext == "tgz" {
                await showToast("Decompressing gzip…")
                tarData = try GzipArchive.unarchive(archive: archiveData)
                await showToast("Decompressed")
                Log.debug("🟢 Decompressed (\(archiveData.count) -> \(tarData.count) bytes)")
            }
            
            await showToast("Parsing tar archive…")
            let tarEntries = try TarContainer.open(container: tarData)
            let mediaCount = tarEntries.filter {
                $0.info.type == .regular &&
                ($0.data?.isEmpty == false) &&
                isMediaFile($0.info.name)
            }.count
            await showToast("Extracting 0/\(mediaCount) files…")

            var extracted = 0
            for entry in tarEntries {
                var name = entry.info.name
                if name.hasPrefix("./") { name.removeFirst(2) }
                if name.hasSuffix("/") { name.removeLast() }
                if name.isEmpty { continue }

                let pathComponents = name.components(separatedBy: "/")
                if pathComponents.contains("__MACOSX") ||
                    pathComponents.contains(where: { $0.hasPrefix("._") }) {
                    Log.debug("   Skipped junk: \(entry.info.name)")
                    continue
                }

                let entryPath = destinationURL.appending(relativePath: name)
                let parentDir = entryPath.deletingLastPathComponent()
                try parentDir.createDirectoryWithStandardPermissions()

                if entry.info.type == .directory {
                    try? fm.createDirectory(at: entryPath, withIntermediateDirectories: false)
                    Log.debug("   Created dir: \(name)/")
                } else if let data = entry.data, !data.isEmpty {
                    try entryPath.writeWithStandardPermissions(data)
                    if isMediaFile(name) {
                        extracted += 1
                        let pct = Int(Double(extracted) / Double(max(mediaCount, 1)) * 100)
                        await showToast("Extracting... \(pct)% (\(extracted)/\(mediaCount))")
                    }
                    Log.debug("   Extracted file: \(name) (\(data.count) bytes)")
                } else {
                    Log.debug("   Skipped unsupported/empty: \(name) (\(entry.info.type))")
                }
            }
            
            return true
        } catch {
            Log.debug("SWCompression extract failed: \(error)")
            return false
        }
    }
}
 
 
struct DeleteConfirmationView: View {
    let title: String
    let message: String
    let hasDeletableFiles: Bool
    let deleteAction: (Bool) -> Void
    let cancelAction: () -> Void
    
    @State private var deleteFiles: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        #if os(iOS)
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
    
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
    
                if hasDeletableFiles {
                    Toggle("Also delete file(s) permanently", isOn: $deleteFiles)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .accessibilityLabel("Toggle permanent file deletion")
                        .accessibilityHint("When enabled, deletes the associated file(s) permanently")
    
                    Text("File deletion cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                }
            }
    
            HStack(spacing: 8) {
                Button(action: {
                    cancelAction()
                    dismiss()
                }) {
                    Text("Cancel")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Cancel deletion")
    
                Button(action: {
                    deleteAction(deleteFiles)
                    dismiss()
                }) {
                    Text("Delete")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityLabel("Confirm deletion")
                .accessibilityHint(hasDeletableFiles && deleteFiles ? "Deletes the item and its file(s) permanently" : "Deletes the item from history")
            }
        }
        .frame (maxWidth: 320, maxHeight: 240)
        #elseif os(macOS)
        VStack(spacing: 20) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
    
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
    
                if hasDeletableFiles {
                    Toggle("Also delete file(s) permanently", isOn: $deleteFiles)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .accessibilityLabel("Toggle permanent file deletion")
                        .accessibilityHint("When enabled, deletes the associated file(s) permanently")
    
                    Text("File deletion cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                }
            }
    
            HStack(spacing: 8) {
                Button(action: {
                    cancelAction()
                    dismiss()
                }) {
                    Text("Cancel")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Cancel deletion")
    
                Button(action: {
                    deleteAction(deleteFiles)
                    dismiss()
                }) {
                    Text("Delete")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityLabel("Confirm deletion")
                .accessibilityHint(hasDeletableFiles && deleteFiles ? "Deletes the item and its file(s) permanently" : "Deletes the item from history")
            }
        }
        .padding(20)
        .frame(minWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        #endif
    }
}
private extension URL {
    func appending(relativePath: String) -> URL {
        var url = self
        let components = relativePath
            .components(separatedBy: "/")
            .filter { !$0.isEmpty && $0 != ".." && $0 != "." }
        for component in components {
            url = url.appendingPathComponent(component)
        }
        return url
    }
}
extension URL {
    func relativePath(to base: URL) -> String {
        let pathComponents = self.pathComponents
        let baseComponents = base.pathComponents
        let commonPrefixCount = zip(baseComponents, pathComponents).prefix(while: { $0 == $1 }).count
        return pathComponents[commonPrefixCount...].joined(separator: "/")
    }
    
    func setStandardPermissions(isDirectory: Bool = false) {
            let perms: mode_t = isDirectory ? 0o755 : 0o644
            let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: UInt16(perms))]  // Explicit UInt16 for mode_t
            do {
                try FileManager.default.setAttributes(attrs, ofItemAtPath: self.path)
            } catch {
                Log.debug("Warning: Could not set permissions on \(self.path): \(error)")
            }
        }
 
        func writeWithStandardPermissions(_ data: Data, isDirectory: Bool = false) throws {
            try data.write(to: self, options: .atomic)
            self.setStandardPermissions(isDirectory: isDirectory)
        }
 
        func createDirectoryWithStandardPermissions() throws {
            try FileManager.default.createDirectory(
                at: self,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o755)]
            )
        }
}
extension Int {
    func byteCountString() -> String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
extension HistoryItem {
    var suggestedFilename: String {
        guard let path = imagePath else {
            return "generated_image.jpg"
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
