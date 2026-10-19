//HistoryTreeNode.swift
import SwiftUI
import AVKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import GenStationCore

struct TreeNodeView: View {
    let entry: HistoryEntry
    let appState: AppState
    @Binding var selectedIDs: Set<UUID>
    @Binding var searchText: String
    @Binding var activeEntry: HistoryEntry?
    let entryRowProvider: (HistoryEntry) -> AnyView
    let copyPromptProvider: (String) -> Void
    let folderId: UUID?
    @Binding var isEditing: Bool
    @Binding var toastMessage: String?
    @Binding var showToast: Bool
    @Binding var toastAction: (() -> Void)?
    let addToInputProvider: (HistoryItem) -> Void
    let undoManager: UndoManager?
    @Binding var sharingInProgress: Bool
    let shareFolderProvider: (Folder) async -> Void
    let shareEntryProvider: (HistoryEntry) async -> Void
    @Binding var folderToRename: Folder?
    @Binding var proposedFolderName: String
    let getMoveDestinations: (Set<UUID>) -> (Bool, [HistoryState.FolderOption])
    private let visibleItemCountProvider: () -> Int
    #if os(macOS)
    let saveSelectedHistoryItemsToFolder: () async -> Void
    #endif
    let shareSelectedIfPossible: () -> Void
    
    private func isEffectivelySelected(for entryID: UUID) -> Bool {
        appState.historyState.isEffectivelySelected(for: entryID)
    }
    
    #if os (macOS)
    init(
        entry: HistoryEntry,
        appState: AppState,
        selectedIDs: Binding<Set<UUID>>,
        searchText: Binding<String>,
        activeEntry: Binding<HistoryEntry?>,
        entryRowProvider: @escaping (HistoryEntry) -> AnyView,
        copyPromptProvider: @escaping (String) -> Void,
        folderId: UUID? = nil,
        isEditing: Binding<Bool>,
        toastMessage: Binding<String?>,
        showToast: Binding<Bool>,
        toastAction: Binding<(() -> Void)?>,
        addToInputProvider: @escaping (HistoryItem) -> Void,
        undoManager: UndoManager?,
        sharingInProgress: Binding<Bool>,
        shareFolderProvider: @escaping (Folder) async -> Void,
        shareEntryProvider: @escaping (HistoryEntry) async -> Void,
        folderToRename: Binding<Folder?>,
        proposedFolderName: Binding<String>,
        getMoveDestinations: @escaping (Set<UUID>) -> (Bool, [HistoryState.FolderOption]),
        visibleItemCountProvider: @escaping () -> Int,
        saveSelectedHistoryItemsToFolder: @escaping () async -> Void,
        shareSelectedIfPossible: @escaping () -> Void


    ) {
        self.entry = entry
        self.appState = appState
        self._selectedIDs = selectedIDs
        self._searchText = searchText
        self._activeEntry = activeEntry
        self.entryRowProvider = entryRowProvider
        self.copyPromptProvider = copyPromptProvider
        self.folderId = folderId
        self._isEditing = isEditing
        self._toastMessage = toastMessage
        self._showToast = showToast
        self._toastAction = toastAction
        self.addToInputProvider = addToInputProvider
        self.undoManager = undoManager
        self._sharingInProgress = sharingInProgress
        self.shareFolderProvider = shareFolderProvider
        self.shareEntryProvider = shareEntryProvider
        self._folderToRename = folderToRename
        self._proposedFolderName = proposedFolderName
        self.getMoveDestinations = getMoveDestinations
        self.visibleItemCountProvider = visibleItemCountProvider
        self.saveSelectedHistoryItemsToFolder = saveSelectedHistoryItemsToFolder
        self.shareSelectedIfPossible = shareSelectedIfPossible
    }
    #else
    init(
        entry: HistoryEntry,
        appState: AppState,
        selectedIDs: Binding<Set<UUID>>,
        searchText: Binding<String>,
        activeEntry: Binding<HistoryEntry?>,
        entryRowProvider: @escaping (HistoryEntry) -> AnyView,
        copyPromptProvider: @escaping (String) -> Void,
        folderId: UUID? = nil,
        isEditing: Binding<Bool>,
        toastMessage: Binding<String?>,
        showToast: Binding<Bool>,
        toastAction: Binding<(() -> Void)?>,
        addToInputProvider: @escaping (HistoryItem) -> Void,
        undoManager: UndoManager?,
        sharingInProgress: Binding<Bool>,
        shareFolderProvider: @escaping (Folder) async -> Void,
        shareEntryProvider: @escaping (HistoryEntry) async -> Void,
        folderToRename: Binding<Folder?>,
        proposedFolderName: Binding<String>,
        getMoveDestinations: @escaping (Set<UUID>) -> (Bool, [HistoryState.FolderOption]),
        visibleItemCountProvider: @escaping () -> Int,
        shareSelectedIfPossible: @escaping () -> Void


    ) {
        self.entry = entry
        self.appState = appState
        self._selectedIDs = selectedIDs
        self._searchText = searchText
        self._activeEntry = activeEntry
        self.entryRowProvider = entryRowProvider
        self.copyPromptProvider = copyPromptProvider
        self.folderId = folderId
        self._isEditing = isEditing
        self._toastMessage = toastMessage
        self._showToast = showToast
        self._toastAction = toastAction
        self.addToInputProvider = addToInputProvider
        self.undoManager = undoManager
        self._sharingInProgress = sharingInProgress
        self.shareFolderProvider = shareFolderProvider
        self.shareEntryProvider = shareEntryProvider
        self._folderToRename = folderToRename
        self._proposedFolderName = proposedFolderName
        self.getMoveDestinations = getMoveDestinations
        self.visibleItemCountProvider = visibleItemCountProvider
        self.shareSelectedIfPossible = shareSelectedIfPossible
    }
    #endif
    
    
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
                toastMessage = itemCount > 0
                    ? (itemCount == 1 ? "Item deleted" : "\(itemCount) items deleted")
                    : (folderCount == 1 ? "Folder deleted" : "\(folderCount) folders deleted")
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
    
    var body: some View {
        if case .folder(let folder) = entry {
            DisclosureGroup(
                isExpanded: Binding<Bool>(
                    get: { appState.historyState.expandedFolderIDs.contains(folder.id) },
                    set: { newValue in
                        if newValue {
                            appState.historyState.expandedFolderIDs.insert(folder.id)
                        } else {
                            appState.historyState.expandedFolderIDs.remove(folder.id)
                        }
                    }
                )
            ) {
                // === Children only - no swipe actions here ===
                if searchText.isEmpty {
                    #if os(iOS)
                    ForEach(folder.children) { child in
                        TreeNodeView(
                            entry: child,
                            appState: appState,
                            selectedIDs: $selectedIDs,
                            searchText: $searchText,
                            activeEntry: $activeEntry,
                            entryRowProvider: entryRowProvider,
                            copyPromptProvider: copyPromptProvider,
                            folderId: folder.id,
                            isEditing: $isEditing,
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
                            visibleItemCountProvider: visibleItemCountProvider,
                            shareSelectedIfPossible: shareSelectedIfPossible
                        )
                    }
                    #else
                    ForEach(folder.children) { child in
                        TreeNodeView(
                            entry: child,
                            appState: appState,
                            selectedIDs: $selectedIDs,
                            searchText: $searchText,
                            activeEntry: $activeEntry,
                            entryRowProvider: entryRowProvider,
                            copyPromptProvider: copyPromptProvider,
                            folderId: folder.id,
                            isEditing: $isEditing,
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
                            visibleItemCountProvider: visibleItemCountProvider,
                            saveSelectedHistoryItemsToFolder: saveSelectedHistoryItemsToFolder,
                            shareSelectedIfPossible: shareSelectedIfPossible
                        )
                    }
                    .padding(.leading, 20)
                    #endif
                } else {
                    ForEach(folder.children) { child in
                        #if os (macOS)
                        TreeNodeView(
                            entry: child,
                            appState: appState,
                            selectedIDs: $selectedIDs,
                            searchText: $searchText,
                            activeEntry: $activeEntry,
                            entryRowProvider: entryRowProvider,
                            copyPromptProvider: copyPromptProvider,
                            folderId: folder.id,
                            isEditing: $isEditing,
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
                            visibleItemCountProvider: visibleItemCountProvider,
                            saveSelectedHistoryItemsToFolder: saveSelectedHistoryItemsToFolder,
                            shareSelectedIfPossible: shareSelectedIfPossible
                        )
                        #elseif os (iOS)
                        TreeNodeView(
                            entry: child,
                            appState: appState,
                            selectedIDs: $selectedIDs,
                            searchText: $searchText,
                            activeEntry: $activeEntry,
                            entryRowProvider: entryRowProvider,
                            copyPromptProvider: copyPromptProvider,
                            folderId: folder.id,
                            isEditing: $isEditing,
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
                            visibleItemCountProvider: visibleItemCountProvider,
                            shareSelectedIfPossible: shareSelectedIfPossible
                        )
                        #endif
                        
                    }
                    .padding(.leading, 20)
                }
            } label: {
                // === Folder row with swipe actions ===
                folderRowVisual(for: folder)
                #if os(iOS)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        Task { await shareFolderProvider(folder) }
                    } label: {
                        Label("AirDrop GenStation Package…", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tint(.green)
                    .disabled(sharingInProgress)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        presentDeleteConfirmation(for: [.folder(folder)])
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
                #endif
                .contextMenu {
                    if !isEditing {
                        // === Normal mode (not editing) ===
                        Button("Rename") {
                            folderToRename = folder
                            proposedFolderName = folder.name
                        }
                        
                        Button("Delete", role: .destructive) {
                            presentDeleteConfirmation(for: [.folder(folder)])
                        }
                        
                        Divider()

                        Button("Expand All Folders") {
                            appState.historyState.expandAllFolders()
                        }
                        .keyboardShortcut("]", modifiers: [.command, .shift]) // Optional

                        Button("Collapse All Folders") {
                            appState.historyState.collapseAllFolders()
                        }
                        .keyboardShortcut("[", modifiers: [.command, .shift]) // Optional
                        
                        Divider()
                        
                        // NEW: Save folder contents
                        #if os(macOS)
                        Button {
                            let items = folder.children.flatMap { $0.allItems }
                            guard !items.isEmpty else {
                                toastMessage = "No images in folder"
                                toastAction = nil
                                showToast = true
                                hideToastAfterDelay()
                                return
                            }
                            Task {
                                await saveSelectedHistoryItemsToFolder()
                            }
                        } label: {
                            Label("Export Selected…", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            Task { await shareFolderProvider(folder) }
                        } label: {
                            Label("AirDrop GenStation Package…", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .disabled(sharingInProgress)
                        #else // iOS
                        Button {
                            let items = folder.children.flatMap { $0.allItems }
                            guard !items.isEmpty else {
                                toastMessage = "No images in folder"
                                toastAction = nil
                                showToast = true
                                hideToastAfterDelay()
                                return
                            }
                            Task {
                                let (success, total) = await PhotosLibraryHelper.saveToPhotosLibrary(
                                    items: items,
                                    appState: appState
                                )
                                await MainActor.run {
                                    toastMessage = success == total && success > 0
                                        ? "Saved \(success) to Photos!"
                                        : "Saved \(success)/\(total) to Photos"
                                    toastAction = nil
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                            }
                        } label: {
                            Label("Save to Photos", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            Task { await shareFolderProvider(folder) }
                        } label: {
                            Label("AirDrop GenStation Package…", systemImage: "dot.radiowaves.left.and.right")
                        }
                        #endif
                        
                    } else {
                        // ─── Edit mode: Multi-select actions + folder-specific actions ───
                        Divider()

                        Button("Select All in Folder") {  // Clearer label
                            let lowerSearch = searchText.lowercased()
                            let dateFormatter = DateFormatter()  // Create once
                            dateFormatter.dateStyle = .short
                            dateFormatter.timeStyle = .short
                            
                            for entry in folder.children {
                                if case .item(let item) = entry {  // Only items (safe)
                                    let isMatch = lowerSearch.isEmpty ||
                                        item.prompt.lowercased().contains(lowerSearch) ||
                                        dateFormatter.string(from: item.date).lowercased().contains(lowerSearch)
                                    if isMatch {
                                        appState.historyState.multiSelection.insert(item.id)
                                    }
                                }
                            }
                        }
                        .disabled({
                            let lowerSearch = searchText.lowercased()
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateStyle = .short
                            dateFormatter.timeStyle = .short
                            
                            var visibleCount = 0
                            var selectedVisibleCount = 0
                            
                            for entry in folder.children {
                                if case .item(let item) = entry {
                                    let isMatch = lowerSearch.isEmpty ||
                                        item.prompt.lowercased().contains(lowerSearch) ||
                                        dateFormatter.string(from: item.date).lowercased().contains(lowerSearch)
                                    if isMatch {
                                        visibleCount += 1
                                        if appState.historyState.multiSelection.contains(item.id) {
                                            selectedVisibleCount += 1
                                        }
                                    }
                                }
                            }
                            return visibleCount == 0 || selectedVisibleCount == visibleCount
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
                                toastAction = nil
                                showToast = true
                                hideToastAfterDelay()
                                return
                            }

                            var addedCount = 0
                            for item in itemsToAdd {
                                guard appState.ui.imageSlots.count < appState.maxImageSlots else { break }
                                addToInputProvider(item)
                                addedCount += 1
                            }

                            if addedCount > 0 {
                                toastMessage = "Added \(addedCount) item\(addedCount == 1 ? "" : "s") to input"
                            } else {
                                toastMessage = "Input slots are full"
                            }

                            toastAction = nil
                            showToast = true
                            hideToastAfterDelay()
                        }
                        .disabled(!appState.canAddImages || appState.maxImageSlots == 0 || appState.historyState.multiSelection.isEmpty)

                        Divider()
                        
                        Menu("Move to...") {
                            let selectedIDs = appState.historyState.multiSelection
                            let (showHome, folders) = getMoveDestinations(selectedIDs)
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
                                    .compactMap { $0.asItem }
                                
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
                                    toastAction = nil
                                    showToast = true
                                    hideToastAfterDelay()
                                }
                                
                                #elseif os(macOS)
                                await saveSelectedHistoryItemsToFolder()
                                #endif
                            }
                        } label: {
                            #if os(iOS)
                            Label("Save Selected to Photos", systemImage: "photo.on.rectangle")
                            #elseif os(macOS)
                            Label("Export Selected…", systemImage: "folder.badge.plus")
                            #endif
                        }
                        .disabled(isEditing ? appState.historyState.multiSelection.isEmpty : false)

                        Button {
                            shareSelectedIfPossible()
                        } label: {
                            Label("AirDrop GenStation Package", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .disabled(appState.historyState.multiSelection.isEmpty || sharingInProgress)

                    }
                }
                
            }
        } else {
            // === Regular history item ===
            entryRowProvider(entry)
            #if os(iOS)
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                // Green Share first
                if case .item = entry {
                    Button {
                        Task { await shareEntryProvider(entry) }
                    } label: {
                        Label("AirDrop GenStation Package…", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .tint(.green)
                    .disabled(sharingInProgress)
                }
                // Blue Add to Input second
                if case .item(let historyItem) = entry {
                    Button {
                        addToInputProvider(historyItem)
                    } label: {
                        Label("Add to Input", systemImage: "plus.square.on.square")
                    }
                    .tint(.blue)
                }
            }
            .swipeActions(edge: .trailing) {
                if case .item(let historyItem) = entry {
                    Button(role: .destructive) {
                        presentDeleteConfirmation(for: [.item(historyItem)])
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
            #endif
        }
    }
    
    @ViewBuilder
    private func folderRowVisual(for folder: Folder) -> some View {
        HStack {
            if isEditing {
                Image(systemName: appState.historyState.isEffectivelySelected(for: folder.id) ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(.gray)
            }
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundColor(.secondary)
            Text(folder.name)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEditing else { return }

            // Collect ALL descendant IDs (folder itself + all nested items/folders)
            var allDescendantIDs = Set<UUID>()
            entry.collectAllIDs(into: &allDescendantIDs) // includes folder.id and all children

            if selectedIDs.contains(entry.id) {
                // Folder is currently selected → deselect it and ALL descendants
                selectedIDs.subtract(allDescendantIDs)
            } else {
                // Select folder, but FIRST remove any individually selected descendants
                // (prevents double-counting and keeps multiSelection clean)
                selectedIDs.subtract(allDescendantIDs)
                selectedIDs.insert(entry.id)
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if !isEditing {
                // Long press enters edit mode and selects this folder
                withAnimation(DS.Anim.standard) {
                    isEditing = true
                    selectedIDs.insert(entry.id)
                }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
            } else {
                // In edit mode, long press triggers rename
                proposedFolderName = folder.name
                folderToRename = folder
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
            }
        }
    }
    
    
    private func hideToastAfterDelay() {
        // Longer delay (5s) when toast has undo action, shorter (2s) for simple toasts
        let delay: TimeInterval = toastAction != nil ? 5.0 : 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.3)) {
                showToast = false
                toastAction = nil
            }
        }
    }
#if os(macOS)
    @MainActor
    private func saveItemsToFolder(_ items: [HistoryItem]) async {
        guard !items.isEmpty else { return }
        
        // Reuse your existing save logic from FullHistoryItemView
        guard let outputDir = appState.settings.outputDirectory else {
            toastMessage = "Output folder not configured"
            toastAction = nil
            showToast = true
            hideToastAfterDelay()
            return
        }
        let dirAccessStarted = outputDir.startAccessingSecurityScopedResource()
        defer { if dirAccessStarted { outputDir.stopAccessingSecurityScopedResource() } }

        var successCount = 0
        var failedCount = 0

        if items.count == 1 {
            await saveSingleItem(items[0], outputDir: outputDir, success: &successCount, failed: &failedCount)
        } else {
            await saveMultipleItems(items, outputDir: outputDir, success: &successCount, failed: &failedCount)
        }

        let message: String
        if failedCount == 0 {
            message = "Saved \(successCount) image\(successCount == 1 ? "" : "s")"
        } else if successCount == 0 {
            message = "Failed to save"
        } else {
            message = "Saved \(successCount)/\(items.count) images"
        }
        toastMessage = message
        toastAction = nil
        showToast = true
        hideToastAfterDelay()
    }
#endif
    #if os (macOS)
    private func saveSingleItem(_ item: HistoryItem, outputDir: URL, success: inout Int, failed: inout Int) async {
        guard let srcPath = item.imagePath,
              item.fileExists(appState: appState) else {
            failed += 1
            return
        }
        
        let srcURL = URL(fileURLWithPath: srcPath)
        let filename = srcURL.lastPathComponent  // Original name, e.g., "generated_image_507.jpg"
        
        let savePanel = NSSavePanel()
        savePanel.title = "Save Image"
        savePanel.prompt = "Save"
        savePanel.nameFieldStringValue = filename  // Pre-fill with original filename
        savePanel.allowedContentTypes = [UTType.png, UTType.jpeg, UTType.tiff, UTType.heic]  // Image types only
        
        guard savePanel.runModal() == .OK, let destURL = savePanel.url else {
            return  // User cancelled
        }
        toastMessage = "Saving image…"
        showToast = true
        hideToastAfterDelay()
        
        do {
            let data = try Data(contentsOf: srcURL)
            try data.write(to: destURL, options: .atomic)
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
    openPanel.title = "Choose Folder to Save \(items.count) Images"
    openPanel.prompt = "Select"
    openPanel.canChooseFiles = false              // No files
    openPanel.canChooseDirectories = true         // Folders only
    openPanel.allowsMultipleSelection = false
    openPanel.allowedContentTypes = []              // Any type
    openPanel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    
    guard openPanel.runModal() == .OK, let destinationFolder = openPanel.url else {
        return  // User cancelled
    }
    
        toastMessage = "Saving \(items.count) images…"
        showToast = true
        hideToastAfterDelay()
    
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
            let data = try Data(contentsOf: srcURL)
            try data.write(to: destURL, options: .atomic)
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
}
 
// LazyThumbnailView and extensions remain exactly as you had them
struct HistoryThumbnailSource: Hashable {
    let id: UUID
    let path: String?
    let status: GenerationStatus?

    init(_ item: HistoryItem) {
        id = item.id
        path = item.imagePath
        status = item.status
    }
}

struct LazyThumbnailView: View {
    let item: HistoryItem
    @State private var thumbnail: PlatformImage? = nil
    @EnvironmentObject var appState: AppState
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        Group {
            if let img = thumbnail {
                Image(platformImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.standard))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.standard)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        // Audio indicator badge for videos with audio
                        if item.imagePath?.hasSuffix(".mp4") == true && item.videoHasAudio == true {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(3)
                                .background(Color.black.opacity(0.7), in: Circle())
                                .padding(2)
                        }
                    }
                    .help(item.imagePath?.hasSuffix(".mp4") ?? false ? "Video thumbnail" : "Image thumbnail")
                    .accessibilityLabel(item.imagePath?.hasSuffix(".mp4") ?? false ? "Video thumbnail generated on \(dateFormatter.string(from: item.date))" : "Image thumbnail generated on \(dateFormatter.string(from: item.date))")
                    .onDrag {
                        // Prefer full-resolution file from disk over thumbnail
                        if let path = item.imagePath {
                            let fileURL = URL(fileURLWithPath: path)
                            let isVideo = fileURL.pathExtension.lowercased() == "mp4"

                            // For images, load full-resolution data with security-scoped access
                            if !isVideo {
                                let provider = NSItemProvider()
                                let typeIdentifier = fileURL.pathExtension.lowercased() == "png" ? UTType.png.identifier : UTType.jpeg.identifier

                                provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
                                    // Access security-scoped resource to read the file
                                    var didStart = false
                                    if let dir = appState.settings.outputDirectory {
                                        didStart = dir.startAccessingSecurityScopedResource()
                                    }

                                    defer {
                                        if didStart, let dir = appState.settings.outputDirectory {
                                            dir.stopAccessingSecurityScopedResource()
                                        }
                                    }

                                    do {
                                        let fullResData = try Data(contentsOf: fileURL)
                                        completion(fullResData, nil)
                                    } catch {
                                        // Fall back to thumbnail if file read fails
                                        completion(img.pngData(), nil)
                                    }
                                    return nil
                                }
                                return provider
                            }
                        }

                        // Fallback to thumbnail data if file not available
                        guard let data = img.pngData() else {
                            return NSItemProvider()
                        }
                        let provider = NSItemProvider()
                        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                            completion(data, nil)
                            return nil
                        }
                        return provider
                    }
            } else {
                Image(systemName: item.imagePath?.hasSuffix(".mp4") ?? false ? "film" : "photo")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                    .help(item.imagePath?.hasSuffix(".mp4") ?? false ? "Video thumbnail placeholder" : "Image thumbnail placeholder")
                    .accessibilityLabel(item.imagePath?.hasSuffix(".mp4") ?? false ? "Video thumbnail placeholder" : "Image thumbnail placeholder")
            }
        }
        .task(id: HistoryThumbnailSource(item)) {
            thumbnail = nil
            let loadedImage = await Self.loadThumbnail(for: item, appState: appState)
            guard !Task.isCancelled else { return }
            thumbnail = loadedImage
        }
    }

    // MARK: - Load Downscaled Thumbnail (≤512px) – for display only
    static func loadThumbnail(for item: HistoryItem, appState: AppState) async -> PlatformImage? {
        guard let path = item.imagePath else { return nil }
        let fileURL = URL(fileURLWithPath: path)
        let isVideo = fileURL.pathExtension.lowercased() == "mp4"
        
        let directory = appState.settings.outputDirectory
        let didStart = directory?.startAccessingSecurityScopedResource() ?? false
        defer { if didStart { directory?.stopAccessingSecurityScopedResource() } }
        // App-owned and fallback files may be readable without a security-scoped grant.
        return await loadThumbnail(from: fileURL, isVideo: isVideo)
    }
    
    // MARK: - Load Full-Resolution Image (for input slots)
    static func loadFullImage(for item: HistoryItem, appState: AppState) async -> PlatformImage? {
        guard let path = item.imagePath else { return nil }
        let fileURL = URL(fileURLWithPath: path)
        
        var data: Data?
        if let dir = appState.settings.outputDirectory {
            let dirStarted = dir.startAccessingSecurityScopedResource()
            defer { if dirStarted { dir.stopAccessingSecurityScopedResource() } }
            let fileStarted = fileURL.startAccessingSecurityScopedResource()
            defer { if fileStarted { fileURL.stopAccessingSecurityScopedResource() } }
            data = try? Data(contentsOf: fileURL)
        } else {
            data = try? Data(contentsOf: fileURL)
        }
        
        guard let imageData = data else { return nil }
        return PlatformImage(platformData: imageData)
    }
    
    // MARK: - Private: Shared thumbnail logic (unchanged from your code)
    private static func loadThumbnail(from fileURL: URL, isVideo: Bool) async -> PlatformImage? {
        if isVideo {
            // Your excellent retry logic — unchanged
            for attempt in 1...3 {
                do {
                    let asset = AVAsset(url: fileURL)
                    let isPlayable = try await asset.load(.isPlayable)
                    if !isPlayable {
                        if attempt < 3 { try await Task.sleep(nanoseconds: 1_000_000_000) }
                        continue
                    }
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 512, height: 512)
                    let time = CMTime(seconds: 0, preferredTimescale: 600)
                    let value = try await generator.image(at: time)
                    let cgImage = value.image
                    #if os(macOS)
                    return PlatformImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
                    #elseif os(iOS)
                    return PlatformImage(cgImage: cgImage)
                    #endif
                } catch {
                    Log.debug("Video thumbnail attempt \(attempt) failed: \(error)")
                    if attempt < 3 {
                        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch {}
                    }
                }
            }
            return nil
        } else {
            // IMAGE: Load full → downscale → release full
            guard let fullImage = PlatformImage(contentsOf: fileURL) else { return nil }
            return fullImage.downscaled(toMaxPixels: 512)
        }
    }
}
 
#if os(macOS)
extension NSImage {
    func pngData() -> Data? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif

private extension HistoryEntry {
    /// Recursively collects ALL descendant item IDs (not folder IDs)
    func allItemIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        collectItemIDs(into: &ids)
        return ids
    }
    
    private func collectItemIDs(into set: inout Set<UUID>) {
        switch self {
        case .item(let item):
            set.insert(item.id)
        case .folder(let folder):
            for child in folder.children {
                child.collectItemIDs(into: &set)
            }
        }
    }
}


