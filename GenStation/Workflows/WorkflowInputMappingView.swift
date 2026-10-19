import SwiftUI
import GenStationCore

struct WorkflowInputMappingView: View {
    let workflow: SavedWorkflow
    let serverURL: String
    @Environment(\.dismiss) private var dismiss
    @State private var definitions: [WorkflowExposedInput]
    @State private var graph: [String: Any] = [:]
    @State private var objectInfo: [String: Any] = [:]
    @State private var error: String?
    @State private var loading = true
    @State private var selectedOutputs: Set<String>
    @State private var rangeDrafts: [String: String] = [:]

    init(workflow: SavedWorkflow, serverURL: String) {
        self.workflow = workflow; self.serverURL = serverURL
        _definitions = State(initialValue: workflow.exposedInputs)
        _selectedOutputs = State(initialValue: Set(workflow.outputNodeIDs))
    }

    private struct Choice: Identifiable {
        let id: String
        let nodeID: String
        let nodeType: String
        let inputKey: String
    }
    private func choices(for kind: WorkflowExposedInput.Kind) -> [Choice] {
        graph.keys.sorted().flatMap { nodeID -> [Choice] in
            guard let node = graph[nodeID] as? [String: Any], let type = node["class_type"] as? String,
                  let inputs = node["inputs"] as? [String: Any] else { return [] }
            return inputs.keys.sorted().compactMap { key in
                let candidate = WorkflowExposedInput(name: "input", label: key, kind: kind, nodeID: nodeID, nodeType: type, inputKey: key)
                guard (try? WorkflowInputResolver.validateDefinitions([candidate], graph: graph, objectInfo: objectInfo)) != nil else { return nil }
                let id = String(data: try! JSONEncoder().encode([nodeID, key]), encoding: .utf8)!
                return Choice(id: id, nodeID: nodeID, nodeType: type, inputKey: key)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Expose only the controls this saved workflow should accept. Agents use these names; every execution still needs approval.")
                    Text("Choose prompt roles carefully. Dynamic text nodes cannot be fully inspected by the text filter.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if loading { ProgressView("Reading server input definitions…") }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                ForEach(definitions.indices, id: \.self) { index in
                    Section("Input \(index + 1)") {
                        TextField("Stable name (for example, subject)", text: $definitions[index].name)
                        TextField("Label", text: $definitions[index].label)
                        Picker("Type", selection: $definitions[index].kind) {
                            ForEach(WorkflowExposedInput.Kind.allCases, id: \.self) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        bindingPicker(index)
                        Toggle("Required", isOn: $definitions[index].required)
                        Toggle("Use a default", isOn: Binding(get: { definitions[index].defaultValue != nil }, set: { enabled in
                            definitions[index].defaultValue = enabled ? (definitions[index].kind.isText ? .text("") : .integer(definitions[index].kind == .seed ? 0 : 1024)) : nil
                        }))
                        if definitions[index].defaultValue != nil {
                            TextField("Default value", text: valueBinding(index))
                        }
                        if !definitions[index].kind.isText {
                            TextField("Minimum (optional)", text: rangeBinding(index, minimum: true))
                            TextField("Maximum (optional)", text: rangeBinding(index, minimum: false))
                        }
                        Text("Allowed values (optional, one per line)").font(.caption)
                        TextEditor(text: choicesBinding(index)).frame(minHeight: 60)
                        if definitions[index].kind == .image {
                            Text("Reference values must be scoped library originals. Preflight never uploads; approved runs upload PNG copies to the configured server.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Remove Input", role: .destructive) { definitions.remove(at: index); rangeDrafts = [:] }
                    }
                }
                Section("Output nodes") {
                    Text("Select up to four output nodes. Leave empty to retain the workflow's existing output selection. A run retrieves at most 12 files, 50 MB each and 200 MB total.").font(.caption)
                    ForEach(graph.keys.sorted(), id: \.self) { id in
                        if let node = graph[id] as? [String: Any], let type = node["class_type"] as? String,
                           let info = objectInfo[type] as? [String: Any], info["output_node"] as? Bool == true {
                            Toggle("\(type) · \(id)", isOn: Binding(get: { selectedOutputs.contains(id) }, set: { selected in
                                if selected { selectedOutputs.insert(id) } else { selectedOutputs.remove(id) }
                            }))
                        }
                    }
                }
                Button("Add Input") {
                    definitions.append(.init(name: "input_\(definitions.count + 1)", label: "New input", kind: .prompt, nodeID: "", nodeType: "", inputKey: ""))
                }.disabled(loading || definitions.count >= 12)
            }
            .navigationTitle("Workflow Inputs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Inputs") {
                        do {
                            guard rangeDrafts.values.allSatisfy({ $0.isEmpty || Int64($0) != nil }) else { throw AgentImageError("Minimum and maximum must be whole numbers.") }
                            try WorkflowLibrary.shared.saveExposedInputs(definitions, for: workflow, preparedGraph: graph, objectInfo: objectInfo, outputNodeIDs: selectedOutputs.sorted())
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(loading || objectInfo.isEmpty)
                }
            }
            .task { await load() }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 600)
        #endif
    }

    @ViewBuilder private func bindingPicker(_ index: Int) -> some View {
        let available = choices(for: definitions[index].kind)
        Picker("Saved node input", selection: Binding(get: {
            available.first { $0.nodeID == definitions[index].nodeID && $0.inputKey == definitions[index].inputKey }?.id ?? ""
        }, set: { value in
            guard let choice = available.first(where: { $0.id == value }) else { return }
            definitions[index].nodeID = choice.nodeID; definitions[index].nodeType = choice.nodeType; definitions[index].inputKey = choice.inputKey
        })) {
            Text("Choose a compatible literal input").tag("")
            ForEach(available) { choice in Text("\(choice.nodeType) · \(choice.nodeID) · \(choice.inputKey)").tag(choice.id) }
        }
    }
    private func valueBinding(_ index: Int) -> Binding<String> {
        Binding(get: {
            switch definitions[index].defaultValue { case .text(let value): return value; case .integer(let value): return String(value); case nil: return "" }
        }, set: { text in
            definitions[index].defaultValue = definitions[index].kind.isText ? .text(text) : Int64(text).map(WorkflowInputValue.integer) ?? .text(text)
        })
    }
    private func choicesBinding(_ index: Int) -> Binding<String> {
        Binding(get: { (definitions[index].choices ?? []).map { value in
            switch value { case .text(let text): return text; case .integer(let number): return String(number) }
        }.joined(separator: "\n") }, set: { text in
            definitions[index].choices = text.isEmpty ? nil : text.components(separatedBy: "\n").map { line in
                definitions[index].kind.isText ? .text(line) : Int64(line).map(WorkflowInputValue.integer) ?? .text(line)
            }
        })
    }
    private func rangeBinding(_ index: Int, minimum: Bool) -> Binding<String> {
        let key = "\(index)-\(minimum)"
        return Binding(get: { rangeDrafts[key] ?? (minimum ? definitions[index].minimum : definitions[index].maximum).map(String.init) ?? "" }, set: { text in
            rangeDrafts[key] = text
            if minimum { definitions[index].minimum = Int64(text) } else { definitions[index].maximum = Int64(text) }
        })
    }
    @MainActor private func load() async {
        defer { loading = false }
        do {
            guard let raw = WorkflowLibrary.shared.getWorkflowJSON(workflow) else { throw AgentImageError("Saved workflow cannot be decoded.") }
            let normalized = try ComfyUITransport(serverURL: serverURL).serverURL
            objectInfo = try await ComfyUIFormatConverter.fetchAndCacheObjectInfo(serverURL: normalized)
            graph = try await ComfyUIFormatConverter.prepareWorkflowFetchingObjectInfoIfNeeded(json: raw, serverURL: normalized).workflow
            graph = ComfyUIFormatConverter.backfillMissingDefaults(workflow: graph, objectInfo: objectInfo).workflow
            guard let reachable = ComfyUIFormatConverter.reachableFromOutputs(workflow: graph), !reachable.isEmpty else { throw AgentImageError("Workflow has no recognized output nodes.") }
            graph = graph.filter { reachable.contains($0.key) }
        } catch { self.error = error.localizedDescription }
    }
}
