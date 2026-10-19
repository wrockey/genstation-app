// AIMLModelPickerSheet.swift
// The sheet that hosts the model browser. Chrome only.
//
// Everything this file used to do — sectioning, search, the row, the id list — moved to
// `ModelBrowserView` (rendering) and `GenStationCore.ModelBrowser` (all of the logic). What is left
// is the container: a NavigationStack, a title, a Done button, and the wiring from `AppState` to
// the browser's values and closures.
//
// The original header said this view "Replaces the flat Menu, which couldn't scale to ~600 models
// or host a search field." That was right, and is not being reversed. What was wrong was its
// content model: it rendered raw ids, searched only ids, and was fed a list containing duplicates.
import SwiftUI
import GenStationCore

struct AIMLModelPickerSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ModelBrowserView(
                task: appState.settings.task,
                served: appState.aimlServedModels,
                showAll: appState.settings.showAllAIMLModels,
                favorites: appState.settings.favoriteAIMLModels,
                recents: appState.settings.recentAIMLModels,
                selectedID: appState.settings.selectedAIMLModel,
                observedCost: appState.historyState.observedCostByModel,
                onSelect: { id in
                    // No canonicalization here, and that is the point. Task 20 wrote
                    // `Catalog.canonicalID(for: id) ?? id` at this site because the picker was fed
                    // raw API ids. `ModelBrowser` now canonicalizes the whole list once, and
                    // `ModelBrowserTests.testEveryRowIDIsCanonicalOrUnknownToTheCatalog` pins it —
                    // so this is a plain assignment again.
                    //
                    // It stays a direct assignment for the other reason too: this is the user
                    // choosing, and clearing the custom payload on an explicit pick is the
                    // behaviour that must not move.
                    appState.settings.selectedAIMLModel = id
                    appState.settings.recordRecentAIMLModel(id)
                    dismiss()
                },
                onToggleFavorite: { appState.settings.toggleFavoriteAIMLModel($0) })
                .navigationTitle(appState.settings.isVideoMode ? "Select Video Model" : "Select Image Model")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 360, minHeight: 480)
    }
}
