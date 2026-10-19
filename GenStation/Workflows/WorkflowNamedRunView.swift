import SwiftUI
import GenStationCore

struct WorkflowNamedRunView: View {
    let initialWorkflowID: UUID?
    let initialAssetID: UUID?
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = WorkflowLibrary.shared
    @State private var selection: UUID?
    @State private var values: [String: String] = [:]
    @State private var legacyPrompt = ""
    @State private var prepared: WorkflowNamedRequest?
    @State private var checking = false
    @State private var error: String?
    @State private var submittedJobID: String?

    private var eligibleWorkflows: [SavedWorkflow] { library.sortedWorkflows.filter { initialAssetID == nil || $0.exposedInputs.contains(where: { $0.kind == .image }) } }
    private var selected: SavedWorkflow? { library.workflows.first { $0.id == selection } }
    private var images: [HistoryItem] {
        app.historyState.history.flatMap(\.allItems).filter { $0.imagePath != nil && $0.task != .video && $0.videoUrl == nil }
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Saved workflow", selection: $selection) {
                    Text("Choose a workflow").tag(Optional<UUID>.none)
                    ForEach(eligibleWorkflows) { workflow in Text(workflow.name).tag(Optional(workflow.id)) }
                }.disabled(submittedJobID != nil)
                if eligibleWorkflows.isEmpty { Text("No saved workflow exposes a compatible image input. Save a workflow and map its image input in Configuration first.") }
                if let selected {
                    ForEach(selected.exposedInputs) { definition in
                        if definition.kind == .image {
                            Picker(definition.label, selection: textBinding(definition)) {
                                Text(definition.required ? "Choose an original" : "Use saved value").tag("")
                                ForEach(images) { item in Text(String(item.prompt.prefix(70))).tag("asset:" + item.id.uuidString) }
                            }
                        } else {
                            TextField(definition.label, text: textBinding(definition))
                        }
                    }.disabled(submittedJobID != nil)
                    if !selected.exposedInputs.contains(where: { $0.kind == .prompt }) {
                        TextField("Prompt override (optional)", text: $legacyPrompt).disabled(submittedJobID != nil)
                    }
                    if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    if let prepared {
                        Section("Review this run") {
                            Text(prepared.prepared.prompt ?? "Use saved prompt inputs")
                            Text("\(prepared.images.count) reference uploads · cost unknown")
                            Text("The saved workflow may access server files or services. Approval uploads these references and runs the workflow once. Stopping local waiting does not cancel server execution.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(prepared.images, id: \.name) { image in Text("\(image.name): original \(image.assetID.uuidString.prefix(8))") }
                            if !prepared.prepared.promptInspectionLimitations.isEmpty {
                                Text("Some linked/custom prompt inputs cannot be fully inspected.").font(.caption)
                            }
                            DisclosureGroup("Prepared workflow details") {
                                Text(String(data: (try? JSONSerialization.data(withJSONObject: prepared.prepared.graph, options: [.prettyPrinted, .sortedKeys])) ?? Data(), encoding: .utf8) ?? "")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                            }
                            Button("Approve and Run") {
                                do {
                                    submittedJobID = try app.workflowJobs.startNamed(prepared, app: app)
                                    self.prepared = nil
                                } catch { self.error = error.localizedDescription }
                            }.buttonStyle(.borderedProminent)
                        }
                    } else if submittedJobID == nil {
                        Button(checking ? "Validating…" : "Validate and Review") { Task { await validate(selected) } }
                            .disabled(checking)
                    }
                }
                if let submittedJobID {
                    Text("Job \(submittedJobID.prefix(8)) is tracked in Jobs. Originals are saved to your output folder, with an app fallback if it is unavailable.")
                    Button("Open Jobs") { app.presentedModal = .jobs }
                }
            }
            .navigationTitle("Run Saved Workflow")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { selection = initialWorkflowID ?? eligibleWorkflows.first?.id; loadDefaults() }
            .onChange(of: selection) { _ in loadDefaults() }
            .onChange(of: values) { _ in prepared = nil }
            .onChange(of: legacyPrompt) { _ in prepared = nil }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 600)
        #endif
    }
    private func textBinding(_ definition: WorkflowExposedInput) -> Binding<String> {
        Binding(get: { values[definition.name] ?? "" }, set: { values[definition.name] = $0 })
    }
    private func loadDefaults() {
        values = [:]; prepared = nil; error = nil; legacyPrompt = ""
        guard let selected else { return }
        for definition in selected.exposedInputs {
            if let value = definition.defaultValue {
                switch value { case .text(let text): values[definition.name] = text; case .integer(let number): values[definition.name] = String(number) }
            }
        }
        if let initialAssetID, let field = selected.exposedInputs.first(where: { $0.kind == .image }) { values[field.name] = "asset:" + initialAssetID.uuidString }
    }
    @MainActor private func validate(_ selected: SavedWorkflow) async {
        checking = true; error = nil; prepared = nil
        defer { checking = false }
        do {
            let capturedValues = values, capturedPrompt = legacyPrompt
            var parsed: [String: WorkflowInputValue] = [:]
            for definition in selected.exposedInputs {
                guard let value = capturedValues[definition.name], !value.isEmpty else { continue }
                if definition.kind.isText { parsed[definition.name] = .text(value) }
                else if let number = Int64(value) { parsed[definition.name] = .integer(number) }
                else { throw AgentImageError("\(definition.label) requires a whole number.") }
            }
            let request = try await WorkflowNamedRequest.prepare(saved: selected, values: parsed, legacyPrompt: capturedPrompt, app: app)
            guard selection == selected.id, values == capturedValues, legacyPrompt == capturedPrompt else { throw AgentImageError("Inputs changed during validation. Validate again.") }
            prepared = request
        } catch { self.error = error.localizedDescription }
    }
}
