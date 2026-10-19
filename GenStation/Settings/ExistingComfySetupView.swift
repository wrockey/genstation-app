import SwiftUI

/// Uses the same installed-server fetch/cache operation as ConfigurationSection.
struct ExistingComfySetupView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void
    @State private var task: Task<Void, Never>?
    @State private var status = "Not checked"
    @State private var checking = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect an existing ComfyUI server").font(.title2.bold())
            Text("Enter the address of your running server. An installed workflow is required; import it from the creation form after connecting.")
            TextField("Server address", text: $appState.settings.comfyServerURL).textFieldStyle(.roundedBorder)
            Text(status).fixedSize(horizontal: false, vertical: true)
            Button("Check connection") {
                task?.cancel()
                let address = appState.settings.comfyServerURL
                checking = true
                status = "Checking…"
                task = Task { @MainActor in
                    defer { checking = false }
                    do {
                        let nodes = try await ComfyUIFormatConverter.fetchAndCacheObjectInfo(serverURL: address)
                        guard !Task.isCancelled, address == appState.settings.comfyServerURL else { return }
                        appState.generation.comfyServerStatus = .connected(nodeCount: nodes.count)
                        status = "Connected. Import an installed workflow to create images."
                    } catch {
                        guard !Task.isCancelled, address == appState.settings.comfyServerURL else { return }
                        status = "Could not connect. Check the address, server, and network, then try again. Your address is saved."
                    }
                }
            }.disabled(checking)
            Button("Continue") {
                appState.settings.provider = .comfyUI
                appState.settings.task = .image
                onContinue()
            }
        }
        .onChange(of: appState.settings.comfyServerURL) { _, _ in task?.cancel(); status = "Not checked"; checking = false }
        .onDisappear { task?.cancel() }
    }
}
