// CustomStyleEditorView.swift
// Sheet-based editor for creating and editing custom prompt styles

import SwiftUI

struct CustomStyleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    // Edit mode: pass existing style to edit, nil for new
    let existingStyle: PromptStyle?
    let onSave: (PromptStyle) -> Void

    @State private var name: String = ""
    @State private var styleDescription: String = ""
    @State private var negativePrompt: String = ""
    @State private var tagsText: String = ""

    // Preview
    @State private var samplePrompt: String = "a cat sitting on a windowsill"

    private var isEditing: Bool { existingStyle != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !styleDescription.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var previewPrompt: String {
        let base = samplePrompt.trimmingCharacters(in: .whitespaces)
        let style = styleDescription.trimmingCharacters(in: .whitespaces)
        if base.isEmpty { return style }
        if style.isEmpty { return base }
        return "\(base)\n\(style)"
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            formContent
                .navigationTitle(isEditing ? "Edit Style" : "New Custom Style")
                .navigationBarTitleDisplayMode(.inline)
                .keyboardDoneButton()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveStyle() }
                            .disabled(!canSave)
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Style" : "New Custom Style")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { saveStyle() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSave)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            }
            .padding()

            Divider()

            formContent
        }
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 600)
        .frame(minHeight: 500, idealHeight: 560, maxHeight: 700)
        #endif
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Name field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)

                    TextField("e.g., Cinematic Mood", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // Style description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Style Description")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)

                    Text("Describe the visual style, mood, lighting, or technique")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $styleDescription)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 120)
                        .padding(4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(DS.Radius.standard)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.standard)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )

                    Text("Example: cinematic lighting, dramatic shadows, film grain, moody atmosphere, professional color grading")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }

                // Negative prompt (optional)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Negative Prompt")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Text("(optional)")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    TextEditor(text: $negativePrompt)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 80)
                        .padding(4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(DS.Radius.standard)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.standard)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )

                    Text("Things to avoid in the generated image")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Tags (optional)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tags")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Text("(optional)")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    TextField("e.g., cinematic, mood, film", text: $tagsText)
                        .textFieldStyle(.roundedBorder)

                    Text("Comma-separated tags for searching")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .padding(.vertical, 8)

                // Live preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Sample prompt:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("sample prompt", text: $samplePrompt)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Result:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(previewPrompt)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.purple.opacity(0.08))
                            .cornerRadius(DS.Radius.small)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if let style = existingStyle {
                name = style.name
                // Strip {prompt} placeholder if present (for editing bundled styles as custom)
                styleDescription = style.prompt
                    .replacingOccurrences(of: "{prompt}", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if styleDescription.hasPrefix(". ") {
                    styleDescription = String(styleDescription.dropFirst(2))
                }
                negativePrompt = style.negativePrompt
                tagsText = style.tags.joined(separator: ", ")
            }
        }
    }

    private func saveStyle() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = styleDescription.trimmingCharacters(in: .whitespaces)
        let trimmedNegative = negativePrompt.trimmingCharacters(in: .whitespaces)

        // Parse tags
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Generate ID for new styles, keep existing ID for edits
        let styleId = existingStyle?.id ?? "custom-\(UUID().uuidString)"

        let newStyle = PromptStyle(
            id: styleId,
            name: trimmedName,
            prompt: trimmedDescription,  // No {prompt} placeholder needed
            negativePrompt: trimmedNegative,
            tags: tags
        )

        onSave(newStyle)
        dismiss()
    }
}

// MARK: - Preview

#if DEBUG
struct CustomStyleEditorView_Previews: PreviewProvider {
    static var previews: some View {
        // New style
        CustomStyleEditorView(existingStyle: nil) { _ in }

        // Edit existing
        CustomStyleEditorView(
            existingStyle: PromptStyle(
                id: "test-1",
                name: "Test Style",
                prompt: "cinematic lighting, moody",
                negativePrompt: "blurry",
                tags: ["mood", "cinematic"]
            )
        ) { _ in }
    }
}
#endif
