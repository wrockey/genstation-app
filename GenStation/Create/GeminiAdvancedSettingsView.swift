// GeminiAdvancedSettingsView.swift
// Advanced settings for native Gemini API image generation

import SwiftUI
import GenStationCore

struct GeminiAdvancedSettingsView: View {
    @EnvironmentObject var appState: AppState

    private let aspectRatios = ["1:1", "3:2", "2:3", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]
    private let resolutions = ["1K", "2K", "4K"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Aspect Ratio
            VStack(alignment: .leading, spacing: 8) {
                Label("Aspect Ratio", systemImage: "aspectratio")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Picker("Aspect Ratio", selection: aspectRatioBinding) {
                    ForEach(aspectRatios, id: \.self) { ratio in
                        Text(ratio).tag(ratio)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(Color.primary.opacity(0.05)))

            // Resolution (only for models that support it)
            if supportsResolution {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Image Resolution", systemImage: "photo.artframe")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Picker("Resolution", selection: resolutionBinding) {
                        ForEach(resolutions, id: \.self) { res in
                            Text(res).tag(res)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(resolutionDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(Color.primary.opacity(0.05)))
            }

            // Info about current settings
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("These settings are sent with your Gemini image generation requests.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    // MARK: - Bindings

    private var aspectRatioBinding: Binding<String> {
        Binding(
            get: { appState.settings.geminiAdvancedParams.aspectRatio ?? "1:1" },
            set: { appState.settings.geminiAdvancedParams.aspectRatio = $0 }
        )
    }

    private var resolutionBinding: Binding<String> {
        Binding(
            get: { appState.settings.geminiAdvancedParams.geminiResolution ?? "1K" },
            set: { appState.settings.geminiAdvancedParams.geminiResolution = $0 }
        )
    }

    // MARK: - Helpers

    /// Whether this model has a resolution to choose. The same predicate the request builder reads
    /// (`ContentView+Generation.swift`), so the card is drawn exactly when the key ships.
    private var supportsResolution: Bool {
        GeminiClient.supportsImageSize(modelID: appState.settings.selectedGeminiModel)
    }

    private var resolutionDescription: String {
        switch appState.settings.geminiAdvancedParams.geminiResolution ?? "1K" {
        case "1K":
            return "Standard quality (~1024px) - fastest generation"
        case "2K":
            return "High quality (~2048px) - balanced"
        case "4K":
            return "Ultra quality (~4096px) - highest detail, slower"
        default:
            return ""
        }
    }
}

#if DEBUG
struct GeminiAdvancedSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GeminiAdvancedSettingsView()
            .environmentObject(AppState())
            .frame(width: 300)
    }
}
#endif
