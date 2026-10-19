//ContentView+Filter.swift
import Foundation
import SwiftUI
import GenStationCore

extension ContentView {
    static func isPromptSafe(_ prompt: String) -> (isSafe: Bool, offendingPhrases: [String]) {
        PromptSafetyPolicy.isPromptSafe(prompt)
    }
}

// MARK: - Responsive Content Filter Blocked Dialog (iOS + macOS)
struct ContentFilterBlockedView: View {
    let offendingEntries: [(line: Int, prompt: String, phrases: [String])]
    let onDismiss: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var hasMultiple: Bool { offendingEntries.count > 1 }
    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.multicolor)
                
                VStack(spacing: 16) {
                    Text("Content Blocked")
                        .font(.largeTitle.bold())
                    
                    Text("One or more prompts were blocked by the safety filter to prevent harmful content.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                
                blockedPromptsSection
                
                Text("Tip: Use neutral, descriptive language. Avoid explicit, violent, or discriminatory terms.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            }
            .padding(isCompact ? 20 : 32)
            // This padding ensures the last item isn't hidden behind the button
            .padding(.bottom, 20)
        }
        // This frame sets the *scrollable area* size
        .frame(
            minHeight: {
                #if os(macOS)
                return 600
                #else
                let idiom = UIDevice.current.userInterfaceIdiom
                if idiom == .pad {
                    let orientation = UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?
                        .interfaceOrientation ?? .portrait
                    
                    return orientation.isPortrait ? 680 : nil
                }
                return nil
                #endif
            }(),
            maxHeight: {
                return .infinity
            }()
        )
        .background(Color.systemBackground)
        .cornerRadius(DS.Radius.modal)
        .shadow(radius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.modal)
                .stroke(Color.separator.opacity(0.3), lineWidth: 1)
        )
        .interactiveDismissDisabled()
    }
    
    private var blockedPromptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hasMultiple ? "Blocked Prompts:" : "Blocked Prompt:")
                .font(.headline)
                .padding(.horizontal)
            
            LazyVStack(spacing: 12) {
                ForEach(offendingEntries, id: \.line) { entry in
                    PromptRow(entry: entry)
                }
            }
            .padding(20)
            .background(Color.systemBackground)
            .cornerRadius(16)
            .padding(.horizontal)
        }
    }
}

struct PromptRow: View {
    let entry: (line: Int, prompt: String, phrases: [String])
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Prompt \(entry.line)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            Text(entry.prompt)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(4)
            
            if !entry.phrases.isEmpty {
                Text("Detected: \(entry.phrases.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .cornerRadius(DS.Radius.panel)
    }

    
}

// MARK: - Prompt Row (Improved for Mobile)




extension String {
    func truncate(to length: Int) -> String {
        count > length ? String(prefix(length)) + "…" : self
    }
}

// MARK: - View Extension (triggers the pretty dialog)
extension View {
    func contentFilterAlert(errorItem: Binding<AlertError?>) -> some View {
            self
                // Show pretty full-screen sheet for content filter errors
                .sheet(item: Binding<PresentedModal?>(
                    get: {
                        guard let error = errorItem.wrappedValue,
                              error.message.contains("Prompt contains inappropriate content"),
                              let full = error.fullMessage,
                              !full.isEmpty else { return nil }
                        
                        let entries = parseBlockedPrompts(from: full)
                        return .contentFilterBlocked(entries)
                    },
                    set: { _ in errorItem.wrappedValue = nil }
                )) { modal in
                    if case .contentFilterBlocked(let entries) = modal {
                        ContentFilterBlockedView(offendingEntries: entries) {
                            errorItem.wrappedValue = nil
                        }
                    }
                }
                // Keep regular alert for all OTHER errors
                .alert(item: Binding<AlertError?>(
                    get: {
                        guard let error = errorItem.wrappedValue else { return nil }
                        return error.message.contains("Prompt contains inappropriate content") ? nil : error
                    },
                    set: { errorItem.wrappedValue = $0 }
                )) { error in
                    Alert(title: Text("Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
                }
        }
        
        private func parseBlockedPrompts(from fullMessage: String) -> [(line: Int, prompt: String, phrases: [String])] {
            // Same as before — unchanged
            // (Keep your existing parseBlockedPrompts function here)
            guard !fullMessage.isEmpty else {
                return [(1, "One or more prompts were blocked", ["inappropriate content"])]
            }
            
            var results: [(Int, String, [String])] = []
            let lines = fullMessage.split(separator: "\n")
            
            var currentLine = 0
            var currentPrompt = ""
            var currentPhrases: [String] = []
            
            for line in lines {
                if line.contains("Line ") && line.contains(":") {
                    if currentLine > 0 {
                        results.append((currentLine, currentPrompt, currentPhrases))
                    }
                    let parts = line.split(separator: ":", maxSplits: 2)
                    if parts.count >= 2,
                       let num = Int(parts[0].replacingOccurrences(of: "Line ", with: "").trimmingCharacters(in: .whitespaces)) {
                        currentLine = num
                        let rest = String(parts[1...].joined(separator: ":")).trimmingCharacters(in: .whitespaces)
                        if rest.contains("→") {
                            let subparts = rest.split(separator: "→", maxSplits: 1)
                            currentPrompt = String(subparts[0]).trimmingCharacters(in: .whitespaces)
                            currentPhrases = String(subparts[1]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        } else {
                            currentPrompt = rest
                            currentPhrases = ["prohibited content"]
                        }
                    }
                }
            }
            if currentLine > 0 {
                results.append((currentLine, currentPrompt, currentPhrases))
            }
            
            return results.isEmpty ? [(1, "Blocked prompt", ["content violation"])] : results
        }
}
