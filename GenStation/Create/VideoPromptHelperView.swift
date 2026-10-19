// VideoPromptHelperView.swift
// Sheet view for building video prompts with templates and form fields

import SwiftUI
import GenStationCore

struct VideoPromptHelperView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let currentModelId: String
    let onApply: (String) -> Void

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    // MARK: - State

    // Template selection
    @State private var selectedTemplate: VideoPromptTemplate? = nil

    // Form fields
    @State private var subject: String = ""
    @State private var action: String = ""
    @State private var selectedCamera: CameraMovement? = nil
    @State private var selectedStyle: VideoStylePreset? = nil
    @State private var selectedMood: VideoMood? = nil
    @State private var selectedLighting: VideoLighting? = nil
    @State private var customDetails: String = ""
    @State private var audioDescription: String = ""  // For audio-capable models

    // Preview
    @State private var generatedPrompt: String = ""
    @State private var isEditing: Bool = false

    // Model info — the display name comes from the catalog (one place, and after Stage 3 it is the
    // vendor's own `info.name`); the audio flag and the tips come from the prompt-guidance table.
    private var modelDisplayName: String {
        VideoWorkflowGuide.guide(for: currentModelId)?.title ?? Catalog.resolve(currentModelId).displayName
    }

    private var guidance: VideoPromptGuidance {
        VideoPromptGuidance.guidance(for: currentModelId)
    }

    private var supportsAudio: Bool {
        guidance.supportsAudio && (currentModelId == GrokVideoClient.model
            ? appState.settings.grokVideoAudio
            : currentModelId == "minimax/h3-max" || appState.settings.aimlAdvancedParams.generateAudio != false)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let guide = VideoWorkflowGuide.guide(for: currentModelId) {
                        Text(guide.summary).font(.subheadline).foregroundStyle(.secondary)
                        if !appState.ui.imageSlots.isEmpty {
                            Text("Your frame images establish the appearance. Focus the prompt on motion, timing, and the transition between frames.").font(.caption)
                        }
                    }
                    templateSection
                    formFieldsSection

                    if supportsAudio {
                        audioSection
                    }

                    previewSection

                    tipsSection
                }
                .padding(isCompact ? 16 : 20)
            }

            Divider()

            footer
        }
        .frame(minWidth: isCompact ? nil : 450, idealWidth: isCompact ? nil : 550, maxWidth: isCompact ? .infinity : 650)
        .frame(minHeight: isCompact ? nil : 550, idealHeight: isCompact ? nil : 650, maxHeight: isCompact ? .infinity : 800)
        .onChange(of: subject) { _ in updatePromptPreview() }
        .onChange(of: action) { _ in updatePromptPreview() }
        .onChange(of: selectedCamera) { _ in updatePromptPreview() }
        .onChange(of: selectedStyle) { _ in updatePromptPreview() }
        .onChange(of: selectedMood) { _ in updatePromptPreview() }
        .onChange(of: selectedLighting) { _ in updatePromptPreview() }
        .onChange(of: customDetails) { _ in updatePromptPreview() }
        .onChange(of: audioDescription) { _ in updatePromptPreview() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Video Prompt Helper")
                        .font(.headline)
                    Text(modelDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: "video.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Template Section

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start with a Template")
                .font(.subheadline.weight(.semibold))

            // Two rows of 3 templates each
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(VideoPromptTemplate.allTemplates) { template in
                    templateCard(template)
                }
            }
        }
    }

    private func templateCard(_ template: VideoPromptTemplate) -> some View {
        let isSelected = selectedTemplate?.id == template.id

        return Button(action: {
            selectedTemplate = template
            applyTemplate(template)
        }) {
            VStack(spacing: 6) {
                Image(systemName: template.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .orange)

                Text(template.name)
                    .font(.caption.weight(.medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(isSelected ? Color.orange : Color.orange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .stroke(Color.orange.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(template.description)
    }

    private func applyTemplate(_ template: VideoPromptTemplate) {
        // Only set pickers, not text fields (user fills those in)
        selectedCamera = CameraMovement.allMovements.first { $0.id == template.suggestedCamera }
        selectedMood = VideoMood.allMoods.first { $0.id == template.suggestedMood }
        selectedLighting = VideoLighting.allLighting.first { $0.id == template.suggestedLighting }

        updatePromptPreview()
    }

    // MARK: - Form Fields Section

    private var formFieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Build Your Prompt")
                .font(.subheadline.weight(.semibold))

            // Subject field
            VStack(alignment: .leading, spacing: 6) {
                Text("Subject")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                TextField("What is the main subject? (e.g., a majestic eagle)", text: $subject)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(DS.Radius.standard)
            }

            // Action field
            VStack(alignment: .leading, spacing: 6) {
                Text("Action / Motion")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                TextField("What happens? (e.g., soaring through clouds)", text: $action)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(DS.Radius.standard)
            }

            // Picker row 1
            HStack(spacing: 12) {
                // Camera Movement
                VStack(alignment: .leading, spacing: 6) {
                    Text("Camera")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    Picker("Camera", selection: $selectedCamera) {
                        Text("None").tag(nil as CameraMovement?)
                        ForEach(CameraMovement.allMovements) { movement in
                            Text(movement.name).tag(movement as CameraMovement?)
                        }
                    }
                    .labelsHidden()
                    #if os(macOS)
                    .frame(maxWidth: .infinity)
                    #endif
                }

                // Style
                VStack(alignment: .leading, spacing: 6) {
                    Text("Style")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    Picker("Style", selection: $selectedStyle) {
                        Text("None").tag(nil as VideoStylePreset?)
                        ForEach(VideoStylePreset.allStyles) { style in
                            Text(style.name).tag(style as VideoStylePreset?)
                        }
                    }
                    .labelsHidden()
                    #if os(macOS)
                    .frame(maxWidth: .infinity)
                    #endif
                }
            }

            // Picker row 2
            HStack(spacing: 12) {
                // Mood
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mood")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    Picker("Mood", selection: $selectedMood) {
                        Text("None").tag(nil as VideoMood?)
                        ForEach(VideoMood.allMoods) { mood in
                            Text(mood.name).tag(mood as VideoMood?)
                        }
                    }
                    .labelsHidden()
                    #if os(macOS)
                    .frame(maxWidth: .infinity)
                    #endif
                }

                // Lighting
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lighting")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    Picker("Lighting", selection: $selectedLighting) {
                        Text("None").tag(nil as VideoLighting?)
                        ForEach(VideoLighting.allLighting) { lighting in
                            Text(lighting.name).tag(lighting as VideoLighting?)
                        }
                    }
                    .labelsHidden()
                    #if os(macOS)
                    .frame(maxWidth: .infinity)
                    #endif
                }
            }

            // Custom details
            VStack(alignment: .leading, spacing: 6) {
                Text("Additional Details (optional)")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                TextField("Any extra details, colors, specific instructions...", text: $customDetails)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(DS.Radius.standard)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: DS.Radius.panel).fill(Color.primary.opacity(0.03)))
    }

    // MARK: - Audio Section (for Veo 3.1, Sora 2)

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.orange)
                Text("Audio Description")
                    .font(.subheadline.weight(.semibold))

                Text("(This model supports audio)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField("Describe sounds: birdsong, wind, footsteps, ambient music...", text: $audioDescription)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(DS.Radius.standard)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.standard)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )

            Text("Describe the audio you want generated alongside the video.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: DS.Radius.panel).fill(Color.orange.opacity(0.05)))
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button(action: { isEditing.toggle() }) {
                    Label(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isEditing {
                TextEditor(text: $generatedPrompt)
                    .font(.body)
                    .padding(8)
                    .frame(minHeight: 100, maxHeight: 150)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(DS.Radius.standard)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.standard)
                            .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                    )
            } else {
                Text(generatedPrompt.isEmpty ? "Fill in the fields above to generate a prompt..." : generatedPrompt)
                    .font(.body)
                    .foregroundColor(generatedPrompt.isEmpty ? .secondary : .primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(DS.Radius.standard)
            }
        }
    }

    // MARK: - Tips Section

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Tips for \(modelDisplayName)")
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(guidance.tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(tip)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: DS.Radius.panel).fill(Color.yellow.opacity(0.08)))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Clear All") {
                clearForm()
            }
            .foregroundColor(.secondary)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Apply to Prompt") {
                onApply(generatedPrompt)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(generatedPrompt.isEmpty)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func updatePromptPreview() {
        var parts: [String] = []

        // Subject + Action (core)
        if !subject.isEmpty {
            if !action.isEmpty {
                parts.append("\(subject), \(action)")
            } else {
                parts.append(subject)
            }
        } else if !action.isEmpty {
            parts.append(action)
        }

        // Camera movement
        if let camera = selectedCamera {
            parts.append("\(camera.name.lowercased()) camera movement")
        }

        // Style
        if let style = selectedStyle {
            parts.append("\(style.name.lowercased()) style")
        }

        // Mood
        if let mood = selectedMood {
            parts.append("\(mood.name.lowercased()) mood")
        }

        // Lighting
        if let lighting = selectedLighting {
            parts.append("\(lighting.name.lowercased()) lighting")
        }

        // Custom details
        if !customDetails.isEmpty {
            parts.append(customDetails)
        }

        // Audio description (for supported models)
        if supportsAudio && !audioDescription.isEmpty {
            parts.append("Audio: \(audioDescription)")
        }

        generatedPrompt = parts.joined(separator: ". ") + (parts.isEmpty ? "" : ".")
    }

    private func clearForm() {
        selectedTemplate = nil
        subject = ""
        action = ""
        selectedCamera = nil
        selectedStyle = nil
        selectedMood = nil
        selectedLighting = nil
        customDetails = ""
        audioDescription = ""
        generatedPrompt = ""
    }
}

// MARK: - Preview

#if DEBUG
struct VideoPromptHelperView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPromptHelperView(
            currentModelId: "google/veo-3.1-i2v-fast",
            onApply: { _ in }
        )
        .environmentObject(AppState())
    }
}
#endif
