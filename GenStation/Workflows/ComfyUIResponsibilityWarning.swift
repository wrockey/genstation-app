//  ComfyUIResponsibilityWarning.swift

import SwiftUI

struct ComfyUIResponsibilityWarning: View {
    @AppStorage("comfyUIWarningAccepted", store: AppStorageContext.defaults) private var accepted = false
    @AppStorage("comfyUIWarningDeclined", store: AppStorageContext.defaults) private var declined = false
    @State private var hasAcceptedTerms = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var onComplete: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: isCompact ? 16 : 24) {
                // MARK: - Icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: isCompact ? 48 : 60))
                    .foregroundColor(.orange)

                // MARK: - Title
                VStack(spacing: 8) {
                    Text("ComfyUI Mode")
                        .font(isCompact ? .title3.bold() : .title2.bold())
                        .multilineTextAlignment(.center)

                    Text("ComfyUI runs on your own server with models you control. GenStation has no ability to filter or moderate this content.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, isCompact ? 16 : 24)

                // MARK: - Prohibited Content Box
                VStack(alignment: .leading, spacing: 12) {
                    Label("Prohibited Content", systemImage: "xmark.shield.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.red)

                    VStack(alignment: .leading, spacing: 8) {
                        prohibitedItem("Nudity or sexually explicit material")
                        prohibitedItem("Violence, gore, or hate symbols")
                        prohibitedItem("Child sexual abuse material (CSAM)")
                    }

                    Text("CSAM is illegal worldwide and strictly prohibited. Zero tolerance.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .fill(Color.red.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, isCompact ? 16 : 24)

                // MARK: - Legal Terms
                VStack(alignment: .leading, spacing: 8) {
                    Text("By enabling ComfyUI mode, you agree that:")
                        .font(.subheadline.weight(.medium))

                    VStack(alignment: .leading, spacing: 6) {
                        legalItem("You are solely responsible for all content generated")
                        legalItem("You will comply with all applicable laws in your jurisdiction")
                        legalItem("You are responsible for licensing of any models, LoRAs, or checkpoints you use")
                        legalItem("You agree to indemnify and hold harmless the developer from any claims arising from your use")
                        legalItem("You confirm you are at least 18 years old")
                    }

                    Text("These terms supplement the Terms of Use you accepted at first launch.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, isCompact ? 16 : 24)

                // MARK: - Checkbox
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: hasAcceptedTerms ? "checkmark.square.fill" : "square")
                        .foregroundColor(hasAcceptedTerms ? .accentColor : .secondary)
                        .font(.title3)

                    Text("I understand and accept full responsibility for all content generated in ComfyUI mode")
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .fill(hasAcceptedTerms ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .stroke(hasAcceptedTerms ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                )
                .padding(.horizontal, isCompact ? 16 : 24)
                .contentShape(Rectangle())
                .onTapGesture { hasAcceptedTerms.toggle() }

                // MARK: - Buttons
                Group {
                    if isCompact {
                        // Vertical stack for compact screens
                        VStack(spacing: 12) {
                            enableButton
                            declineButton
                        }
                    } else {
                        // Horizontal for larger screens
                        HStack(spacing: 16) {
                            declineButton
                            enableButton
                        }
                    }
                }
                .padding(.horizontal, isCompact ? 16 : 24)
                .padding(.top, 8)
            }
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Color.systemBackground)
        .cornerRadius(DS.Radius.modal)
        .shadow(radius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.modal)
                .stroke(Color.separator.opacity(0.3), lineWidth: 1)
        )
        .interactiveDismissDisabled()
        .zIndex(11)
    }

    // MARK: - Helper Views

    private func prohibitedItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }

    private func legalItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var enableButton: some View {
        Button(action: {
            if hasAcceptedTerms {
                accepted = true
                onComplete()
            }
        }) {
            Text("Enable ComfyUI")
                .font(.headline)
                .frame(maxWidth: isCompact ? .infinity : 160)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(hasAcceptedTerms ? .blue : .gray)
        .disabled(!hasAcceptedTerms)
        .keyboardShortcut(.defaultAction)
    }

    private var declineButton: some View {
        Button(action: {
            declined = true
            onComplete()
        }) {
            Text("Decline")
                .font(.headline)
                .frame(maxWidth: isCompact ? .infinity : 120)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .keyboardShortcut(.cancelAction)
    }
}
