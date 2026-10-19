// StyleDatabase.swift
// Data models and loader for prompt style database

import SwiftUI

// MARK: - Platform Colors

extension Color {
    static var platformWindowBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    static var platformTextBackground: Color {
        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

// MARK: - Data Models

struct PromptStyle: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let prompt: String
    let negativePrompt: String
    let tags: [String]

    var description: String? { nil }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PromptStyle, rhs: PromptStyle) -> Bool {
        lhs.id == rhs.id
    }
}

struct StyleGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let styles: [PromptStyle]

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: StyleGroup, rhs: StyleGroup) -> Bool {
        lhs.id == rhs.id
    }
}

struct StyleSubcategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let groups: [StyleGroup]?
    let styles: [PromptStyle]?  // Some subcategories have styles directly

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: StyleSubcategory, rhs: StyleSubcategory) -> Bool {
        lhs.id == rhs.id
    }

    /// Returns all groups, creating synthetic groups from direct styles if needed
    var allGroups: [StyleGroup] {
        if let groups = groups {
            return groups
        } else if let styles = styles, !styles.isEmpty {
            // Wrap direct styles in a synthetic group
            return [StyleGroup(id: "\(id)-styles", name: "Styles", styles: styles)]
        }
        return []
    }
}

struct StyleCategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let subcategories: [StyleSubcategory]

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: StyleCategory, rhs: StyleCategory) -> Bool {
        lhs.id == rhs.id
    }

    var systemImage: String {
        switch icon {
        case "camera": return "camera"
        case "paintbrush.pointed": return "paintbrush.pointed"
        case "cube": return "cube"
        case "paintpalette": return "paintpalette"
        case "globe": return "globe"
        case "film": return "film"
        case "theatermasks": return "theatermasks"
        case "scissors": return "scissors"
        case "sparkles": return "sparkles"
        default: return "paintbrush"
        }
    }
}

struct StyleDatabase: Codable {
    let version: String
    let source: String
    let license: String?
    let categories: [StyleCategory]
}

// MARK: - Style Manager

@MainActor
class StyleManager: ObservableObject {
    static let shared = StyleManager()

    @Published var database: StyleDatabase?
    @Published var isLoaded = false
    @Published var loadError: String?

    private init() {
        loadDatabase()
    }

    func loadDatabase() {
        guard let url = Bundle.main.url(forResource: "prompt_styles", withExtension: "json") else {
            loadError = "Style database not found in bundle"
            Log.debug("StyleManager: prompt_styles.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            database = try JSONDecoder().decode(StyleDatabase.self, from: data)
            isLoaded = true
            Log.debug("StyleManager: Loaded \(database?.categories.count ?? 0) categories")
        } catch {
            loadError = "Failed to load styles: \(error.localizedDescription)"
            Log.debug("StyleManager: Failed to decode - \(error)")
        }
    }

    /// Apply selected styles to a base prompt - appends style descriptions after the prompt
    static func applyStyles(_ styles: [PromptStyle], to basePrompt: String) -> String {
        guard !styles.isEmpty else { return basePrompt }

        // Extract style descriptions (remove the {prompt} placeholder and clean up)
        let styleDescriptions = styles.map { style -> String in
            // Remove {prompt} and the " . " separator that typically follows it
            var description = style.prompt
                .replacingOccurrences(of: "{prompt}", with: "")
                .trimmingCharacters(in: .whitespaces)
            // Remove leading " . " if present
            if description.hasPrefix(". ") {
                description = String(description.dropFirst(2))
            }
            return description
        }

        // Combine all style descriptions
        let combinedStyles = styleDescriptions.joined(separator: " . ")

        // Append to base prompt with newline
        if basePrompt.isEmpty {
            return combinedStyles
        } else {
            return basePrompt + "\n" + combinedStyles
        }
    }

    /// Combine negative prompts from selected styles
    static func combineNegativePrompts(_ styles: [PromptStyle]) -> String {
        let negatives = styles.map { $0.negativePrompt }.filter { !$0.isEmpty }
        return negatives.joined(separator: ", ")
    }

    /// Search result with full path to the style
    struct SearchResult: Identifiable, Hashable {
        let id = UUID()
        let style: PromptStyle
        let category: StyleCategory
        let subcategory: StyleSubcategory
        let group: StyleGroup

        var breadcrumb: String {
            "\(category.name) → \(subcategory.name) → \(group.name)"
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(style.id)
        }

        static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
            lhs.style.id == rhs.style.id
        }
    }

    /// Search styles by name, tags, or hierarchy (category/subcategory/group names)
    func search(_ query: String) -> [SearchResult] {
        guard let database = database, !query.isEmpty else { return [] }

        let lowercasedQuery = query.lowercased()
        var results: [SearchResult] = []

        for category in database.categories {
            let categoryMatch = category.name.lowercased().contains(lowercasedQuery)

            for subcategory in category.subcategories {
                let subcategoryMatch = subcategory.name.lowercased().contains(lowercasedQuery)

                for group in subcategory.allGroups {
                    let groupMatch = group.name.lowercased().contains(lowercasedQuery)

                    for style in group.styles {
                        // Match against name, tags, or hierarchy
                        let nameMatch = style.name.lowercased().contains(lowercasedQuery)
                        let tagMatch = style.tags.contains { $0.lowercased().contains(lowercasedQuery) }

                        if nameMatch || tagMatch || categoryMatch || subcategoryMatch || groupMatch {
                            results.append(SearchResult(
                                style: style,
                                category: category,
                                subcategory: subcategory,
                                group: group
                            ))
                        }
                    }
                }
            }
        }

        return results
    }

    /// Get all styles as SearchResults
    func allStyles() -> [SearchResult] {
        guard let database = database else { return [] }

        var results: [SearchResult] = []

        for category in database.categories {
            for subcategory in category.subcategories {
                for group in subcategory.allGroups {
                    for style in group.styles {
                        results.append(SearchResult(
                            style: style,
                            category: category,
                            subcategory: subcategory,
                            group: group
                        ))
                    }
                }
            }
        }

        return results
    }

    /// Get a random style with its full path
    func randomStyle() -> SearchResult? {
        let all = allStyles()
        guard !all.isEmpty else { return nil }
        return all.randomElement()
    }
}

// MARK: - Column Browser Item Protocol

protocol ColumnBrowserItem: Identifiable, Hashable {
    var displayName: String { get }
    var hasChildren: Bool { get }
}

extension StyleCategory: ColumnBrowserItem {
    var displayName: String { name }
    var hasChildren: Bool { !subcategories.isEmpty }
}

extension StyleSubcategory: ColumnBrowserItem {
    var displayName: String { name }
    var hasChildren: Bool { !(groups?.isEmpty ?? true) || !(styles?.isEmpty ?? true) }
}

extension StyleGroup: ColumnBrowserItem {
    var displayName: String { name }
    var hasChildren: Bool { !styles.isEmpty }
}

extension PromptStyle: ColumnBrowserItem {
    var displayName: String { name }
    var hasChildren: Bool { false }
}

// MARK: - Style Browser View

struct StyleBrowserView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var styleManager = StyleManager.shared

    // Column selections
    @State private var selectedCategory: StyleCategory?
    @State private var selectedSubcategory: StyleSubcategory?
    @State private var selectedGroup: StyleGroup?

    // Multi-select for styles (shared with PromptSection for enhancement)
    private var selectedStyles: Binding<Set<PromptStyle>> {
        Binding(
            get: { appState.ui.selectedStyles },
            set: { appState.ui.selectedStyles = $0 }
        )
    }

    // Enhance sheet and model selection
    @State private var showEnhanceSheet: Bool = false
    @State private var selectedEnhancementModel: EnhancementModel = PromptEnhancer.shared.lastModel

    // Custom style editor
    @State private var showCustomStyleEditor: Bool = false
    @State private var editingStyle: PromptStyle? = nil

    // Special mode for showing custom styles or favorites
    @State private var showingCustomStyles: Bool = false
    @State private var showingFavorites: Bool = false

    // Search
    @State private var searchQuery: String = ""
    @State private var isSearchFocused: Bool = false
    @FocusState private var searchFieldFocused: Bool
    @State private var isNavigatingFromSearch: Bool = false

    // Computed search results
    private var searchResults: [StyleManager.SearchResult] {
        styleManager.search(searchQuery)
    }

    // Computed list of all favorited styles (from both built-in and custom)
    private var favoritedStyles: [PromptStyle] {
        var results: [PromptStyle] = []

        // Add favorited custom styles
        for style in appState.ui.customStyles {
            if appState.ui.favoriteStyleIDs.contains(style.id) {
                results.append(style)
            }
        }

        // Add favorited built-in styles
        if let database = styleManager.database {
            for category in database.categories {
                for subcategory in category.subcategories {
                    for group in subcategory.allGroups {
                        for style in group.styles {
                            if appState.ui.favoriteStyleIDs.contains(style.id) {
                                results.append(style)
                            }
                        }
                    }
                }
            }
        }

        return results
    }

    var body: some View {
        #if os(iOS)
        // iOS: NavigationStack drill-down pattern
        iOSNavigationBrowser
        #else
        // macOS: Column browser pattern
        VStack(spacing: 0) {
            // Search bar
            searchBar

            Divider()

            // Column browser or search results
            ZStack {
                columnBrowser

                // Search results overlay
                if !searchQuery.isEmpty {
                    searchResultsOverlay
                }
            }

            Divider()

            // Action bar (simplified)
            macOSActionBar
        }
        .sheet(isPresented: $showEnhanceSheet) {
            EnhancePromptView(
                originalPrompt: appState.prompt,
                styles: Array(selectedStyles.wrappedValue),
                initialModel: selectedEnhancementModel,
                onApply: { enhancedPrompt in
                    appState.prompt = enhancedPrompt
                    selectedStyles.wrappedValue.removeAll()
                },
                onPromptChanged: { newPrompt in
                    appState.prompt = newPrompt
                }
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showCustomStyleEditor) {
            CustomStyleEditorView(existingStyle: editingStyle) { newStyle in
                if editingStyle != nil {
                    appState.ui.updateCustomStyle(newStyle)
                } else {
                    appState.ui.addCustomStyle(newStyle)
                }
                editingStyle = nil
            }
        }
        #endif
    }

    // MARK: - macOS Action Bar

    #if os(macOS)
    private var macOSActionBar: some View {
        HStack(spacing: 12) {
            // New custom style button
            Button(action: {
                editingStyle = nil
                showCustomStyleEditor = true
            }) {
                Label("New Style", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.purple)
            .help("Create a custom style")

            // Clear selection
            Button(action: { selectedStyles.wrappedValue.removeAll() }) {
                Label("Clear", systemImage: "xmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .disabled(selectedStyles.wrappedValue.isEmpty)

            // Selected styles chips (scrollable)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(selectedStyles.wrappedValue)) { style in
                        styleChip(style)
                    }
                }
            }

            Spacer()

            // Hint when no styles selected
            if selectedStyles.wrappedValue.isEmpty {
                Text("Select a style")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }

            // Enhance button with model picker
            Menu {
                ForEach(EnhancementModel.allCases) { model in
                    let providerInfo = enhancementProviderInfo(for: model)
                    let displayText = "\(model.displayName) (\(providerInfo.label))"
                    Button(action: {
                        selectedEnhancementModel = model
                        PromptEnhancer.shared.lastModel = model
                    }) {
                        if model == selectedEnhancementModel {
                            Label(displayText, systemImage: "checkmark")
                        } else {
                            Text(displayText)
                        }
                    }
                    .disabled(!providerInfo.available)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("Enhance")
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            } primaryAction: {
                showEnhanceSheet = true
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .fill(Color.indigo.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(.indigo)
            .disabled(selectedStyles.wrappedValue.isEmpty)
            .help("Enhance with \(selectedEnhancementModel.displayName)")
            .id(selectedEnhancementModel)  // Force menu to update when selection changes
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.platformWindowBackground.opacity(0.3))
        .onAppear {
            // Sync with persisted model on appear
            selectedEnhancementModel = PromptEnhancer.shared.lastModel
        }
    }
    #endif

    // MARK: - iOS Navigation Browser

    #if os(iOS)
    @State private var navigationPath = NavigationPath()

    private var iOSNavigationBrowser: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Search bar at top
                iOSSearchBar

                // Category list
                List(styleManager.database?.categories ?? []) { category in
                    NavigationLink(value: category) {
                        Label(category.name, systemImage: category.systemImage)
                    }
                }
                .listStyle(.insetGrouped)

                // Bottom bar with selection info and actions
                if !selectedStyles.wrappedValue.isEmpty {
                    iOSSelectionBar
                }
            }
            .navigationTitle("Styles")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .navigationDestination(for: StyleCategory.self) { category in
                iOSSubcategoryList(category: category)
            }
            .navigationDestination(for: StyleSubcategory.self) { subcategory in
                iOSGroupList(subcategory: subcategory)
            }
            .navigationDestination(for: StyleGroup.self) { group in
                iOSStyleList(group: group)
            }
        }
    }

    private var iOSSearchBar: some View {
        HStack(spacing: 8) {
            // Random style button (leading)
            Button(action: selectRandomStyle) {
                Image(systemName: "dice.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
            }
            .accessibilityLabel("Add random style")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search styles...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFieldFocused)

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(DS.Radius.card)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            // Search results dropdown
            if !searchQuery.isEmpty {
                iOSSearchResults
                    .offset(y: 44)
            }
        }
        .zIndex(1)
    }

    private var iOSSearchResults: some View {
        VStack(spacing: 0) {
            if searchResults.isEmpty {
                Text("No results for \"\(searchQuery)\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                HStack {
                    Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { result in
                            Button(action: { iOSNavigateToResult(result) }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.style.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(result.breadcrumb)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                            }
                            Divider().padding(.leading)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(DS.Radius.panel)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal)
    }

    private func iOSNavigateToResult(_ result: StyleManager.SearchResult) {
        selectedStyles.wrappedValue.insert(result.style)
        searchQuery = ""
        searchFieldFocused = false
        // Navigate to the style's group
        navigationPath.append(result.category)
        navigationPath.append(result.subcategory)
        navigationPath.append(result.group)
    }

    private func iOSSubcategoryList(category: StyleCategory) -> some View {
        List(category.subcategories) { subcategory in
            NavigationLink(value: subcategory) {
                Text(subcategory.name)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func iOSGroupList(subcategory: StyleSubcategory) -> some View {
        List(subcategory.allGroups) { group in
            NavigationLink(value: group) {
                HStack {
                    Text(group.name)
                    Spacer()
                    Text("\(group.styles.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(subcategory.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func iOSStyleList(group: StyleGroup) -> some View {
        List(group.styles) { style in
            Button(action: {
                if selectedStyles.wrappedValue.contains(style) {
                    selectedStyles.wrappedValue.remove(style)
                } else {
                    selectedStyles.wrappedValue.insert(style)
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: selectedStyles.wrappedValue.contains(style) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(selectedStyles.wrappedValue.contains(style) ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(style.name)
                            .foregroundColor(.primary)
                        if !style.tags.isEmpty {
                            Text(style.tags.prefix(3).joined(separator: " · "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !selectedStyles.wrappedValue.isEmpty {
                    Text("\(selectedStyles.wrappedValue.count) selected")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selectedStyles.wrappedValue.isEmpty {
                iOSSelectionBar
            }
        }
    }

    private var iOSSelectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                // Selected styles chips (scrollable)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(selectedStyles.wrappedValue)) { style in
                            HStack(spacing: 4) {
                                Text(style.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Button(action: { selectedStyles.wrappedValue.remove(style) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .accessibilityLabel("Remove \(style.name)")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(DS.Radius.panel)
                        }
                    }
                }

                // Clear button
                Button(action: { selectedStyles.wrappedValue.removeAll() }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Clear all styles")

                // Enhance button with model picker
                Menu {
                    ForEach(EnhancementModel.allCases) { model in
                        let providerInfo = enhancementProviderInfo(for: model)
                        let displayText = "\(model.displayName) (\(providerInfo.label))"
                        Button(action: {
                            selectedEnhancementModel = model
                            PromptEnhancer.shared.lastModel = model
                        }) {
                            if model == selectedEnhancementModel {
                                Label(displayText, systemImage: "checkmark")
                            } else {
                                Text(displayText)
                            }
                        }
                        .disabled(!providerInfo.available)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("Enhance")
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.indigo)
                    .cornerRadius(DS.Radius.standard)
                } primaryAction: {
                    showEnhanceSheet = true
                }
                .id(selectedEnhancementModel)  // Force menu to update when selection changes
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .onAppear {
                selectedEnhancementModel = PromptEnhancer.shared.lastModel
            }
        }
        .sheet(isPresented: $showEnhanceSheet) {
            EnhancePromptView(
                originalPrompt: appState.prompt,
                styles: Array(selectedStyles.wrappedValue),
                initialModel: selectedEnhancementModel,
                onApply: { enhancedPrompt in
                    appState.prompt = enhancedPrompt
                    selectedStyles.wrappedValue.removeAll()
                },
                onPromptChanged: { newPrompt in
                    appState.prompt = newPrompt
                }
            )
            .environmentObject(appState)
        }
    }
    #endif

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            // Random style button (leading)
            Button(action: selectRandomStyle) {
                Image(systemName: "dice.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .help("Add random style")
            .accessibilityLabel("Add random style")

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("Search styles...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(DS.footnoteFont)
                    .focused($searchFieldFocused)

                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        searchFieldFocused = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.platformTextBackground.opacity(0.5))
            .cornerRadius(DS.Radius.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func selectRandomStyle() {
        guard let result = styleManager.randomStyle() else { return }

        // Navigate to show the style in the browser
        isNavigatingFromSearch = true
        selectedCategory = result.category
        selectedSubcategory = result.subcategory
        selectedGroup = result.group

        // Add to existing selection (don't replace)
        selectedStyles.wrappedValue.insert(result.style)

        searchQuery = ""
        searchFieldFocused = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNavigatingFromSearch = false
        }
    }

    // MARK: - Search Results Overlay

    private var searchResultsOverlay: some View {
        VStack(spacing: 0) {
            if searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No styles found for \"\(searchQuery)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Results header
                HStack {
                    Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                // Results list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { result in
                            searchResultRow(result)
                        }
                    }
                }
            }
        }
        .background(Color.platformWindowBackground.opacity(0.95))
    }

    private func searchResultRow(_ result: StyleManager.SearchResult) -> some View {
        Button(action: { navigateToResult(result) }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.style.name)
                    .font(DS.footnoteFont.weight(.medium))
                    .foregroundColor(.primary)

                Text(result.breadcrumb)
                    .font(DS.captionFont)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
    }

    private func navigateToResult(_ result: StyleManager.SearchResult) {
        // Set flag to prevent onChange from clearing child selections
        isNavigatingFromSearch = true

        // Navigate column browser to this style's location
        selectedCategory = result.category
        selectedSubcategory = result.subcategory
        selectedGroup = result.group

        // Auto-select the style
        selectedStyles.wrappedValue.insert(result.style)

        // Clear search
        searchQuery = ""
        searchFieldFocused = false

        // Reset flag after a brief delay to allow state to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNavigatingFromSearch = false
        }
    }

    // MARK: - Column Browser

    private var columnBrowser: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Column 1: Categories (with My Styles/Favorites at top)
                categoriesColumnView
                    .frame(width: geo.size.width / 4)
                    .onChange(of: selectedCategory) { _ in
                        guard !isNavigatingFromSearch else { return }
                        selectedSubcategory = nil
                        selectedGroup = nil
                    }
                    .onChange(of: showingCustomStyles) { newValue in
                        if newValue {
                            // Clear regular category selection when entering custom styles mode
                            showingFavorites = false
                            selectedCategory = nil
                            selectedSubcategory = nil
                            selectedGroup = nil
                        }
                    }
                    .onChange(of: showingFavorites) { newValue in
                        if newValue {
                            // Clear regular category selection when entering favorites mode
                            showingCustomStyles = false
                            selectedCategory = nil
                            selectedSubcategory = nil
                            selectedGroup = nil
                        }
                    }

                Divider()

                // Column 2: Subcategories (or empty if showing custom styles/favorites)
                if showingCustomStyles || showingFavorites {
                    // Empty column when in custom styles or favorites mode
                    emptyColumnPlaceholder(title: "Subcategory")
                        .frame(width: geo.size.width / 4)
                } else {
                    columnView(
                        title: "Subcategory",
                        items: selectedCategory?.subcategories ?? [],
                        selection: $selectedSubcategory,
                        icon: nil,
                        emptyHint: selectedCategory == nil ? "← Select a category" : nil
                    )
                    .frame(width: geo.size.width / 4)
                    .onChange(of: selectedSubcategory) { _ in
                        guard !isNavigatingFromSearch else { return }
                        selectedGroup = nil
                    }
                }

                Divider()

                // Column 3: Groups (or empty if showing custom styles/favorites)
                if showingCustomStyles || showingFavorites {
                    // Empty column when in custom styles or favorites mode
                    emptyColumnPlaceholder(title: "Group")
                        .frame(width: geo.size.width / 4)
                } else {
                    columnView(
                        title: "Group",
                        items: selectedSubcategory?.allGroups ?? [],
                        selection: $selectedGroup,
                        icon: nil,
                        emptyHint: selectedSubcategory == nil ? "← Select a subcategory" : nil
                    )
                    .frame(width: geo.size.width / 4)
                }

                Divider()

                // Column 4: Styles (custom styles, favorites, or regular styles)
                if showingCustomStyles {
                    customStylesColumnView
                        .frame(width: geo.size.width / 4)
                } else if showingFavorites {
                    favoritesColumnView
                        .frame(width: geo.size.width / 4)
                } else {
                    styleColumnView(
                        title: "Style",
                        styles: selectedGroup?.styles ?? [],
                        selectedStyles: selectedStyles,
                        emptyHint: selectedGroup == nil ? "← Select a group" : nil
                    )
                    .frame(width: geo.size.width / 4)
                }
            }
        }
    }

    // MARK: - Categories Column with My Styles

    private var categoriesColumnView: some View {
        VStack(spacing: 0) {
            // Header
            Text("Category")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.platformWindowBackground.opacity(0.5))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    // My Styles section (always visible)
                    specialCategoryRow(
                        name: "My Styles",
                        icon: "person.crop.circle",
                        color: .purple,
                        isSelected: showingCustomStyles,
                        badge: appState.ui.customStyles.count
                    ) {
                        showingCustomStyles = true
                        selectedCategory = nil
                    }

                    // Favorites section (if any favorites exist)
                    if !appState.ui.favoriteStyleIDs.isEmpty {
                        specialCategoryRow(
                            name: "Favorites",
                            icon: "star.fill",
                            color: .yellow,
                            isSelected: showingFavorites,
                            badge: appState.ui.favoriteStyleIDs.count
                        ) {
                            showingFavorites = true
                            selectedCategory = nil
                        }
                    }

                    // Separator
                    if !appState.ui.customStyles.isEmpty || !appState.ui.favoriteStyleIDs.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                    }

                    // Regular categories
                    ForEach(styleManager.database?.categories ?? []) { category in
                        columnRow(
                            item: category,
                            isSelected: selectedCategory?.id == category.id && !showingCustomStyles,
                            icon: category.systemImage
                        ) {
                            showingCustomStyles = false
                            selectedCategory = category
                        }
                    }
                }
            }
        }
    }

    private func specialCategoryRow(
        name: String,
        icon: String,
        color: Color,
        isSelected: Bool,
        badge: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 16)

                Text(name)
                    .font(DS.footnoteFont)
                    .lineLimit(1)

                Spacer()

                if badge > 0 {
                    Text("\(badge)")
                        .font(DS.captionFont)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(DS.Radius.standard)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }

    private func emptyColumnPlaceholder(title: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.platformWindowBackground.opacity(0.5))

            Divider()

            Spacer()
        }
    }

    // MARK: - Custom Styles Column

    private var customStylesColumnView: some View {
        VStack(spacing: 0) {
            // Header with count
            HStack {
                Text("My Styles")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if !selectedStyles.wrappedValue.isEmpty {
                    Text("\(selectedStyles.wrappedValue.count) selected")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.platformWindowBackground.opacity(0.5))

            Divider()

            if appState.ui.customStyles.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "paintbrush.pointed")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No custom styles yet")
                        .font(DS.footnoteFont)
                        .foregroundColor(.secondary)

                    Button(action: {
                        editingStyle = nil
                        showCustomStyleEditor = true
                    }) {
                        Label("Create Style", systemImage: "plus")
                            .font(DS.smallFont)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.ui.customStyles) { style in
                            customStyleRow(style: style)
                        }
                    }
                }
            }
        }
    }

    private func customStyleRow(style: PromptStyle) -> some View {
        let isSelected = selectedStyles.wrappedValue.contains(style)

        return HStack(spacing: 4) {
            Button(action: {
                if isSelected {
                    selectedStyles.wrappedValue.remove(style)
                } else {
                    selectedStyles.wrappedValue.insert(style)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(style.name)
                                .font(DS.footnoteFont)
                                .lineLimit(1)

                            // Custom badge
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.purple.opacity(0.6))
                        }

                        if !style.tags.isEmpty {
                            Text(style.tags.prefix(3).joined(separator: " · "))
                                .font(DS.tinyFont)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Favorite star
            Button(action: {
                appState.ui.toggleFavorite(style.id)
            }) {
                Image(systemName: appState.ui.isFavorite(style.id) ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundColor(appState.ui.isFavorite(style.id) ? .yellow : .secondary.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appState.ui.isFavorite(style.id) ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contextMenu {
            Button(action: {
                editingStyle = style
                showCustomStyleEditor = true
            }) {
                Label("Edit Style", systemImage: "pencil")
            }

            Button(action: {
                appState.ui.toggleFavorite(style.id)
            }) {
                if appState.ui.isFavorite(style.id) {
                    Label("Remove from Favorites", systemImage: "star.slash")
                } else {
                    Label("Add to Favorites", systemImage: "star")
                }
            }

            Divider()

            Button(role: .destructive, action: {
                appState.ui.deleteCustomStyle(style)
            }) {
                Label("Delete Style", systemImage: "trash")
            }
        }
    }

    // MARK: - Favorites Column

    private var favoritesColumnView: some View {
        VStack(spacing: 0) {
            // Header with count
            HStack {
                Text("Favorites")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if !selectedStyles.wrappedValue.isEmpty {
                    Text("\(selectedStyles.wrappedValue.count) selected")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.platformWindowBackground.opacity(0.5))

            Divider()

            if favoritedStyles.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "star")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No favorites yet")
                        .font(DS.footnoteFont)
                        .foregroundColor(.secondary)

                    Text("Star any style to add it here")
                        .font(DS.smallFont)
                        .foregroundColor(.secondary.opacity(0.7))

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(favoritedStyles) { style in
                            favoriteStyleRow(style: style)
                        }
                    }
                }
            }
        }
    }

    private func favoriteStyleRow(style: PromptStyle) -> some View {
        let isSelected = selectedStyles.wrappedValue.contains(style)
        let isCustomStyle = style.id.hasPrefix("custom-")

        return HStack(spacing: 4) {
            Button(action: {
                if isSelected {
                    selectedStyles.wrappedValue.remove(style)
                } else {
                    selectedStyles.wrappedValue.insert(style)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(style.name)
                                .font(DS.footnoteFont)
                                .lineLimit(1)

                            // Custom badge if it's a custom style
                            if isCustomStyle {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.purple.opacity(0.6))
                            }
                        }

                        if !style.tags.isEmpty {
                            Text(style.tags.prefix(3).joined(separator: " · "))
                                .font(DS.tinyFont)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Favorite star (filled, can unfavorite)
            Button(action: {
                appState.ui.toggleFavorite(style.id)
            }) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.yellow)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from favorites")
            .accessibilityLabel("Remove from favorites")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contextMenu {
            // Edit option only for custom styles
            if isCustomStyle {
                Button(action: {
                    editingStyle = style
                    showCustomStyleEditor = true
                }) {
                    Label("Edit Style", systemImage: "pencil")
                }
            }

            Button(action: {
                appState.ui.toggleFavorite(style.id)
            }) {
                Label("Remove from Favorites", systemImage: "star.slash")
            }

            // Delete option only for custom styles
            if isCustomStyle {
                Divider()

                Button(role: .destructive, action: {
                    appState.ui.deleteCustomStyle(style)
                }) {
                    Label("Delete Style", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Single-select Column

    private func columnView<T: ColumnBrowserItem>(
        title: String,
        items: [T],
        selection: Binding<T?>,
        icon: ((T) -> String)?,
        emptyHint: String? = nil
    ) -> some View {
        VStack(spacing: 0) {
            // Header
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.platformWindowBackground.opacity(0.5))

            Divider()

            // Items list or empty state
            if items.isEmpty {
                // Empty state with hint
                VStack(spacing: 8) {
                    Spacer()
                    if let hint = emptyHint {
                        Text(hint)
                            .font(DS.smallFont)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            columnRow(
                                item: item,
                                isSelected: selection.wrappedValue?.id == item.id,
                                icon: icon?(item)
                            ) {
                                selection.wrappedValue = item
                            }
                        }
                    }
                }
            }
        }
    }

    private func columnRow<T: ColumnBrowserItem>(
        item: T,
        isSelected: Bool,
        icon: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                }

                Text(item.displayName)
                    .font(DS.footnoteFont)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                if item.hasChildren {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        #if os(macOS)
        .help(item.displayName)
        #endif
    }

    // MARK: - Multi-select Style Column

    private func styleColumnView(
        title: String,
        styles: [PromptStyle],
        selectedStyles: Binding<Set<PromptStyle>>,
        emptyHint: String? = nil
    ) -> some View {
        VStack(spacing: 0) {
            // Header with count
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if !selectedStyles.wrappedValue.isEmpty {
                    Text("\(selectedStyles.wrappedValue.count) selected")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.platformWindowBackground.opacity(0.5))

            Divider()

            // Styles list with checkmarks or empty state
            if styles.isEmpty {
                // Empty state with hint
                VStack(spacing: 8) {
                    Spacer()
                    if let hint = emptyHint {
                        Text(hint)
                            .font(DS.smallFont)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(styles) { style in
                            styleRow(
                                style: style,
                                isSelected: selectedStyles.wrappedValue.contains(style),
                                toggle: {
                                    if selectedStyles.wrappedValue.contains(style) {
                                        selectedStyles.wrappedValue.remove(style)
                                    } else {
                                        selectedStyles.wrappedValue.insert(style)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private func styleRow(
        style: PromptStyle,
        isSelected: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(style.displayName)
                            .font(DS.footnoteFont)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if !style.tags.isEmpty {
                            Text(style.tags.prefix(3).joined(separator: " · "))
                                .font(DS.tinyFont)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Favorite star
            Button(action: {
                appState.ui.toggleFavorite(style.id)
            }) {
                Image(systemName: appState.ui.isFavorite(style.id) ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundColor(appState.ui.isFavorite(style.id) ? .yellow : .secondary.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(appState.ui.isFavorite(style.id) ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(appState.ui.isFavorite(style.id) ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        #if os(macOS)
        .help(style.displayName)
        #endif
    }

    // MARK: - Style Chip

    private func styleChip(_ style: PromptStyle) -> some View {
        HStack(spacing: 2) {
            Text(style.name)
                .font(DS.captionFont)
                .lineLimit(1)

            Button(action: { selectedStyles.wrappedValue.remove(style) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(style.name)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.2))
        .cornerRadius(DS.Radius.card)
    }

    // MARK: - Helpers

    /// Returns provider info for enhancement model based on available API keys
    private func enhancementProviderInfo(for model: EnhancementModel) -> (label: String, available: Bool) {
        let provider = model.selectProvider(
            geminiKey: appState.settings.apiKey,
            aimlKey: appState.settings.aimlapiKey,
            grokKey: appState.settings.grokApiKey
        )
        if let provider = provider {
            switch provider {
            case .gemini: return ("Gemini", true)
            case .aimlapi: return ("AI·ML", true)
            case .xai: return ("xAI", true)
            }
        }
        return ("No key", false)
    }
}

// MARK: - Keyboard Event Handling (macOS)

#if os(macOS)
struct KeyEventHandlingView: NSViewRepresentable {
    let onKeyDown: (UInt16) -> Bool  // Returns true if handled

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        // Request focus after a short delay to ensure view is in hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }

    class KeyCaptureNSView: NSView {
        var onKeyDown: ((UInt16) -> Bool)?

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func keyDown(with event: NSEvent) {
            if let handler = onKeyDown, handler(event.keyCode) {
                // Event was handled
            } else {
                super.keyDown(with: event)
            }
        }

        override func becomeFirstResponder() -> Bool {
            return true
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            window?.makeFirstResponder(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Request focus when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }
}

// Key codes for reference
private enum KeyCode: UInt16 {
    case upArrow = 126
    case downArrow = 125
    case leftArrow = 123
    case rightArrow = 124
    case space = 49
    case returnKey = 36
    case delete = 51
    case home = 115
    case escape = 53
}
#endif

extension View {
    @ViewBuilder
    func keyboardNavigationOverlay(
        onUp: @escaping () -> Void,
        onDown: @escaping () -> Void,
        onLeft: @escaping () -> Void,
        onRight: @escaping () -> Void,
        onSpace: @escaping () -> Void,
        onReturn: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onHome: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
        self.background(
            KeyEventHandlingView { keyCode in
                switch keyCode {
                case 126: onUp(); return true      // Up arrow
                case 125: onDown(); return true    // Down arrow
                case 123: onLeft(); return true    // Left arrow
                case 124: onRight(); return true   // Right arrow
                case 49: onSpace(); return true    // Space
                case 36: onReturn(); return true   // Return
                case 51: onDelete(); return true   // Delete
                case 115: onHome(); return true    // Home
                default: return false
                }
            }
            .allowsHitTesting(true)
        )
        #else
        self
        #endif
    }
}

// MARK: - Breadcrumb Style Browser (Option A - Drill-down Navigation)

struct TabFilterStyleBrowser: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var styleManager = StyleManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }

    // Navigation state - drill down through hierarchy
    enum BrowseLevel: Equatable {
        case root                                    // Show categories + My Styles + Favorites
        case category(StyleCategory)                 // Show subcategories
        case subcategory(StyleCategory, StyleSubcategory)  // Show groups
        case group(StyleCategory, StyleSubcategory, StyleGroup)  // Show styles
        case myStyles                                // Show custom styles
        case favorites                               // Show favorited styles
    }

    @State private var currentLevel: BrowseLevel = .root

    // Keyboard navigation
    @State private var focusedIndex: Int = 0

    // Search
    @State private var searchText: String = ""
    @State private var isSearchExpanded: Bool = false
    @FocusState private var searchFocused: Bool

    // Custom style editor
    @State private var showCustomStyleEditor: Bool = false
    @State private var editingStyle: PromptStyle? = nil

    // Styles popover
    @State private var showStylesPopover: Bool = false

    // Selected styles binding
    private var selectedStyles: Binding<Set<PromptStyle>> {
        Binding(
            get: { appState.ui.selectedStyles },
            set: { appState.ui.selectedStyles = $0 }
        )
    }

    // Favorited styles
    private var favoritedStyles: [PromptStyle] {
        var results: [PromptStyle] = []
        for style in appState.ui.customStyles {
            if appState.ui.favoriteStyleIDs.contains(style.id) {
                results.append(style)
            }
        }
        if let database = styleManager.database {
            for category in database.categories {
                for subcategory in category.subcategories {
                    for group in subcategory.allGroups {
                        for style in group.styles {
                            if appState.ui.favoriteStyleIDs.contains(style.id) {
                                results.append(style)
                            }
                        }
                    }
                }
            }
        }
        return results
    }

    // Current item count for keyboard navigation
    private var currentItemCount: Int {
        if !searchText.isEmpty {
            return styleManager.search(searchText).count
        }
        switch currentLevel {
        case .root:
            let baseCount = 1 + (appState.ui.favoriteStyleIDs.isEmpty ? 0 : 1) // My Styles + Favorites
            return baseCount + (styleManager.database?.categories.count ?? 0)
        case .myStyles:
            return appState.ui.customStyles.count
        case .favorites:
            return favoritedStyles.count
        case .category(let cat):
            return cat.subcategories.count
        case .subcategory(_, let sub):
            return sub.allGroups.count
        case .group(_, _, let grp):
            return grp.styles.count
        }
    }

    // Get the style at focused index (for space to toggle)
    private func styleAtFocusedIndex() -> PromptStyle? {
        if !searchText.isEmpty {
            let results = styleManager.search(searchText)
            guard focusedIndex < results.count else { return nil }
            return results[focusedIndex].style
        }
        switch currentLevel {
        case .myStyles:
            guard focusedIndex < appState.ui.customStyles.count else { return nil }
            return appState.ui.customStyles[focusedIndex]
        case .favorites:
            guard focusedIndex < favoritedStyles.count else { return nil }
            return favoritedStyles[focusedIndex]
        case .group(_, _, let grp):
            guard focusedIndex < grp.styles.count else { return nil }
            return grp.styles[focusedIndex]
        default:
            return nil
        }
    }

    // MARK: - Keyboard Navigation

    private func handleKeyDown() {
        if focusedIndex < currentItemCount - 1 {
            focusedIndex += 1
        }
    }

    private func handleKeyUp() {
        if focusedIndex > 0 {
            focusedIndex -= 1
        }
    }

    private func handleKeyRight() {
        // Drill into focused item
        if !searchText.isEmpty {
            // In search results, select the style
            if let style = styleAtFocusedIndex() {
                selectedStyles.wrappedValue.insert(style)
            }
            return
        }

        switch currentLevel {
        case .root:
            // Determine which item is focused
            let hasFavorites = !appState.ui.favoriteStyleIDs.isEmpty
            if focusedIndex == 0 {
                currentLevel = .myStyles
                focusedIndex = 0
            } else if hasFavorites && focusedIndex == 1 {
                currentLevel = .favorites
                focusedIndex = 0
            } else {
                let categoryIndex = focusedIndex - (hasFavorites ? 2 : 1)
                if let categories = styleManager.database?.categories,
                   categoryIndex < categories.count {
                    currentLevel = .category(categories[categoryIndex])
                    focusedIndex = 0
                }
            }

        case .category(let cat):
            if focusedIndex < cat.subcategories.count {
                currentLevel = .subcategory(cat, cat.subcategories[focusedIndex])
                focusedIndex = 0
            }

        case .subcategory(let cat, let sub):
            let groups = sub.allGroups
            if focusedIndex < groups.count {
                currentLevel = .group(cat, sub, groups[focusedIndex])
                focusedIndex = 0
            }

        case .group, .myStyles, .favorites:
            // At style level - toggle selection
            if let style = styleAtFocusedIndex() {
                if selectedStyles.wrappedValue.contains(style) {
                    selectedStyles.wrappedValue.remove(style)
                } else {
                    selectedStyles.wrappedValue.insert(style)
                }
            }
        }
    }

    private func handleKeyLeft() {
        // Go back up one level
        switch currentLevel {
        case .root:
            break // Already at root
        case .myStyles, .favorites:
            currentLevel = .root
            focusedIndex = 0
        case .category:
            currentLevel = .root
            focusedIndex = 0
        case .subcategory(let cat, _):
            currentLevel = .category(cat)
            focusedIndex = 0
        case .group(let cat, let sub, _):
            currentLevel = .subcategory(cat, sub)
            focusedIndex = 0
        }
    }

    private func handleSpaceKey() {
        // Toggle selection on focused style
        if let style = styleAtFocusedIndex() {
            if selectedStyles.wrappedValue.contains(style) {
                selectedStyles.wrappedValue.remove(style)
            } else {
                selectedStyles.wrappedValue.insert(style)
            }
        }
    }

    private func handleHomeKey() {
        currentLevel = .root
        focusedIndex = 0
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb navigation bar
            breadcrumbBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Main content list
            contentList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 40, coordinateSpace: .local)
                        .onEnded { value in
                            if value.translation.width > 60 && abs(value.translation.height) < abs(value.translation.width) {
                                withAnimation(DS.Anim.quick) {
                                    handleKeyLeft()
                                }
                            }
                        }
                )
                .onChange(of: currentLevel) { _ in
                    // Reset focus index when level changes
                    if focusedIndex >= currentItemCount {
                        focusedIndex = max(0, currentItemCount - 1)
                    }
                }
                .onChange(of: searchText) { _ in
                    focusedIndex = 0
                }

            Divider()

            // Action bar
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .keyboardNavigationOverlay(
            onUp: handleKeyUp,
            onDown: handleKeyDown,
            onLeft: handleKeyLeft,
            onRight: handleKeyRight,
            onSpace: handleSpaceKey,
            onReturn: handleKeyRight,
            onDelete: handleKeyLeft,
            onHome: handleHomeKey
        )
        .sheet(isPresented: $showCustomStyleEditor) {
            CustomStyleEditorView(existingStyle: editingStyle) { newStyle in
                if editingStyle != nil {
                    appState.ui.updateCustomStyle(newStyle)
                } else {
                    appState.ui.addCustomStyle(newStyle)
                }
                editingStyle = nil
            }
        }
    }

    // MARK: - Breadcrumb Bar

    private var breadcrumbBar: some View {
        Group {
            if isCompact {
                compactBreadcrumbBar
            } else {
                regularBreadcrumbBar
            }
        }
    }

    // MARK: Regular breadcrumb bar (macOS, iPad)

    private var regularBreadcrumbBar: some View {
        HStack(spacing: 6) {
            // Home button
            Button(action: { currentLevel = .root }) {
                Image(systemName: "house.fill")
                    .font(.system(size: 16))
                    .foregroundColor(currentLevel == .root ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Home")

            // Breadcrumb segments based on current level
            breadcrumbSegments

            Spacer()

            // Search field — flexible width
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DS.bodyFont)
                    .frame(minWidth: 110, maxWidth: 220)
                    .focused($searchFocused)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(DS.Radius.standard)
        }
    }

    // MARK: Compact breadcrumb bar (iPhone)

    private var compactBreadcrumbBar: some View {
        VStack(spacing: 8) {
            // Row 1: Home + breadcrumbs + dice + search toggle
            HStack(spacing: 6) {
                Button(action: { currentLevel = .root }) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 16))
                        .foregroundColor(currentLevel == .root ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Home")

                breadcrumbSegments

                Spacer()

                Button(action: {
                    withAnimation(DS.Anim.springFast) {
                        isSearchExpanded.toggle()
                        if isSearchExpanded {
                            searchFocused = true
                        }
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(isSearchExpanded ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSearchExpanded ? "Close search" : "Search styles")
            }

            // Row 2: Expandable search field
            if isSearchExpanded {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    TextField("Search styles...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DS.bodyFont)
                        .focused($searchFocused)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }

                    Button("Cancel") {
                        withAnimation(DS.Anim.springFast) {
                            isSearchExpanded = false
                        }
                    }
                    .font(DS.smallFont)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(DS.Radius.standard)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: isSearchExpanded) { expanded in
            if !expanded {
                searchText = ""
            }
        }
    }

    // MARK: - Random Style Selection

    private func selectRandomStyle() {
        guard let result = styleManager.randomStyle() else { return }

        // Add to selection
        selectedStyles.wrappedValue.insert(result.style)

        // Navigate to the style's location in the browser
        currentLevel = .group(result.category, result.subcategory, result.group)

        // Set focus to the selected style in the list
        if let styleIndex = result.group.styles.firstIndex(where: { $0.id == result.style.id }) {
            focusedIndex = styleIndex
        }

        // Clear search if active
        searchText = ""
    }

    @ViewBuilder
    private var breadcrumbSegments: some View {
        switch currentLevel {
        case .root:
            EmptyView()

        case .myStyles:
            breadcrumbChevron
            breadcrumbButton(title: "My Styles", icon: "person.crop.circle.fill", color: .purple, isActive: true) {}

        case .favorites:
            breadcrumbChevron
            breadcrumbButton(title: "Favorites", icon: "star.fill", color: .yellow, isActive: true) {}

        case .category(let cat):
            breadcrumbChevron
            breadcrumbButton(title: cat.name, icon: cat.systemImage, color: .secondary, isActive: true) {}

        case .subcategory(let cat, let sub):
            breadcrumbChevron
            breadcrumbButton(title: cat.name, icon: cat.systemImage, color: .secondary, isActive: false) {
                currentLevel = .category(cat)
            }
            breadcrumbChevron
            breadcrumbButton(title: sub.name, icon: nil, color: .secondary, isActive: true) {}

        case .group(let cat, let sub, let grp):
            breadcrumbChevron
            breadcrumbButton(title: cat.name, icon: cat.systemImage, color: .secondary, isActive: false) {
                currentLevel = .category(cat)
            }
            breadcrumbChevron
            breadcrumbButton(title: sub.name, icon: nil, color: .secondary, isActive: false) {
                currentLevel = .subcategory(cat, sub)
            }
            breadcrumbChevron
            breadcrumbButton(title: grp.name, icon: nil, color: .secondary, isActive: true) {}
        }
    }

    private var breadcrumbChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9))
            .foregroundColor(.secondary.opacity(0.6))
    }

    private func breadcrumbButton(title: String, icon: String?, color: Color, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(DS.smallFont.weight(isActive ? .medium : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(isActive)
    }

    // MARK: - Content List

    private var contentList: some View {
        Group {
            if !searchText.isEmpty {
                searchResultsList
            } else {
                levelContentList
            }
        }
    }

    // Search results across all styles
    private var searchResultsList: some View {
        let results = styleManager.search(searchText)

        return Group {
            if results.isEmpty {
                emptySearchState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            searchResultRow(result: result, isFocused: focusedIndex == index)
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }

    private func searchResultRow(result: StyleManager.SearchResult, isFocused: Bool = false) -> some View {
        let style = result.style
        let isSelected = selectedStyles.wrappedValue.contains(style)
        let isFavorite = appState.ui.favoriteStyleIDs.contains(style.id)

        return HStack(spacing: 8) {
            Button(action: {
                if isSelected {
                    selectedStyles.wrappedValue.remove(style)
                } else {
                    selectedStyles.wrappedValue.insert(style)
                }
            }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(style.name)
                    .font(DS.bodyFont.weight(.medium))
                    .lineLimit(2)
                Text(result.breadcrumb)
                    .font(DS.captionFont)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Prompt preview
                promptPreview(for: style)
            }

            Spacer(minLength: 4)

            Button(action: { appState.ui.toggleFavorite(style.id) }) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundColor(isFavorite ? .yellow : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(isFocused ? Color.accentColor.opacity(0.15) : (isSelected ? Color.accentColor.opacity(0.08) : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        )
        .contentShape(Rectangle())
    }

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No styles match \"\(searchText)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // Level-specific content
    @ViewBuilder
    private var levelContentList: some View {
        switch currentLevel {
        case .root:
            rootLevelList
        case .myStyles:
            myStylesList
        case .favorites:
            favoritesList
        case .category(let cat):
            subcategoryList(category: cat)
        case .subcategory(_, let sub):
            groupList(subcategory: sub)
        case .group(_, _, let grp):
            stylesList(styles: grp.styles)
        }
    }

    // Root level: My Styles, Favorites, Categories
    private var rootLevelList: some View {
        let hasFavorites = !appState.ui.favoriteStyleIDs.isEmpty
        let categories = styleManager.database?.categories ?? []

        return ScrollView {
            LazyVStack(spacing: 0) {
                // My Styles (index 0)
                rootCategoryRow(
                    title: "My Styles",
                    icon: "person.crop.circle.fill",
                    iconColor: .purple,
                    subtitle: "\(appState.ui.customStyles.count) styles",
                    isFocused: focusedIndex == 0
                ) {
                    currentLevel = .myStyles
                    focusedIndex = 0
                }
                Divider().padding(.leading, 56)

                // Favorites (index 1 if exists)
                if hasFavorites {
                    rootCategoryRow(
                        title: "Favorites",
                        icon: "star.fill",
                        iconColor: .yellow,
                        subtitle: "\(appState.ui.favoriteStyleIDs.count) styles",
                        isFocused: focusedIndex == 1
                    ) {
                        currentLevel = .favorites
                        focusedIndex = 0
                    }
                    Divider().padding(.leading, 56)
                }

                // Section header separator
                HStack {
                    Text("BROWSE STYLES")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.03))

                // Categories (index starts at 1 or 2 depending on favorites)
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    let categoryFocusIndex = index + (hasFavorites ? 2 : 1)
                    let styleCount = category.subcategories.reduce(0) { $0 + $1.allGroups.reduce(0) { $0 + $1.styles.count } }
                    rootCategoryRow(
                        title: category.name,
                        icon: category.systemImage,
                        iconColor: .accentColor,
                        subtitle: "\(category.subcategories.count) subcategories · \(styleCount) styles",
                        isFocused: focusedIndex == categoryFocusIndex
                    ) {
                        currentLevel = .category(category)
                        focusedIndex = 0
                    }
                    Divider().padding(.leading, 56)
                }
            }
        }
    }

    // My Styles list
    private var myStylesList: some View {
        Group {
            if appState.ui.customStyles.isEmpty {
                emptyMyStylesState
            } else {
                stylesList(styles: appState.ui.customStyles, isCustom: true)
            }
        }
    }

    private var emptyMyStylesState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No custom styles yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button(action: {
                editingStyle = nil
                showCustomStyleEditor = true
            }) {
                Label("Create Style", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    // Favorites list
    private var favoritesList: some View {
        Group {
            if favoritedStyles.isEmpty {
                emptyFavoritesState
            } else {
                stylesList(styles: favoritedStyles)
            }
        }
    }

    private var emptyFavoritesState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "star")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No favorites yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Star any style to add it here")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
    }

    // Subcategory list for a category
    private func subcategoryList(category: StyleCategory) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(category.subcategories.enumerated()), id: \.element.id) { index, subcategory in
                    let styleCount = subcategory.allGroups.reduce(0) { $0 + $1.styles.count }
                    navigationRow(
                        title: subcategory.name,
                        icon: nil,
                        iconColor: .secondary,
                        subtitle: "\(subcategory.allGroups.count) groups · \(styleCount) styles",
                        isFocused: focusedIndex == index
                    ) {
                        currentLevel = .subcategory(category, subcategory)
                        focusedIndex = 0
                    }
                    Divider().padding(.leading, 44)
                }
            }
        }
    }

    // Group list for a subcategory
    private func groupList(subcategory: StyleSubcategory) -> some View {
        let groups = subcategory.allGroups
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if case .subcategory(let cat, _) = currentLevel {
                        navigationRow(
                            title: group.name,
                            icon: nil,
                            iconColor: .secondary,
                            subtitle: "\(group.styles.count) styles",
                            isFocused: focusedIndex == index
                        ) {
                            currentLevel = .group(cat, subcategory, group)
                            focusedIndex = 0
                        }
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    // Styles list (final level)
    private func stylesList(styles: [PromptStyle], isCustom: Bool = false) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(styles.enumerated()), id: \.element.id) { index, style in
                    styleRow(style: style, showCustomBadge: isCustom || style.id.hasPrefix("custom-"), isFocused: focusedIndex == index)
                    Divider().padding(.leading, 44)
                }
            }
        }
    }

    // Enriched root-level category row with tinted icon circle
    private func rootCategoryRow(title: String, icon: String, iconColor: Color, subtitle: String, isFocused: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.prominentFont.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(DS.smallFont)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Navigation row (for drilling down)
    private func navigationRow(title: String, icon: String?, iconColor: Color, subtitle: String, isFocused: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(iconColor)
                        .frame(width: 24)
                } else {
                    Color.clear.frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.bodyFont.weight(.medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(DS.smallFont)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Style row (selectable)
    private func styleRow(style: PromptStyle, showCustomBadge: Bool = false, isFocused: Bool = false) -> some View {
        let isSelected = selectedStyles.wrappedValue.contains(style)
        let isFavorite = appState.ui.favoriteStyleIDs.contains(style.id)

        return HStack(spacing: 8) {
            Button(action: {
                if isSelected {
                    selectedStyles.wrappedValue.remove(style)
                } else {
                    selectedStyles.wrappedValue.insert(style)
                }
            }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(style.name)
                        .font(DS.bodyFont.weight(.medium))
                        .lineLimit(2)

                    if showCustomBadge {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.purple.opacity(0.7))
                    }
                }

                if !style.tags.isEmpty {
                    Text(style.tags.joined(separator: " · "))
                        .font(DS.smallFont)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Prompt preview
                promptPreview(for: style)
            }

            Spacer(minLength: 4)

            Button(action: { appState.ui.toggleFavorite(style.id) }) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundColor(isFavorite ? .yellow : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(isFocused ? Color.accentColor.opacity(0.15) : (isSelected ? Color.accentColor.opacity(0.08) : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        )
        .contentShape(Rectangle())
        .contextMenu {
            if showCustomBadge {
                Button(action: {
                    editingStyle = style
                    showCustomStyleEditor = true
                }) {
                    Label("Edit Style", systemImage: "pencil")
                }
            }

            Button(action: { appState.ui.toggleFavorite(style.id) }) {
                if isFavorite {
                    Label("Remove from Favorites", systemImage: "star.slash")
                } else {
                    Label("Add to Favorites", systemImage: "star")
                }
            }

            if showCustomBadge {
                Divider()
                Button(role: .destructive, action: {
                    appState.ui.deleteCustomStyle(style)
                }) {
                    Label("Delete Style", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Prompt Preview Helper

    @ViewBuilder
    private func promptPreview(for style: PromptStyle) -> some View {
        let cleaned = style.prompt
            .replacingOccurrences(of: "{prompt}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = cleaned.hasPrefix(". ") ? String(cleaned.dropFirst(2)) : cleaned
        if !preview.isEmpty {
            Text(preview)
                .font(DS.captionFont)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            // New custom style button
            Button(action: {
                editingStyle = nil
                showCustomStyleEditor = true
            }) {
                Label("Create Custom", systemImage: "plus.circle")
                    .font(DS.prominentFont.weight(.medium))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundColor(.purple)
            .help("Create a new custom style")

            Button(action: selectRandomStyle) {
                Label("Surprise Me", systemImage: "dice.fill")
                    .font(DS.prominentFont.weight(.medium))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundColor(.orange)
            .help("Add a random style")

            if !selectedStyles.wrappedValue.isEmpty {
                Button(action: { selectedStyles.wrappedValue.removeAll() }) {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(DS.prominentFont.weight(.medium))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            // Selected styles indicator with popover
            if !selectedStyles.wrappedValue.isEmpty {
                stylesIndicator
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(DS.Anim.quick, value: selectedStyles.wrappedValue.isEmpty)
    }

    // MARK: - Styles Indicator

    private var stylesIndicator: some View {
        Button(action: {
            showStylesPopover = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 13, weight: .medium))
                Text("\(selectedStyles.wrappedValue.count) style\(selectedStyles.wrappedValue.count == 1 ? "" : "s")")
                    .font(DS.bodyFont.weight(.medium))
            }
            .foregroundColor(.purple)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.purple.opacity(0.1))
            .cornerRadius(DS.Radius.panel)
        }
        .buttonStyle(.plain)
        .help("View and manage selected styles")
        .popover(isPresented: $showStylesPopover, arrowEdge: .top) {
            selectedStylesPopover
        }
    }

    private var selectedStylesPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Selected Styles")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            // Styles list
            if selectedStyles.wrappedValue.isEmpty {
                Text("No styles selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(selectedStyles.wrappedValue).sorted(by: { $0.name < $1.name }), id: \.id) { style in
                            HStack {
                                Text(style.name)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer()

                                Button(action: {
                                    selectedStyles.wrappedValue.remove(style)
                                    if selectedStyles.wrappedValue.isEmpty {
                                        showStylesPopover = false
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove style")
                                .accessibilityLabel("Remove \(style.name)")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())

                            if style != Array(selectedStyles.wrappedValue).sorted(by: { $0.name < $1.name }).last {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(minWidth: 220, maxWidth: 280)
    }
}

// MARK: - Preview

#if DEBUG
struct StyleBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        StyleBrowserView()
            .environmentObject(AppState())
            .frame(width: 800, height: 500)
    }
}
#endif
