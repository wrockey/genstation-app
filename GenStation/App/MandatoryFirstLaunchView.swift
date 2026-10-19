// MandatoryFirstLaunchView.swift

import SwiftUI

struct MandatoryFirstLaunchView: View {
    @State private var hasAcceptedTerms = false
    @State private var hasScrolledToBottom = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    var onComplete: () -> Void

    private var isCompact: Bool {
        sizeClass == .compact
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: isCompact ? 24 : 32) {
                    // Logo + Welcome
                    headerSection

                    // Key Points
                    keyPointsSection

                    // Legal Notice Card
                    legalSection

                    // Acceptance Toggle
                    acceptanceSection

                    // Privacy Policy Link
                    Link(destination: URL(string: "https://genstation.art/privacy.html") ?? URL(string: "https://genstation.art")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.raised.fill")
                            Text("Privacy Policy")
                        }
                        .font(.subheadline.weight(.medium))
                    }

                    // Buttons
                    buttonSection
                }
                .padding(isCompact ? 20 : 32)
                .frame(maxWidth: 620)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: isCompact ? nil : 500, idealWidth: 600, maxWidth: 700)
        .frame(minHeight: isCompact ? nil : 550, idealHeight: 650, maxHeight: 800)
        .background(Color.systemBackground)
        .interactiveDismissDisabled()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: isCompact ? 80 : 100, height: isCompact ? 80 : 100)
                .clipShape(RoundedRectangle(cornerRadius: isCompact ? 18 : 22))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            Text("Welcome to GenStation")
                .font(isCompact ? .title.bold() : .largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("AI image generation workbench")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, isCompact ? 8 : 16)
    }

    // MARK: - Key Points Section

    private var keyPointsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            keyPoint(icon: "key.fill", text: "Connects to Gemini, Grok, and AI/ML API using your own API keys")
            keyPoint(icon: "dollarsign.circle", text: "We do not sell credits and earn nothing from these services")
            keyPoint(icon: "server.rack", text: "ComfyUI mode requires your own ComfyUI installation")
            keyPoint(icon: "hand.raised.slash.fill", text: "We collect zero personal data")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func keyPoint(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Legal Section

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.secondary)
                Text("Terms of Use")
                    .font(.headline)
            }

            Text(legalText)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Acceptance Section

    private var acceptanceSection: some View {
        Toggle(isOn: $hasAcceptedTerms) {
            VStack(alignment: .leading, spacing: 2) {
                Text("I accept the Terms of Use")
                    .font(.subheadline.weight(.medium))
                Text("I confirm I am 18+ years old")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(.accentColor)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hasAcceptedTerms ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(hasAcceptedTerms ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .animation(DS.Anim.quick, value: hasAcceptedTerms)
    }

    // MARK: - Button Section

    private var buttonSection: some View {
        Group {
            if isCompact {
                // Vertical stack for iPhone
                VStack(spacing: 12) {
                    continueButton
                    declineButton
                }
            } else {
                // Horizontal for larger screens
                HStack(spacing: 16) {
                    declineButton
                    Spacer()
                    continueButton
                }
            }
        }
        .padding(.top, 8)
    }

    private var continueButton: some View {
        Button(action: { onComplete() }) {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: isCompact ? .infinity : 160)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!hasAcceptedTerms)
        .keyboardShortcut(.defaultAction)
    }

    private var declineButton: some View {
        Button(action: { exit(0) }) {
            Text("Decline")
                .font(.headline)
                .frame(maxWidth: isCompact ? .infinity : 120)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .foregroundColor(.red)
        .keyboardShortcut(.escape)
    }

    // MARK: - Legal Text

    private var legalText: String {
        """
        By continuing, you acknowledge and agree to the following:

        NO WARRANTY: GenStation is free, experimental software provided "AS IS" without warranties of any kind, express or implied, including merchantability, fitness for a particular purpose, or non-infringement.

        API CREDITS: Any lost, consumed, rate-limited, or banned API credits are your sole responsibility. The developer is not liable for any financial loss related to third-party API usage.

        USE AT YOUR OWN RISK: You use GenStation entirely at your own risk. The developer shall not be liable for any damages—direct, indirect, incidental, consequential, or punitive—arising from use or inability to use this software.

        THIRD-PARTY SERVICES: GenStation does not host, train, or run any AI models. It forwards your prompts, images, and API keys to third-party services. You are solely responsible for all costs and API access.

        GENERATED CONTENT: All content is produced by third-party services you connect to. You are solely responsible for its legality, copyright compliance, and appropriate use. The developer has no control over and assumes no responsibility for any output, including but not limited to intellectual property infringement.

        LEGAL COMPLIANCE: You must comply with all applicable local, state, national, and international laws regarding your use of this software and any generated content.

        DATA COLLECTION: GenStation collects no personal data, but connected third-party services may log your activity per their own policies.

        COMFYUI: In ComfyUI mode, you are solely responsible for the licensing and legality of any models, LoRAs, or checkpoints you use.

        INDEMNIFICATION: You agree to indemnify, defend, and hold harmless the developer from any claims, losses, or expenses (including attorney fees) arising from your use of this software or generated content.

        LIMITATION OF LIABILITY: In no event shall the developer's total liability exceed zero dollars ($0).

        SEVERABILITY: If any provision of these terms is found unenforceable, the remaining provisions shall remain in full force and effect.

        ENTIRE AGREEMENT: These terms constitute the entire agreement between you and the developer regarding GenStation and supersede any prior agreements.

        MODIFICATIONS: The developer may modify or discontinue GenStation at any time without notice. Continued use after terms updates constitutes acceptance of new terms.

        AGE REQUIREMENT: You represent and warrant that you are at least 18 years of age (or the age of majority in your jurisdiction).

        CONTENT FILTER: GenStation includes a local prompt filter. Additionally, all supported AI providers enforce their own content policies and safety filters. You remain fully responsible for all generated content and compliance with applicable laws.
        """
    }
}

// MARK: - Preview

#if DEBUG
struct MandatoryFirstLaunchView_Previews: PreviewProvider {
    static var previews: some View {
        MandatoryFirstLaunchView(onComplete: {})
            .previewDisplayName("Default")

        MandatoryFirstLaunchView(onComplete: {})
            .previewDevice("iPhone 15")
            .previewDisplayName("iPhone")
    }
}
#endif
