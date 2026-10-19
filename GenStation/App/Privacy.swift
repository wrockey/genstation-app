// Privacy.swift (simplified without #available to avoid version errors; use introspection for all iOS)
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum PrivacyService: String, Identifiable {
    case gemini = "Gemini"
    case grok = "Grok"
    case aimlapi = "AI/ML API"
    case imgbb = "ImgBB"

    var id: Self { self }

    /// UserDefaults key for "don't show again" consent
    var consentKey: String {
        "dontShow\(rawValue.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: " ", with: ""))Privacy"
    }

    /// Whether the user has already consented to this service's privacy notice
    var hasConsented: Bool {
        AppStorageContext.defaults.bool(forKey: consentKey)
    }

    var policyURL: String {
        switch self {
        case .gemini: return "https://policies.google.com/privacy"
        case .grok: return "https://x.ai/legal/privacy-policy"
        case .aimlapi: return "https://aimlapi.com/privacy-policy"
        case .imgbb: return "https://imgbb.com/privacy"
        }
    }

    var message: String {
        switch self {
        case .gemini:
            return """
            Your prompt, any input images, and your API key will be sent to Google for processing. \
            GenStation does not store or log this data—your API key is stored locally in the system Keychain. \
            Data may be transmitted across international borders. \
            Google may retain or use your data per their privacy policy. \
            GenStation has no access to or control over your data once sent. \
            For data deletion or privacy concerns, contact Google directly per their privacy policy.
            """
        case .grok:
            return """
            Your prompt and your API key will be sent to xAI for processing. \
            GenStation does not store or log this data—your API key is stored locally in the system Keychain. \
            Data may be transmitted across international borders. \
            xAI may retain or use your data per their privacy policy. \
            GenStation has no access to or control over your data once sent. \
            For data deletion or privacy concerns, contact xAI directly per their privacy policy.
            """
        case .aimlapi:
            return """
            Your prompt, any input images, and your API key will be sent to AI/ML API for processing. \
            AI/ML API routes requests to third-party model providers (e.g., FLUX, Kling, Stable Diffusion)—your data may be forwarded to these providers. \
            GenStation does not store or log this data—your API key is stored locally in the system Keychain. \
            Data may be transmitted across international borders. \
            GenStation has no access to or control over your data once sent. \
            For data deletion, retention details, or privacy concerns, contact AI/ML API directly per their privacy policy.
            """
        case .imgbb:
            return """
            Input images and your API key will be uploaded to ImgBB to obtain public (unlisted) URLs for the AI model. \
            These images are publicly viewable by anyone with the link and are set to expire after 10 minutes. \
            Your API key is stored locally in the system Keychain. \
            GenStation does not retain the images or URLs. Data may be transmitted across international borders. \
            GenStation has no access to or control over your data once sent. \
            For data deletion or privacy concerns, contact ImgBB directly per their privacy policy.
            """
        }
    }
}

struct PrivacyNoticeSheet: View {
    let service: PrivacyService
    let onDismiss: (Bool, Bool) -> Void

    @State private var dontShowAgain = false

    var body: some View {
        VStack(spacing: 24) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                    .symbolRenderingMode(.hierarchical)

                Text("\(service.rawValue) Privacy Notice")
                    .font(.title2.bold())
                    .foregroundColor(.primary)

                Text(service.message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let url = URL(string: service.policyURL) {
                    Link("View Privacy Policy", destination: url)
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.regular)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }

                Checkbox(isChecked: $dontShowAgain, label: "Don't show again")

                HStack(spacing: 12) {
                    Button("Cancel") {
                        onDismiss(false, dontShowAgain)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .foregroundColor(.secondary)
                    .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0.5)

                    Button("Continue") {
                        onDismiss(true, dontShowAgain)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(.blue)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
            }
            .padding(24)
            #if os(macOS)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
            #elseif os(iOS)
            .background(Color(UIColor.systemBackground).opacity(0.95))
            #endif
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            .frame(minWidth: 400, maxWidth: 450, minHeight: 250)  // If extra arg error, remove minHeight or check SwiftUI version; it's valid in SwiftUI 5+
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
    }
}

struct Checkbox: View {
    @Binding var isChecked: Bool
    let label: String

    var body: some View {
        Button(action: {
            isChecked.toggle()
        }) {
            HStack {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? .blue : .gray)
                    .font(.system(size: 20))
                Text(label)
                    .font(.subheadline.italic())
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

// MARK: - Clear Background for FullScreenCover
#if os(iOS)
struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#elseif os(macOS)
struct ClearBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

extension PrivacyService {
    var displayName: String {
        switch self {
        case .gemini:  return "Google Gemini"
        case .grok:    return "xAI Grok"
        case .aimlapi: return "AI/ML API"
        case .imgbb:   return "ImgBB"
        }
    }

    var subtitle: String {
        switch self {
        case .gemini:  return "Your prompts & images are sent to Google"
        case .grok:    return "Your prompts are sent to xAI"
        case .aimlapi: return "Routes to third-party model providers"
        case .imgbb:   return "Warning: Images become temporarily public"
        }
    }

    var icon: String {
        switch self {
        case .gemini:  return "brain.head.profile"
        case .grok:    return "flame.fill"
        case .aimlapi: return "network"
        case .imgbb:   return "photo.on.rectangle.angled"
        }
    }

    var accentColor: Color {
        switch self {
        case .gemini:  return .blue
        case .grok:    return .orange
        case .aimlapi: return .purple
        case .imgbb:   return .red
        }
    }
}
