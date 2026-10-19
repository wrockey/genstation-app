// ImageDescriptionSheet.swift
// GenStation
//
// Sheet view for displaying AI-generated image descriptions

import SwiftUI

struct ImageDescriptionSheet: View {
    let description: String
    let onUseAsPrompt: () -> Void
    let onCopy: () -> Void
    let onDismiss: () -> Void

    @State private var showCopiedToast = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)

                    Text("Image Description")
                        .font(.title2.bold())
                }
                .padding(.top)

                // Description text
                ScrollView {
                    Text(description)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.panel))

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        onCopy()
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedToast = false
                        }
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onUseAsPrompt()
                    } label: {
                        Label("Use as Prompt", systemImage: "text.cursor")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .overlay {
                if showCopiedToast {
                    VStack {
                        LiquidGlassToast(message: "Copied to clipboard")
                            .transition(.toastTransition)
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .animation(.easeInOut, value: showCopiedToast)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(macOS)
        .frame(width: 500, height: 450)
        #endif
    }
}

#Preview {
    ImageDescriptionSheet(
        description: "A serene mountain landscape at golden hour, with snow-capped peaks reflecting warm sunlight. A winding river flows through the valley below, surrounded by lush pine forests. The sky features soft gradient colors from deep orange near the horizon to pale blue above, with wispy clouds catching the last rays of daylight. The composition emphasizes depth with foreground wildflowers, midground trees, and distant mountains creating natural layers.",
        onUseAsPrompt: { },
        onCopy: { },
        onDismiss: { }
    )
}
