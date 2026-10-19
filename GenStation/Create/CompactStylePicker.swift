// CompactStylePicker.swift
// Inline style picker for use in popovers/sheets without leaving current context

import SwiftUI

struct CompactStylePicker: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: StyleCategory?
    @State private var selectedSubcategory: StyleSubcategory?
    @State private var selectedGroup: StyleGroup?
    @State private var searchText: String = ""
    @State private var styleDatabase: StyleDatabase?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Styles")
                    .font(.headline)

                Spacer()

                if !appState.ui.selectedStyles.isEmpty {
                    Text("\(appState.ui.selectedStyles.count) selected")
                        .font(.caption)
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(DS.Radius.standard)
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
            }
            .padding()

            Divider()

            // Search with random style button
            HStack(spacing: 8) {
                // Random style button
                Button(action: selectRandomStyle) {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .help("Add random style")

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search styles...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(DS.Radius.standard)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Content
            if let database = styleDatabase {
                if !searchText.isEmpty {
                    // Search results
                    searchResultsView(database: database)
                } else {
                    // Browse mode
                    #if os(iOS)
                    navigationBrowser(database: database)
                    #else
                    columnBrowser(database: database)
                    #endif
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Selected styles footer
            if !appState.ui.selectedStyles.isEmpty {
                Divider()
                selectedStylesFooter
            }
        }
        .frame(minWidth: 400, idealWidth: 500, maxWidth: 600)
        .frame(minHeight: 400, idealHeight: 500, maxHeight: 600)
        .onAppear {
            loadStyleDatabase()
        }
    }

    // MARK: - Search Results

    private func searchResultsView(database: StyleDatabase) -> some View {
        let results = searchStyles(in: database, query: searchText)

        return ScrollView {
            LazyVStack(spacing: 4) {
                if results.isEmpty {
                    Text("No styles found")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(results, id: \.id) { style in
                        styleRow(style)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func searchStyles(in database: StyleDatabase, query: String) -> [PromptStyle] {
        let lowercasedQuery = query.lowercased()
        var results: [PromptStyle] = []

        for category in database.categories {
            for subcategory in category.subcategories {
                for group in subcategory.groups ?? [] {
                    for style in group.styles {
                        if style.name.lowercased().contains(lowercasedQuery) ||
                           style.tags.contains(where: { $0.lowercased().contains(lowercasedQuery) }) {
                            results.append(style)
                        }
                    }
                }
            }
        }

        return results
    }

    // MARK: - iOS Navigation Browser

    #if os(iOS)
    private func navigationBrowser(database: StyleDatabase) -> some View {
        NavigationStack {
            List(database.categories, id: \.id) { category in
                NavigationLink(value: category) {
                    Label(category.name, systemImage: category.icon)
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: StyleCategory.self) { category in
                List(category.subcategories, id: \.id) { subcategory in
                    NavigationLink(value: subcategory) {
                        Text(subcategory.name)
                    }
                }
                .navigationTitle(category.name)
                .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(for: StyleSubcategory.self) { subcategory in
                List(subcategory.groups ?? [], id: \.id) { group in
                    NavigationLink(value: group) {
                        Text(group.name)
                    }
                }
                .navigationTitle(subcategory.name)
                .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(for: StyleGroup.self) { group in
                List(group.styles, id: \.id) { style in
                    styleRow(style)
                }
                .navigationTitle(group.name)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    #endif

    // MARK: - macOS Column Browser

    #if os(macOS)
    private func columnBrowser(database: StyleDatabase) -> some View {
        HStack(spacing: 0) {
            // Categories column
            VStack(alignment: .leading, spacing: 0) {
                Text("Category")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(database.categories, id: \.id) { category in
                            categoryRow(category)
                        }
                    }
                    .padding(4)
                }
            }
            .frame(width: 140)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Subcategories/Groups column
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedCategory != nil ? "Subcategory" : "")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        if let category = selectedCategory {
                            ForEach(category.subcategories, id: \.id) { subcategory in
                                subcategoryRow(subcategory)
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .frame(width: 140)
            .background(Color.primary.opacity(0.02))

            Divider()

            // Styles column
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedSubcategory != nil ? "Styles" : "")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        if let subcategory = selectedSubcategory {
                            ForEach(subcategory.groups ?? [], id: \.id) { group in
                                groupSection(group)
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .frame(minWidth: 180)
        }
    }

    private func categoryRow(_ category: StyleCategory) -> some View {
        Button(action: {
            selectedCategory = category
            selectedSubcategory = nil
            selectedGroup = nil
        }) {
            HStack {
                Image(systemName: category.icon)
                    .frame(width: 20)
                Text(category.name)
                    .lineLimit(1)
                Spacer()
                if selectedCategory?.id == category.id {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selectedCategory?.id == category.id ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(DS.Radius.small)
        }
        .buttonStyle(.plain)
    }

    private func subcategoryRow(_ subcategory: StyleSubcategory) -> some View {
        Button(action: {
            selectedSubcategory = subcategory
            selectedGroup = nil
        }) {
            HStack {
                Text(subcategory.name)
                    .lineLimit(1)
                Spacer()
                if selectedSubcategory?.id == subcategory.id {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selectedSubcategory?.id == subcategory.id ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(DS.Radius.small)
        }
        .buttonStyle(.plain)
    }

    private func groupSection(_ group: StyleGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.name)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 8)

            ForEach(group.styles, id: \.id) { style in
                styleRow(style)
            }
        }
    }
    #endif

    // MARK: - Style Row

    private func styleRow(_ style: PromptStyle) -> some View {
        let isSelected = appState.ui.selectedStyles.contains(style)

        return Button(action: {
            if isSelected {
                appState.ui.selectedStyles.remove(style)
            } else {
                appState.ui.selectedStyles.insert(style)
            }
        }) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .purple : .secondary)

                Text(style.name)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.purple.opacity(0.1) : Color.clear)
            .cornerRadius(DS.Radius.small)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected Styles Footer

    private var selectedStylesFooter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(appState.ui.selectedStyles).sorted(by: { $0.name < $1.name }), id: \.id) { style in
                    HStack(spacing: 4) {
                        Text(style.name)
                            .font(.caption)
                            .lineLimit(1)

                        Button(action: {
                            appState.ui.selectedStyles.remove(style)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(DS.Radius.panel)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Random Style

    private func selectRandomStyle() {
        guard let database = styleDatabase else { return }

        // Collect all styles from the database
        var allStyles: [PromptStyle] = []
        for category in database.categories {
            for subcategory in category.subcategories {
                for group in subcategory.groups ?? [] {
                    allStyles.append(contentsOf: group.styles)
                }
            }
        }

        // Pick a random style and add it
        if let randomStyle = allStyles.randomElement() {
            appState.ui.selectedStyles.insert(randomStyle)
        }
    }

    // MARK: - Data Loading

    private func loadStyleDatabase() {
        guard let url = Bundle.main.url(forResource: "prompt_styles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let database = try? JSONDecoder().decode(StyleDatabase.self, from: data) else {
            return
        }
        styleDatabase = database
    }
}

// MARK: - Preview

#if DEBUG
struct CompactStylePicker_Previews: PreviewProvider {
    static var previews: some View {
        CompactStylePicker()
            .environmentObject(AppState())
    }
}
#endif
