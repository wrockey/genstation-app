#if os(macOS)
import AppKit
import SwiftUI

/// Owns the decision independently of any window. Closing a review never
/// resumes its caller; only an explicit decision (or revoked access) does.
@MainActor
final class AgentApprovalCenter: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AgentApprovalCenter()
    struct Request: Identifiable {
        let id: String
        let requestID: String?
        let requestLabel: String?
        let createdAt: Date
        let prompt: String
        let model: String
        let notice: String
    }
    @Published private(set) var pending: [Request] = []
    private var continuations: [String: CheckedContinuation<Bool, Never>] = [:]
    private var reviewWindow: NSWindow?
    private var reviewingID: String?

    func request(jobID: String, requestID: String? = nil, requestLabel: String? = nil, createdAt: Date? = nil, prompt: String, model: String, notice: String?) async -> Bool {
        // The services reject duplicate active submissions before this point.
        guard continuations[jobID] == nil else { return false }
        return await withCheckedContinuation { continuation in
            continuations[jobID] = continuation
            pending.append(Request(id: jobID, requestID: requestID, requestLabel: requestLabel, createdAt: createdAt ?? Date(), prompt: prompt, model: model,
                notice: notice ?? "The price and maximum charge are unknown. Your provider account pays for this request. A failure or local cancellation may still incur a charge."))
            if reviewWindow == nil { review(jobID) }
        }
    }

    func review(_ id: String) {
        guard let request = pending.first(where: { $0.id == id }) else { return }
        if reviewingID == id, let reviewWindow {
            NSApp.activate(ignoringOtherApps: true)
            reviewWindow.makeKeyAndOrderFront(nil)
            return
        }
        hideReview()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Review Agent Generation"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: AgentApprovalReview(request: request, center: self))
        reviewingID = id
        reviewWindow = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func decide(_ id: String, approved: Bool) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        pending.removeAll { $0.id == id }
        if reviewingID == id { hideReview() }
        continuation.resume(returning: approved)
    }

    func denyAll() {
        for id in pending.map(\.id) { decide(id, approved: false) }
    }

    func hideReview() {
        reviewWindow?.delegate = nil
        reviewWindow?.close()
        reviewWindow = nil
        reviewingID = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === reviewWindow else { return }
        reviewWindow = nil
        reviewingID = nil
    }
}

private struct AgentApprovalReview: View {
    let request: AgentApprovalCenter.Request
    let center: AgentApprovalCenter
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Approve one agent generation?").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let label = request.requestLabel { Text(label).font(.headline) }
                    Text("Job \(request.id)").font(.caption.monospaced()).textSelection(.enabled)
                    if let id = request.requestID { Text("Request \(id)").font(.caption.monospaced()).textSelection(.enabled) }
                    Text(request.model).font(.headline)
                    Text(request.prompt).textSelection(.enabled)
                    Text(request.notice).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Closing this window leaves the request waiting. Reopen it from Jobs → Pending Approvals while GenStation remains open.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Deny") { center.decide(request.id, approved: false) }
                Spacer()
                Button("Review Later") { center.hideReview() }.keyboardShortcut(.cancelAction)
                Button("Approve once") { center.decide(request.id, approved: true) }
                    .buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(minWidth: 480, minHeight: 360)
    }
}

struct AgentPendingApprovalsView: View {
    @ObservedObject private var center = AgentApprovalCenter.shared
    var body: some View {
        if !center.pending.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pending Approvals (\(center.pending.count))").font(.headline)
                Text("Nothing is submitted until you approve. Closing a review leaves it here while the app is open.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(center.pending) { request in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(request.model).lineLimit(2)
                            Text(request.prompt).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                            Text("Job \(request.id)").font(.caption.monospaced()).textSelection(.enabled)
                            if let id = request.requestID { Text("Request \(id)").font(.caption.monospaced()).textSelection(.enabled) }
                            if let label = request.requestLabel { Text(label).font(.caption) }
                            Text(request.createdAt, style: .relative).font(.caption)
                        }
                        Spacer()
                        Button("Review") { center.review(request.id) }
                        Button("Deny") { center.decide(request.id, approved: false) }
                    }
                }
            }.padding()
            Divider()
        }
    }
}
#endif
