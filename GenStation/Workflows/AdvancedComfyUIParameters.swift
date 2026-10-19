// AdvancedComfyUIParameters.swift
import SwiftUI

// MARK: - Friendly Parameter Labels
private let friendlyLabels: [String: String] = [
    "cfg": "CFG Scale",
    "cfg_scale": "CFG Scale",
    "denoise": "Denoise Strength",
    "strength": "Strength",
    "steps": "Steps",
    "seed": "Seed",
    "noise_seed": "Noise Seed",
    "sampler_name": "Sampler",
    "scheduler": "Scheduler",
    "width": "Width",
    "height": "Height",
    "batch_size": "Batch Size",
    "text": "Prompt Text",
    "clip_skip": "CLIP Skip",
    "vae_name": "VAE",
    "ckpt_name": "Checkpoint",
    "lora_name": "LoRA",
    "model_name": "Model",
    "control_net_name": "ControlNet",
    "image": "Image",
    "mask": "Mask",
    "positive": "Positive Conditioning",
    "negative": "Negative Conditioning",
    "latent_image": "Latent Image",
    "samples": "Samples",
    "start_at_step": "Start Step",
    "end_at_step": "End Step",
    "add_noise": "Add Noise",
    "return_with_leftover_noise": "Return Leftover Noise",
    "tile_width": "Tile Width",
    "tile_height": "Tile Height",
    "guidance": "Guidance",
    "max_shift": "Max Shift",
    "base_shift": "Base Shift"
]

/// Returns a friendly display name for a parameter key
private func friendlyLabel(for key: String) -> String {
    friendlyLabels[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
}

// MARK: - Common Parameter Types
/// Represents a commonly-adjusted parameter extracted from the workflow
struct CommonParameter: Identifiable {
    let id: String  // nodeId + key
    let nodeId: String
    let nodeLabel: String
    let key: String
    let value: Any
    let classType: String
}

/// Keys considered "common" parameters that users frequently adjust
private let commonParameterKeys: Set<String> = [
    "seed", "noise_seed", "steps", "cfg", "cfg_scale", "denoise", "sampler_name", "scheduler"
]

// MARK: - Parameter Tooltips/Help Text
private let parameterTooltips: [String: String] = [
    // Sampling parameters
    "seed": "Random seed for reproducibility. Same seed + settings = same image.",
    "noise_seed": "Random seed for noise generation. Same seed = same noise pattern.",
    "steps": "Number of denoising steps. More steps = higher quality but slower. Typical: 20-30.",
    "cfg": "Classifier-Free Guidance scale. Higher = follows prompt more strictly. Typical: 5-8.",
    "cfg_scale": "Classifier-Free Guidance scale. Higher = follows prompt more strictly. Typical: 5-8.",
    "denoise": "Denoising strength (0-1). Lower preserves more of input image. 1.0 = full generation.",
    "strength": "Effect strength (0-1). Higher = stronger effect.",
    "sampler_name": "Algorithm for denoising. euler/dpmpp_2m are fast, dpmpp_sde gives more detail.",
    "scheduler": "Controls noise schedule. karras often gives better results than normal.",

    // Model parameters
    "ckpt_name": "The Stable Diffusion checkpoint/model file to use.",
    "vae_name": "Variational Auto-Encoder for image encoding/decoding.",
    "lora_name": "LoRA model for style/concept fine-tuning.",
    "clip_skip": "Skip last N CLIP layers. Try 1-2 for anime models.",

    // Image dimensions
    "width": "Output image width in pixels.",
    "height": "Output image height in pixels.",
    "batch_size": "Number of images to generate in parallel.",

    // ControlNet/IPAdapter
    "control_net_name": "ControlNet model for guided generation.",
    "guidance": "Guidance strength for the model.",

    // Advanced sampling
    "start_at_step": "Step to begin denoising (for multi-pass generation).",
    "end_at_step": "Step to end denoising (for multi-pass generation).",
    "add_noise": "Whether to add initial noise (disable for img2img latent input).",
    "return_with_leftover_noise": "Return partially denoised latent for chaining.",

    // Flux/SD3 specific
    "max_shift": "Maximum timestep shift for Flux models.",
    "base_shift": "Base timestep shift for Flux models.",

    // Tiling
    "tile_width": "Width of each tile for tiled generation.",
    "tile_height": "Height of each tile for tiled generation."
]

/// Returns tooltip text for a parameter, or nil if none defined
private func tooltip(for key: String) -> String? {
    parameterTooltips[key]
}

// MARK: - Node Ordering Priority
/// Priority order for node types (lower = shown first)
private let nodeTypePriority: [String: Int] = [
    // Samplers first - most commonly adjusted
    "KSampler": 0,
    "KSamplerAdvanced": 1,
    "SamplerCustom": 2,
    "SamplerCustomAdvanced": 3,

    // Model loaders
    "CheckpointLoaderSimple": 10,
    "CheckpointLoader": 11,
    "UNETLoader": 12,

    // LoRA
    "LoraLoader": 20,
    "LoraLoaderModelOnly": 21,

    // VAE
    "VAELoader": 30,
    "VAEDecode": 31,
    "VAEEncode": 32,

    // CLIP/Conditioning
    "CLIPTextEncode": 40,
    "CLIPTextEncodeSDXL": 41,
    "ConditioningCombine": 42,
    "ConditioningConcat": 43,

    // ControlNet
    "ControlNetLoader": 50,
    "ControlNetApply": 51,
    "ControlNetApplyAdvanced": 52,

    // IPAdapter
    "IPAdapter": 60,
    "IPAdapterAdvanced": 61,

    // Image operations
    "LoadImage": 70,
    "SaveImage": 71,
    "PreviewImage": 72,

    // Latent operations
    "EmptyLatentImage": 80,
    "LatentUpscale": 81,
    "LatentUpscaleBy": 82
]

/// Returns priority for a node class type (lower = shown first)
private func nodePriority(for classType: String) -> Int {
    // Check for exact match first
    if let priority = nodeTypePriority[classType] {
        return priority
    }
    // Check for partial matches (e.g., "KSamplerSelect" contains "KSampler")
    for (key, priority) in nodeTypePriority {
        if classType.contains(key) {
            return priority + 1  // Slightly lower priority than exact match
        }
    }
    // Unknown nodes go last
    return 1000
}

// MARK: - Inline Settings View (for side panel)
/// An inline version of ComfyUI settings that directly modifies appState
struct AdvancedComfyUISettingsView: View {
    @EnvironmentObject var appState: AppState

    private var workflow: [String: Any] {
        appState.generation.comfyWorkflow ?? [:]
    }

    /// Extract common parameters (seed, steps, cfg, etc.) for quick access
    private var commonParameters: [CommonParameter] {
        var params: [CommonParameter] = []
        let sortedNodeIds = workflow.keys.sorted(by: <)

        for nodeId in sortedNodeIds {
            guard let node = workflow[nodeId] as? [String: Any],
                  let classType = node["class_type"] as? String,
                  let inputs = node["inputs"] as? [String: Any] else {
                continue
            }

            for (key, value) in inputs {
                // Skip links (arrays) - only include actual values
                if value is [Any] { continue }
                if commonParameterKeys.contains(key) {
                    let nodeLabel = classType.contains("KSampler") ? "Sampler" : classType
                    params.append(CommonParameter(
                        id: "\(nodeId)_\(key)",
                        nodeId: nodeId,
                        nodeLabel: nodeLabel,
                        key: key,
                        value: value,
                        classType: classType
                    ))
                }
            }
        }
        return params
    }

    private var nodeSections: [NodeSection] {
        var sections: [NodeSection] = []

        for nodeId in workflow.keys {
            guard let node = workflow[nodeId] as? [String: Any],
                  let classType = node["class_type"] as? String,
                  let inputs = node["inputs"] as? [String: Any] else {
                continue
            }

            // Filter out inputs that are just links (arrays) - keep only editable values
            let editableInputs = inputs.filter { key, value in
                !(value is [Any])
            }

            // Skip nodes with no editable inputs
            guard !editableInputs.isEmpty else { continue }

            // Also skip nodes that only have common parameters (they're shown in Common section)
            let nonCommonInputs = editableInputs.filter { key, _ in
                !commonParameterKeys.contains(key)
            }

            // Include node if it has non-common inputs OR if it's a significant node type
            let significantTypes = ["KSampler", "KSamplerAdvanced", "SamplerCustom", "CheckpointLoader", "LoraLoader"]
            let isSignificant = significantTypes.contains(where: { classType.contains($0) })

            if !nonCommonInputs.isEmpty || isSignificant {
                let inputsArray = editableInputs.keys.sorted().map { key in
                    NodeInput(id: key, key: key, value: editableInputs[key] ?? "")
                }
                sections.append(NodeSection(id: nodeId, nodeId: nodeId, classType: classType, inputs: inputsArray))
            }
        }

        // Sort by node type priority (samplers first, then loaders, etc.)
        return sections.sorted { a, b in
            let priorityA = nodePriority(for: a.classType)
            let priorityB = nodePriority(for: b.classType)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Same priority - sort by node ID for stability
            return a.nodeId < b.nodeId
        }
    }

    struct NodeSection: Identifiable {
        let id: String
        let nodeId: String
        let classType: String
        let inputs: [NodeInput]
    }

    struct NodeInput: Identifiable {
        let id: String
        let key: String
        let value: Any
    }

    @State private var expandedNodes: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if appState.generation.comfyWorkflow == nil {
                Text("No workflow loaded")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                // Generation Settings
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Batch Size")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("", value: $appState.settings.comfyBatchSize, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.center)
                        Stepper("", value: $appState.settings.comfyBatchSize, in: 1...32)
                            .labelsHidden()
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Generation Timeout")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Alert if generation takes longer")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        Spacer()
                        TextField("", value: Binding(
                            get: { appState.settings.comfyGenerationTimeout / 60 },
                            set: { appState.settings.comfyGenerationTimeout = max(60, $0 * 60) }
                        ), formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.center)
                        Text("min")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Stepper("", value: Binding(
                            get: { appState.settings.comfyGenerationTimeout / 60 },
                            set: { appState.settings.comfyGenerationTimeout = max(60, $0 * 60) }
                        ), in: 1...60)
                            .labelsHidden()
                    }
                }

                // Common Parameters Section (seed, steps, cfg, etc.)
                if !commonParameters.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick Settings")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        ForEach(commonParameters) { param in
                            ParamView(
                                nodeId: param.nodeId,
                                key: param.key,
                                value: param.value,
                                classType: param.classType,
                                updateWorkflow: updateWorkflowValue
                            )
                            if param.id != commonParameters.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.08))
                    .cornerRadius(DS.Radius.standard)
                }

                // Workflow Node Parameters (collapsed by default)
                if !nodeSections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("All Node Parameters")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)

                        ForEach(nodeSections) { section in
                            CollapsibleNodeGroupView(
                                section: section,
                                isExpanded: Binding(
                                    get: { expandedNodes.contains(section.id) },
                                    set: { expanded in
                                        if expanded {
                                            expandedNodes.insert(section.id)
                                        } else {
                                            expandedNodes.remove(section.id)
                                        }
                                    }
                                ),
                                updateWorkflow: updateWorkflowValue
                            )
                        }
                    }
                }
            }
        }
    }

    private func updateWorkflowValue(nodeId: String, key: String, value: Any) {
        guard var workflow = appState.generation.comfyWorkflow,
              var node = workflow[nodeId] as? [String: Any],
              var inputs = node["inputs"] as? [String: Any] else {
            return
        }
        inputs[key] = value
        node["inputs"] = inputs
        workflow[nodeId] = node
        appState.generation.comfyWorkflow = workflow
    }
}

/// Collapsible node group for the side panel (collapsed by default)
struct CollapsibleNodeGroupView: View {
    let section: AdvancedComfyUISettingsView.NodeSection
    @Binding var isExpanded: Bool
    let updateWorkflow: (String, String, Any) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (always visible)
            Button(action: { withAnimation(DS.Anim.quick) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text(section.classType)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(section.inputs.count) params")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.inputs) { input in
                        ParamView(
                            nodeId: section.nodeId,
                            key: input.key,
                            value: input.value,
                            classType: section.classType,
                            updateWorkflow: updateWorkflow
                        )
                        if input.id != section.inputs.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color.primary.opacity(0.03))
        .cornerRadius(DS.Radius.standard)
    }
}

/// Inline node group for the side panel (uses direct workflow updates) - expanded by default
struct InlineNodeGroupView: View {
    let section: AdvancedComfyUISettingsView.NodeSection
    let updateWorkflow: (String, String, Any) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(section.classType)")
                .font(.subheadline.bold())
                .foregroundColor(.primary)

            ForEach(section.inputs) { input in
                ParamView(
                    nodeId: section.nodeId,
                    key: input.key,
                    value: input.value,
                    classType: section.classType,
                    updateWorkflow: updateWorkflow
                )
                if input.id != section.inputs.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(DS.Radius.standard)
    }
}

// MARK: - Sheet Version (original)
struct AdvancedComfyUIParameters: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var localWorkflow: [String: [String: Any]] = [:]
    @State private var error: String? = nil
    
    // Extract node processing into a computed property to simplify type checking
    private var nodeSections: [NodeSection] {
        var sections: [NodeSection] = []

        for nodeId in localWorkflow.keys {
            guard let node = localWorkflow[nodeId],
                  let classType = node["class_type"] as? String,
                  let inputs = node["inputs"] as? [String: Any] else {
                continue
            }

            // Filter out inputs that are just links (arrays) - keep only editable values
            let editableInputs = inputs.filter { _, value in
                !(value is [Any])
            }

            // Skip nodes with no editable inputs
            guard !editableInputs.isEmpty else { continue }

            let inputsArray = editableInputs.keys.sorted().map { key in
                NodeInput(id: key, key: key, value: editableInputs[key]!)
            }
            sections.append(NodeSection(id: nodeId, nodeId: nodeId, classType: classType, inputs: inputsArray))
        }

        // Sort by node type priority (samplers first, then loaders, etc.)
        return sections.sorted { a, b in
            let priorityA = nodePriority(for: a.classType)
            let priorityB = nodePriority(for: b.classType)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            return a.nodeId < b.nodeId
        }
    }
    
    struct NodeSection: Identifiable {
        let id: String  // Use nodeId as the stable ID
        let nodeId: String
        let classType: String
        let inputs: [NodeInput]
    }

    struct NodeInput: Identifiable {
        let id: String  // Use key as the stable ID
        let key: String
        let value: Any
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = error {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    }

                    // Generation Settings Section
                    GroupBox {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Batch Size")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                TextField("", value: $appState.settings.comfyBatchSize, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.center)
                                Stepper("", value: $appState.settings.comfyBatchSize, in: 1...32)
                                    .labelsHidden()
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Generation Timeout")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text("Alert if generation takes longer")
                                        .font(.caption)
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                                Spacer()
                                TextField("", value: Binding(
                                    get: { appState.settings.comfyGenerationTimeout / 60 },
                                    set: { appState.settings.comfyGenerationTimeout = max(60, $0 * 60) }
                                ), formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.center)
                                Text("min")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Stepper("", value: Binding(
                                    get: { appState.settings.comfyGenerationTimeout / 60 },
                                    set: { appState.settings.comfyGenerationTimeout = max(60, $0 * 60) }
                                ), in: 1...60)
                                    .labelsHidden()
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Text("Generation Settings")
                            .font(.title3)
                            .bold()
                    }

                    ForEach(nodeSections) { section in
                        NodeGroupView(
                            section: section,
                            localWorkflow: $localWorkflow
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Advanced ComfyUI Parameters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appState.generation.comfyWorkflow = localWorkflow
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if let wf = appState.generation.comfyWorkflow as? [String: [String: Any]] {
                localWorkflow = wf
            } else {
                error = "No workflow loaded or invalid format."
            }
        }
    }
}

struct NodeGroupView: View {
    let section: AdvancedComfyUIParameters.NodeSection
    @Binding var localWorkflow: [String: [String: Any]]
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.inputs) { input in
                    ParamView(
                        nodeId: section.nodeId,
                        key: input.key,
                        value: input.value,
                        classType: section.classType,
                        updateWorkflow: { nodeId, key, value in
                            guard var node = localWorkflow[nodeId],
                                  var inputs = node["inputs"] as? [String: Any] else {
                                return
                            }
                            inputs[key] = value
                            node["inputs"] = inputs
                            localWorkflow[nodeId] = node
                        }
                    )
                    if input.id != section.inputs.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 5)
        } label: {
            Text("\(section.classType) (ID: \(section.nodeId))")
                .font(.title3)
                .bold()
                .foregroundColor(.primary)
        }
        .groupBoxStyle(DefaultGroupBoxStyle()) // Ensures consistent rounded look
        .shadow(radius: 1) // Subtle shadow for depth on both platforms
    }
}

// MARK: - Parameter Label with Tooltip
/// A label view that shows friendly parameter name with optional tooltip
struct ParamLabel: View {
    let key: String
    let minWidth: CGFloat

    init(_ key: String, minWidth: CGFloat = 100) {
        self.key = key
        self.minWidth = minWidth
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(friendlyLabel(for: key))
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let helpText = tooltip(for: key) {
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .help(helpText)
            }
        }
        .frame(minWidth: minWidth, alignment: .leading)
    }
}

struct ParamView: View {
    @EnvironmentObject var appState: AppState

    let nodeId: String
    let key: String
    let value: Any
    let classType: String
    let updateWorkflow: (String, String, Any) -> Void

    @State private var text: String
    @State private var currentValue: Any
    @FocusState private var isFocused: Bool
    
    // Initialize @State based on value type
    init(nodeId: String, key: String, value: Any, classType: String, updateWorkflow: @escaping (String, String, Any) -> Void) {
        self.nodeId = nodeId
        self.key = key
        self.value = value
        self.classType = classType
        self.updateWorkflow = updateWorkflow
        if let intValue = value as? Int {
            self._text = State(initialValue: String(intValue))
            self._currentValue = State(initialValue: intValue)
        } else if let doubleValue = value as? Double {
            self._text = State(initialValue: String(format: "%.2f", doubleValue))
            self._currentValue = State(initialValue: doubleValue)
        } else if let stringValue = value as? String {
            self._text = State(initialValue: stringValue)
            self._currentValue = State(initialValue: stringValue) // Use string for currentValue
        } else if let boolValue = value as? Bool {
            self._text = State(initialValue: "")
            self._currentValue = State(initialValue: boolValue)
        } else {
            self._text = State(initialValue: "\(value)")
            self._currentValue = State(initialValue: value)
        }
    }
    
    var body: some View {
        Group {
            if let arrayValue = value as? [Any] {
                linkParamView(arrayValue: arrayValue)
            } else if value is Bool {
                if let boolValue = value as? Bool {
                    boolParamView(initialValue: boolValue)
                }
            } else if value is String {
                if let stringValue = value as? String {
                    stringParamView(initialValue: stringValue)
                }
            } else if value is Int || value is Double {
                numericParamView()
            } else {
                unsupportedParamView()
            }
        }
        .onAppear {
            // Initialize text here instead of init, to handle prop updates
            if let intValue = value as? Int {
                text = String(intValue)
            } else if let doubleValue = value as? Double {
                text = String(format: "%.2f", doubleValue)
            } else if let stringValue = value as? String {
                text = stringValue
            } else {
                text = "\(value)"
            }
            
            // Recast specific integer keys to double on appear
            let doubleKeys = ["cfg", "denoise", "strength"] // Add more keys as needed
            if doubleKeys.contains(key), let intVal = currentValue as? Int {
                let doubleVal = Double(intVal)
                currentValue = doubleVal
                text = String(format: "%.2f", doubleVal)
                updateWorkflow(nodeId, key, doubleVal)
            }
        }
    }
    
    @ViewBuilder
    private func numericParamView() -> some View {
        let bindingInt = Binding<Int?>(
            get: { currentValue as? Int },
            set: { newVal in
                if let val = newVal {
                    currentValue = val
                    updateWorkflow(nodeId, key, val)
                    text = String(val)
                }
            }
        )
        
        let bindingDouble = Binding<Double?>(
            get: { currentValue as? Double },
            set: { newVal in
                if let val = newVal {
                    currentValue = val
                    updateWorkflow(nodeId, key, val)
                    text = String(format: "%.2f", val)
                }
            }
        )
        
        let commitValue: () -> Void = {
            if let intVal = Int(text) {
                bindingInt.wrappedValue = intVal
            } else if let doubleVal = Double(text) {
                bindingDouble.wrappedValue = doubleVal
            } else {
                // Revert to previous value
                if let intVal = currentValue as? Int {
                    text = String(intVal)
                } else if let doubleVal = currentValue as? Double {
                    text = String(format: "%.2f", doubleVal)
                }
            }
        }
        
        if key == "steps" && classType.contains("KSampler") {
            HStack {
                ParamLabel(key)
                Spacer()
                HStack(spacing: 0) {
                    TextField("", text: $text)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                        .multilineTextAlignment(.center)
                        .focused($isFocused)
                        .onSubmit(commitValue)
                        .onChange(of: isFocused) { focused in
                            if !focused { commitValue() }
                        }
                    if let doubleVal = bindingDouble.wrappedValue {
                        let range: ClosedRange<Double> = 0.0...100.0 // Adjust for steps if needed
                        let step: Double = 1.0
                        Stepper("", value: Binding<Double>(get: { doubleVal }, set: { bindingDouble.wrappedValue = $0 }), in: range, step: step)
                    } else if let intVal = bindingInt.wrappedValue {
                        Stepper("", value: Binding<Int>(get: { intVal }, set: { bindingInt.wrappedValue = $0 }), in: 1...100)
                    }
                }
            }
        } else if key == "seed" || key == "noise_seed" {
            HStack {
                ParamLabel(key)
                Spacer()
                TextField("", text: $text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isFocused)
                    .onSubmit(commitValue)
                    .onChange(of: isFocused) { focused in
                        if !focused { commitValue() }
                    }
                Button("Random") {
                    let rand = Int.random(in: 0...Int.max)
                    text = String(rand)
                    bindingInt.wrappedValue = rand  // Keep seeds as Int
                }
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
        } else {
            HStack {
                ParamLabel(key)
                Spacer()
                HStack(spacing: 0) {
                    TextField("", text: $text)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                        .multilineTextAlignment(.center)
                        .focused($isFocused)
                        .onSubmit(commitValue)
                        .onChange(of: isFocused) { focused in
                            if !focused { commitValue() }
                        }
                    if let doubleVal = bindingDouble.wrappedValue {
                        let range: ClosedRange<Double> = key == "cfg" || key == "cfg_scale" ? 0.0...20.0 : (key == "denoise" || key == "strength" ? 0.0...1.0 : 0.0...100.0)
                        let step: Double = key == "cfg" || key == "cfg_scale" ? 0.5 : (key == "denoise" || key == "strength" ? 0.01 : 0.1)
                        Stepper("", value: Binding<Double>(get: { doubleVal }, set: { bindingDouble.wrappedValue = $0 }), in: range, step: step)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func linkParamView(arrayValue: [Any]) -> some View {
        let linkText = if arrayValue.count == 2, let node = arrayValue[0] as? String, arrayValue[1] is Int {
            "→ Node \(node)"
        } else {
            "Linked"
        }
        HStack {
            ParamLabel(key)
            Spacer()
            Text(linkText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
    }

    @ViewBuilder
    private func boolParamView(initialValue: Bool) -> some View {
        let binding = Binding<Bool>(
            get: { currentValue as? Bool ?? initialValue },
            set: { newVal in
                currentValue = newVal
                updateWorkflow(nodeId, key, newVal)
            }
        )
        HStack {
            ParamLabel(key)
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func stringParamView(initialValue: String) -> some View {
        let binding = Binding<String>(
            get: { text },
            set: { newVal in
                updateWorkflow(nodeId, key, newVal)
                text = newVal
            }
        )
        if isDropdownKey(key: key, classType: classType) {
            let availableOptions = options(for: key, classType: classType)
            // Include current value if it's not in the list (e.g., model was renamed/removed)
            let allOptions = availableOptions.contains(text) ? availableOptions : [text] + availableOptions

            HStack {
                ParamLabel(key)
                Spacer()
                Picker("", selection: binding) {
                    ForEach(allOptions, id: \.self) { option in
                        // Show filename without path for model names
                        let displayName = option.contains("/") ? String(option.split(separator: "/").last ?? Substring(option)) : option
                        Text(displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        } else {
            HStack {
                ParamLabel(key)
                Spacer()
                TextField("", text: binding)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
    }

    @ViewBuilder
    private func unsupportedParamView() -> some View {
        HStack {
            ParamLabel(key)
            Spacer()
            Text("Unsupported")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func isDropdownKey(key: String, classType: String) -> Bool {
        // Sampler/scheduler dropdowns for KSampler nodes
        if classType.contains("KSampler") && (key == "sampler_name" || key == "scheduler") {
            return true
        }
        // Model selection dropdowns (only show if we have fetched options)
        if key == "ckpt_name" && appState.generation.fetchedCheckpoints != nil {
            return true
        }
        if key == "vae_name" && appState.generation.fetchedVAEs != nil {
            return true
        }
        if key == "lora_name" && appState.generation.fetchedLoRAs != nil {
            return true
        }
        return false
    }

    private func options(for key: String, classType: String) -> [String] {
        if key == "sampler_name" {
            // Use fetched samplers if available, otherwise fall back to hardcoded list
            if let fetched = appState.generation.fetchedSamplers, !fetched.isEmpty {
                return fetched
            }
            return [
                // Classic samplers
                "euler", "euler_ancestral", "euler_cfg_pp", "heun", "heunpp2",
                "dpm_2", "dpm_2_ancestral",
                "lms",
                // DPM++ family
                "dpmpp_2s_ancestral", "dpmpp_sde", "dpmpp_sde_gpu",
                "dpmpp_2m", "dpmpp_2m_sde", "dpmpp_2m_sde_gpu",
                "dpmpp_3m_sde", "dpmpp_3m_sde_gpu",
                // Fast/adaptive
                "dpm_fast", "dpm_adaptive",
                // DDIM/DDPM
                "ddim", "ddpm",
                // UniPC
                "uni_pc", "uni_pc_bh2",
                // LCM/Turbo (for distilled models)
                "lcm",
                // TCD
                "ipndm", "ipndm_v", "deis"
            ]
        } else if key == "scheduler" {
            // Use fetched schedulers if available, otherwise fall back to hardcoded list
            if let fetched = appState.generation.fetchedSchedulers, !fetched.isEmpty {
                return fetched
            }
            return [
                "normal", "karras", "exponential", "sgm_uniform",
                "simple", "ddim_uniform", "beta", "linear_quadratic"
            ]
        } else if key == "ckpt_name" {
            return appState.generation.fetchedCheckpoints ?? []
        } else if key == "vae_name" {
            return appState.generation.fetchedVAEs ?? []
        } else if key == "lora_name" {
            return appState.generation.fetchedLoRAs ?? []
        }
        return []
    }
}
