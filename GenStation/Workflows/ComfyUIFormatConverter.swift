// ComfyUIFormatConverter.swift
// Utilities for ComfyUI workflow format detection and server info caching

import Foundation
import GenStationCore

/// Utilities for ComfyUI workflow handling
class ComfyUIFormatConverter {

    // MARK: - Object Info Cache
    // Used to cache server node definitions when testing connection

    private static let cacheKey = "cachedComfyUIObjectInfo"
    private static let cacheTimestampKey = "cachedComfyUIObjectInfoTimestamp"
    private static let cacheServerURLKey = "cachedComfyUIObjectInfoServerURL"
    private static var inMemoryObjectInfo: [String: Any]?

    /// Saves object_info to cache (called when testing server connection)
    static func cacheObjectInfo(_ objectInfo: [String: Any], serverURL: String) {
        if let data = try? JSONSerialization.data(withJSONObject: objectInfo) {
            inMemoryObjectInfo = objectInfo
            AppStorageContext.defaults.set(data, forKey: cacheKey)
            AppStorageContext.defaults.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
            AppStorageContext.defaults.set(serverURL, forKey: cacheServerURLKey)
            Log.debug("Cached ComfyUI object_info (\(objectInfo.count) node types)")
        }
    }

    /// Returns info about the cache (for UI display)
    static var cacheInfo: (nodeCount: Int, serverURL: String?, date: Date?)? {
        guard let data = AppStorageContext.defaults.data(forKey: cacheKey),
              let objectInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let serverURL = AppStorageContext.defaults.string(forKey: cacheServerURLKey)
        let timestamp = AppStorageContext.defaults.double(forKey: cacheTimestampKey)
        let date = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        return (objectInfo.count, serverURL, date)
    }

    /// Clears the object_info cache
    static func clearCache() {
        inMemoryObjectInfo = nil
        AppStorageContext.defaults.removeObject(forKey: cacheKey)
        AppStorageContext.defaults.removeObject(forKey: cacheTimestampKey)
        AppStorageContext.defaults.removeObject(forKey: cacheServerURLKey)
    }

    /// Loads the cached object_info dictionary, using in-memory cache when available
    static func loadCachedObjectInfo() -> [String: Any]? {
        if let cached = inMemoryObjectInfo { return cached }
        guard let data = AppStorageContext.defaults.data(forKey: cacheKey),
              let objectInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        inMemoryObjectInfo = objectInfo
        return objectInfo
    }

    /// Normalizes a user-entered server URL: trims whitespace and prepends http:// when no scheme is given.
    static func normalizedServerURL(_ raw: String) -> String {
        ComfyUIEndpoints.normalizedServerURL(raw)
    }

    /// True when the cached object_info was fetched from the given server URL (staleness check).
    static func cachedObjectInfoMatches(serverURL: String) -> Bool {
        guard let cachedURL = AppStorageContext.defaults.string(forKey: cacheServerURLKey) else { return false }
        return normalizedServerURL(cachedURL) == normalizedServerURL(serverURL)
    }

    /// Errors thrown while fetching object_info from the server.
    enum ObjectInfoFetchError: LocalizedError {
        case invalidURL
        case httpStatus(Int)
        case network(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .httpStatus(401), .httpStatus(403): return "Server rejected access. Check the server or proxy authentication settings."
            case .httpStatus(404): return "Node definitions were not found. Check the server address and any proxy base path."
            case .httpStatus(let code): return "Server responded with status: \(code)"
            case .network(let detail): return "Failed to connect: \(detail)"
            case .invalidResponse: return "Server returned an unreadable object_info response"
            }
        }
    }

    /// Fetches `/object_info` from the ComfyUI server and caches it for workflow conversion.
    /// Extracted from the Test Connection flow so imports can auto-fetch on demand.
    @discardableResult
    static func fetchAndCacheObjectInfo(serverURL: String) async throws -> [String: Any] {
        let baseURL = normalizedServerURL(serverURL)
        guard let url = ComfyUIEndpoints.objectInfoURL(serverURL: serverURL) else {
            throw ObjectInfoFetchError.invalidURL
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw ObjectInfoFetchError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ObjectInfoFetchError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let objectInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !objectInfo.isEmpty,
              objectInfo.values.allSatisfy({ ($0 as? [String: Any])?["input"] is [String: Any] }) else {
            throw ObjectInfoFetchError.invalidResponse
        }

        cacheObjectInfo(objectInfo, serverURL: baseURL)
        return objectInfo
    }

    // MARK: - Workflow Preparation

    /// Result of preparing a parsed workflow dict for storage/execution.
    struct PreparedWorkflow {
        let workflow: [String: Any]
        /// True when the input was UI format and had to be converted to API format.
        let wasConverted: Bool
    }

    /// Typed rejections for workflow preparation. `errorDescription` is the short alert
    /// title; `remediation` is the detailed "More Info" text.
    enum WorkflowPreparationError: LocalizedError {
        case emptyWorkflow
        case containsSubgraphs
        case containsGroupNodes
        case objectInfoUnavailable(detail: String?)
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .emptyWorkflow:
                return "Invalid or empty workflow."
            case .containsSubgraphs:
                return "Workflow contains subgraphs"
            case .containsGroupNodes:
                return "Workflow contains group nodes"
            case .objectInfoUnavailable:
                return "Could not reach ComfyUI server"
            case .conversionFailed:
                return "Failed to convert workflow"
            }
        }

        var remediation: String? {
            switch self {
            case .emptyWorkflow:
                return nil
            case .containsSubgraphs:
                return """
                This workflow uses subgraphs, which can't be auto-converted and would \
                lose nodes. In ComfyUI, unpack/convert the subgraph to regular nodes, or \
                export as API format: enable Dev Mode in Settings, then use Save (API Format).
                """
            case .containsGroupNodes:
                return """
                Group nodes cannot be auto-converted. Please ungroup \
                them in ComfyUI before saving, or export as API format: \
                enable Dev Mode in Settings, then use Save (API Format).
                """
            case .objectInfoUnavailable(let detail):
                var message = """
                This workflow is in ComfyUI's standard format and needs server \
                data to convert, but the server could not be reached.

                1. Check your ComfyUI server URL and that the server is running
                2. Then reload this workflow

                Alternatively, in ComfyUI enable 'Dev Mode Options' \
                and use 'Save (API Format)'.
                """
                if let detail = detail, !detail.isEmpty {
                    message += "\n\nDetails: \(detail)"
                }
                return message
            case .conversionFailed:
                return """
                The file may be corrupted or use an unsupported format.

                Try exporting your workflow as API format: in ComfyUI, \
                enable Dev Mode in Settings, then use Save (API Format).
                """
            }
        }
    }

    /// Synchronous core of workflow preparation: passes API-format dicts through and
    /// converts UI-format dicts, enforcing the subgraph/group-node rejections.
    static func prepareWorkflow(
        json: [String: Any],
        objectInfo: [String: Any]?
    ) throws -> PreparedWorkflow {
        guard isUIFormat(json) else {
            guard !json.isEmpty else { throw WorkflowPreparationError.emptyWorkflow }
            return PreparedWorkflow(workflow: json, wasConverted: false)
        }

        // Subgraphs (ComfyUI frontend ≥1.24) live under definitions.subgraphs and are not
        // expanded by the converter, so their internal nodes would be silently dropped.
        if workflowContainsSubgraphs(json) {
            throw WorkflowPreparationError.containsSubgraphs
        }

        guard let objectInfo = objectInfo else {
            throw WorkflowPreparationError.objectInfoUnavailable(detail: nil)
        }

        guard let result = convertUIToAPIFormat(uiWorkflow: json, objectInfo: objectInfo) else {
            throw WorkflowPreparationError.conversionFailed
        }

        if !result.warnings.isEmpty {
            Log.debug("Conversion warnings: \(result.warnings.joined(separator: "; "))")
            if result.warnings.contains(where: { $0.contains("Group node") }) {
                throw WorkflowPreparationError.containsGroupNodes
            }
        }

        guard !result.workflow.isEmpty else { throw WorkflowPreparationError.emptyWorkflow }
        return PreparedWorkflow(workflow: result.workflow, wasConverted: true)
    }

    /// True when a UI-format workflow declares non-empty subgraph definitions.
    static func workflowContainsSubgraphs(_ json: [String: Any]) -> Bool {
        guard let defs = json["definitions"] as? [String: Any],
              let subgraphs = defs["subgraphs"] as? [[String: Any]] else { return false }
        return !subgraphs.isEmpty
    }

    /// Async preparation used by the import paths: when the workflow is UI format and the
    /// object_info cache is missing or was fetched from a different server URL, fetch it
    /// first. On fetch failure, falls back to any cached copy before giving up.
    static func prepareWorkflowFetchingObjectInfoIfNeeded(
        json: [String: Any],
        serverURL: String
    ) async throws -> PreparedWorkflow {
        guard isUIFormat(json) else {
            return try prepareWorkflow(json: json, objectInfo: nil)
        }

        // Reject subgraphs before doing any network work.
        if workflowContainsSubgraphs(json) {
            throw WorkflowPreparationError.containsSubgraphs
        }

        var objectInfo: [String: Any]?
        if cachedObjectInfoMatches(serverURL: serverURL) {
            objectInfo = loadCachedObjectInfo()
        }

        if objectInfo == nil {
            do {
                objectInfo = try await fetchAndCacheObjectInfo(serverURL: serverURL)
            } catch {
                // Stale-URL or leftover cache is better than failing outright.
                if let cached = loadCachedObjectInfo() {
                    Log.debug("object_info fetch failed (\(error.localizedDescription)); using cached copy")
                    objectInfo = cached
                } else {
                    throw WorkflowPreparationError.objectInfoUnavailable(
                        detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                }
            }
        }

        return try prepareWorkflow(json: json, objectInfo: objectInfo)
    }

    // MARK: - Default Backfill

    /// Backfills missing required inputs in a workflow using defaults from object_info.
    /// Returns the modified workflow and a list of what was injected.
    static func backfillMissingDefaults(
        workflow: [String: Any],
        objectInfo: [String: Any]
    ) -> (workflow: [String: Any], injected: [(nodeID: String, classType: String, inputName: String, value: Any)]) {
        var result = workflow
        var injected: [(nodeID: String, classType: String, inputName: String, value: Any)] = []

        for (nodeID, nodeValue) in workflow {
            guard let nodeDict = nodeValue as? [String: Any],
                  let classType = nodeDict["class_type"] as? String else { continue }

            guard let nodeInfo = objectInfo[classType] as? [String: Any],
                  let inputDefs = nodeInfo["input"] as? [String: Any],
                  let requiredInputs = inputDefs["required"] as? [String: Any] else { continue }

            let currentInputs = nodeDict["inputs"] as? [String: Any] ?? [:]

            for (inputName, inputDefValue) in requiredInputs {
                // Skip if already present in the workflow
                if currentInputs[inputName] != nil { continue }

                guard let inputDef = inputDefValue as? [Any], !inputDef.isEmpty else { continue }

                var defaultValue: Any?

                if let options = inputDef.first as? [String] {
                    // Nested combo: [["option1", "option2", ...]]
                    defaultValue = options.first
                } else if !(inputDef.first is String) {
                    // Combo with Foundation bridging issue — extract first option element-wise
                    if let options = inputDef.first as? [Any], let firstOpt = options.first as? String {
                        defaultValue = firstOpt
                    }
                } else if let typeName = inputDef.first as? String {
                    if let metadata = inputDef.dropFirst().first as? [String: Any] {
                        if let defVal = metadata["default"] {
                            // Widget with explicit default (INT, FLOAT, STRING, BOOLEAN, COMBO)
                            defaultValue = defVal
                        } else if typeName == "COMBO",
                                  let choices = metadata["choices"] as? [String] ?? metadata["options"] as? [String] {
                            // COMBO type without explicit default — use first choice
                            defaultValue = choices.first
                        }
                    } else if !typeName.isEmpty && typeName != typeName.uppercased() {
                        // Flat combo: ["option1", "option2", ...] — first element is the default
                        defaultValue = typeName
                    }
                }
                // else: connection-only or no default — skip

                if let value = defaultValue {
                    injected.append((nodeID: nodeID, classType: classType, inputName: inputName, value: value))
                    Log.debug("Backfill: \(classType) node \(nodeID) — injecting \(inputName) = \(value)")
                }
            }

            // Apply all injections for this node
            let nodeInjections = injected.filter { $0.nodeID == nodeID }
            if !nodeInjections.isEmpty {
                var updatedNode = nodeDict
                var updatedInputs = currentInputs
                for injection in nodeInjections {
                    updatedInputs[injection.inputName] = injection.value
                }
                updatedNode["inputs"] = updatedInputs
                result[nodeID] = updatedNode
            }
        }

        return (result, injected)
    }

    // MARK: - Node Info Fetching

    /// Fetches object_info for specific node class types from the server.
    /// Uses per-node endpoint GET /object_info/{node_class} for efficiency.
    static func fetchNodeInfo(
        classTypes: Set<String>,
        serverURL: String
    ) async -> [String: Any] {
        var merged: [String: Any] = [:]

        await withTaskGroup(of: (String, [String: Any]?).self) { group in
            for classType in classTypes {
                group.addTask {
                    guard let url = ComfyUIEndpoints.objectInfoURL(serverURL: serverURL, classType: classType) else {
                        return (classType, nil)
                    }
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let httpResponse = response as? HTTPURLResponse,
                              httpResponse.statusCode == 200 else { return (classType, nil) }
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            return (classType, json)
                        }
                    } catch {
                        Log.debug("Failed to fetch node info for \(classType): \(error.localizedDescription)")
                    }
                    return (classType, nil)
                }
            }

            for await (_, result) in group {
                if let info = result {
                    for (key, value) in info {
                        merged[key] = value
                    }
                }
            }
        }

        return merged
    }

    // MARK: - Format Detection

    /// Checks if a JSON dictionary is in UI format (has "nodes" array and "links").
    /// Use `convertUIToAPIFormat()` for conversion when object_info is available.
    /// API format has node IDs as keys with "class_type" and "inputs" - this is what we need.
    static func isUIFormat(_ json: [String: Any]) -> Bool {
        return json["nodes"] is [[String: Any]] && json["links"] is [[Any]]
    }

    // MARK: - UI to API Conversion

    /// Converts a ComfyUI UI-format workflow (nodes array + links array) to API format
    /// (dict keyed by node ID with class_type + inputs).
    /// Requires object_info from the server for correct widget value mapping.
    static func convertUIToAPIFormat(
        uiWorkflow: [String: Any],
        objectInfo: [String: Any]
    ) -> (workflow: [String: Any], warnings: [String])? {
        guard let nodes = uiWorkflow["nodes"] as? [[String: Any]],
              let linksRaw = uiWorkflow["links"] as? [[Any]] else { return nil }

        var warnings: [String] = []

        // Phase 1 — Parse links into lookup map
        // linkID -> (fromID, fromSlot, toID, toSlot, type)
        var linkMap: [Int: (fromID: Int, fromSlot: Int, toID: Int, toSlot: Int, type: String)] = [:]
        for link in linksRaw {
            guard link.count >= 6,
                  let linkID = link[0] as? Int,
                  let fromID = link[1] as? Int,
                  let fromSlot = link[2] as? Int,
                  let toID = link[3] as? Int,
                  let toSlot = link[4] as? Int else { continue }
            let type = link[5] as? String ?? ""
            linkMap[linkID] = (fromID, fromSlot, toID, toSlot, type)
        }

        // Phase 2 — Build node lookup and identify special node types
        var nodeByID: [Int: [String: Any]] = [:]
        var rerouteIDs: Set<Int> = []
        var primitiveNodeIDs: Set<Int> = []
        let skipTypes: Set<String> = ["Reroute", "Note", "PrimitiveNode"]

        for node in nodes {
            guard let id = node["id"] as? Int else { continue }
            nodeByID[id] = node
            let type = node["type"] as? String ?? ""
            if type == "Reroute" { rerouteIDs.insert(id) }
            if type == "PrimitiveNode" { primitiveNodeIDs.insert(id) }
        }

        // Phase 3 — Resolve PrimitiveNode values
        var primitiveValues: [Int: Any] = [:]
        for primID in primitiveNodeIDs {
            guard let node = nodeByID[primID],
                  let widgets = node["widgets_values"] as? [Any],
                  !widgets.isEmpty else { continue }
            primitiveValues[primID] = widgets[0]
        }

        // Build set of node IDs that have outgoing links (other nodes depend on them)
        var nodesWithOutgoing: Set<Int> = []
        for (_, link) in linkMap {
            nodesWithOutgoing.insert(link.fromID)
        }

        // Phase 4 — Convert each node
        var apiWorkflow: [String: Any] = [:]

        for node in nodes {
            guard let id = node["id"] as? Int,
                  let classType = node["type"] as? String else { continue }

            // Check mode: 2 = muted, 4 = bypassed
            if let mode = node["mode"] as? Int, mode == 2 { continue }
            if let mode = node["mode"] as? Int, mode == 4 {
                warnings.append("Node \(id) (\(classType)) is bypassed — included but may behave differently than in ComfyUI")
            }

            // Skip special UI-only node types
            if skipTypes.contains(classType) { continue }
            if classType.hasPrefix("workflow/") {
                warnings.append("Group node '\(classType)' cannot be converted. Please ungroup it in ComfyUI.")
                continue
            }

            let idStr = String(id)
            var inputs: [String: Any] = [:]

            // Build connected inputs map from the node's input slots
            var connectedInputs: [String: Int] = [:]  // inputName → linkID
            var convertedWidgets: Set<String> = []
            if let nodeInputs = node["inputs"] as? [[String: Any]] {
                for nodeInput in nodeInputs {
                    guard let name = nodeInput["name"] as? String else { continue }
                    if let linkID = nodeInput["link"] as? Int {
                        connectedInputs[name] = linkID
                    }
                    if nodeInput["widget"] != nil {
                        convertedWidgets.insert(name)
                    }
                }
            }

            // Look up node type in object_info
            guard let nodeInfo = objectInfo[classType] as? [String: Any] else {
                // Unknown node type not in object_info (e.g. subgraph components, missing custom nodes)
                if !nodesWithOutgoing.contains(id) && connectedInputs.isEmpty {
                    // No other node depends on this one AND it has no connections — frontend-only decorative node
                    Log.debug("Skipping frontend-only node '\(classType)' (node \(id)) — not in object_info, no connections")
                    continue
                }

                // Include connections
                for (name, linkID) in connectedInputs {
                    guard let link = linkMap[linkID] else { continue }
                    let (sourceID, sourceSlot) = resolveSource(
                        nodeID: link.fromID, slot: link.fromSlot,
                        linkMap: linkMap, nodeByID: nodeByID, rerouteIDs: rerouteIDs
                    )
                    if primitiveNodeIDs.contains(sourceID), let val = primitiveValues[sourceID] {
                        inputs[name] = val
                    } else {
                        inputs[name] = [String(sourceID), sourceSlot]
                    }
                }

                // Map widget values using the node's own metadata
                let widgetsValues = node["widgets_values"] as? [Any] ?? []
                if !widgetsValues.isEmpty {
                    if let proxyWidgets = (node["properties"] as? [String: Any])?["proxyWidgets"] as? [[Any]] {
                        // Subgraph/component node: proxyWidgets defines widget order
                        // Each entry is [sourceNodeID, widgetName]. "-1" means outer node input.
                        for (idx, proxy) in proxyWidgets.enumerated() where idx < widgetsValues.count {
                            guard proxy.count >= 2,
                                  let sourceID = proxy[0] as? String,
                                  let widgetName = proxy[1] as? String else { continue }
                            // Only map inputs exposed on this node (sourceID == "-1"), skip internal proxied widgets
                            if sourceID == "-1" && connectedInputs[widgetName] == nil {
                                let value = widgetsValues[idx]
                                if !(value is NSNull) {
                                    inputs[widgetName] = value
                                }
                            }
                        }
                    } else if let nodeInputs = node["inputs"] as? [[String: Any]] {
                        // Non-subgraph unknown node: use inputs array with widget property
                        var widgetIdx = 0
                        for nodeInput in nodeInputs {
                            guard let name = nodeInput["name"] as? String,
                                  nodeInput["widget"] != nil else { continue }
                            // Skip connected inputs — already handled above
                            if connectedInputs[name] != nil {
                                widgetIdx += 1
                                continue
                            }
                            if widgetIdx < widgetsValues.count {
                                let value = widgetsValues[widgetIdx]
                                if !(value is NSNull) {
                                    inputs[name] = value
                                }
                                widgetIdx += 1
                            }
                        }
                    }
                    Log.debug("Mapped \(inputs.count) inputs for unknown node '\(classType)' (node \(id)) using widget values")
                }

                apiWorkflow[idStr] = ["class_type": classType, "inputs": inputs]
                continue
            }

            // Get input_order and input definitions
            let inputOrder = nodeInfo["input_order"] as? [String: Any]
            let inputDefs = nodeInfo["input"] as? [String: Any]
            let requiredDefs = inputDefs?["required"] as? [String: Any] ?? [:]
            let optionalDefs = inputDefs?["optional"] as? [String: Any] ?? [:]

            let requiredOrder = inputOrder?["required"] as? [String] ?? []
            let optionalOrder = inputOrder?["optional"] as? [String] ?? []
            // Skip "hidden" entirely — hidden inputs don't consume widgets_values
            var orderedInputNames = requiredOrder + optionalOrder

            // Detect incomplete input_order: inputs defined but not listed in order.
            // Some ComfyUI versions/custom nodes omit combo inputs from input_order.
            // Fall back to NSDictionary key enumeration (preserves JSON insertion order).
            let orderedSet = Set(orderedInputNames)
            let inputRawDict = nodeInfo["input"] as? NSDictionary
            let reqOrderedKeys = (inputRawDict?["required"] as? NSDictionary)?.allKeys as? [String]
                ?? Array(requiredDefs.keys)
            let optOrderedKeys = (inputRawDict?["optional"] as? NSDictionary)?.allKeys as? [String]
                ?? Array(optionalDefs.keys)

            let missingFromOrder = (reqOrderedKeys + optOrderedKeys).filter { !orderedSet.contains($0) }
            if !missingFromOrder.isEmpty {
                Log.debug("input_order incomplete for \(classType) node \(id): missing \(missingFromOrder); using definition key order")
                orderedInputNames = reqOrderedKeys + optOrderedKeys
            }

            let widgetsValues = node["widgets_values"] as? [Any] ?? []
            var widgetIdx = 0

            if orderedInputNames.isEmpty && inputOrder == nil {
                // No input_order available — fall back to connections-only
                warnings.append("No input_order for '\(classType)' (node \(id)) — connections only")
                for (name, linkID) in connectedInputs {
                    guard let link = linkMap[linkID] else { continue }
                    let (sourceID, sourceSlot) = resolveSource(
                        nodeID: link.fromID, slot: link.fromSlot,
                        linkMap: linkMap, nodeByID: nodeByID, rerouteIDs: rerouteIDs
                    )
                    if primitiveNodeIDs.contains(sourceID), let val = primitiveValues[sourceID] {
                        inputs[name] = val
                    } else {
                        inputs[name] = [String(sourceID), sourceSlot]
                    }
                }
                apiWorkflow[idStr] = ["class_type": classType, "inputs": inputs]
                continue
            }

            // Walk input_order (required + optional, NOT hidden)
            for inputName in orderedInputNames {
                let inputDefRaw = requiredDefs[inputName] ?? optionalDefs[inputName]
                let inputDef = inputDefRaw as? [Any]
                let isWidget: Bool
                if let inputDef = inputDef {
                    isWidget = isWidgetType(inputDef)
                } else if inputDefRaw != nil {
                    // inputDef bridging failed (Foundation/Swift type mismatch)
                    // Safe default: treat as widget so we consume a widgets_values entry
                    // (skipping a widget causes all subsequent values to shift)
                    Log.debug("  inputDef bridging failed for \(classType).\(inputName): \(type(of: inputDefRaw!))")
                    isWidget = true
                } else {
                    isWidget = false
                }
                let isConverted = convertedWidgets.contains(inputName)

                // Resolve connection: linkID must exist AND be valid in linkMap
                let resolvedLink: (nodeID: Int, slot: Int)?
                if let linkID = connectedInputs[inputName], let link = linkMap[linkID] {
                    resolvedLink = resolveSource(
                        nodeID: link.fromID, slot: link.fromSlot,
                        linkMap: linkMap, nodeByID: nodeByID, rerouteIDs: rerouteIDs
                    )
                } else {
                    resolvedLink = nil
                }

                if let source = resolvedLink {
                    // Connected input — emit link or primitive value
                    if primitiveNodeIDs.contains(source.nodeID), let val = primitiveValues[source.nodeID] {
                        inputs[inputName] = val
                    } else {
                        inputs[inputName] = [String(source.nodeID), source.slot]
                    }

                    // If it's a widget type but NOT a converted widget, value is still in widgets_values
                    if isWidget && !isConverted {
                        if widgetIdx < widgetsValues.count { widgetIdx += 1 }
                        advancePastControlAfterGenerate(
                            inputName: inputName, inputDef: inputDef,
                            widgetsValues: widgetsValues, widgetIdx: &widgetIdx
                        )
                    }
                    // Converted widgets had their value removed from widgets_values — don't advance
                } else if isWidget && !isConverted {
                    // Not connected, widget type, not converted — pop value from widgets_values
                    if widgetIdx < widgetsValues.count {
                        let value = widgetsValues[widgetIdx]
                        widgetIdx += 1
                        if !(value is NSNull) {
                            inputs[inputName] = value
                        }
                    }
                    advancePastControlAfterGenerate(
                        inputName: inputName, inputDef: inputDef,
                        widgetsValues: widgetsValues, widgetIdx: &widgetIdx
                    )
                }
                // Converted widget not connected: value was removed from widgets_values — skip
                // Connection-only type not connected: skip

            }

            // Confidence check
            if widgetIdx != widgetsValues.count {
                Log.debug("Widget count mismatch for \(classType) node \(id): consumed \(widgetIdx), got \(widgetsValues.count)")
            }

            apiWorkflow[idStr] = ["class_type": classType, "inputs": inputs]
        }

        return (apiWorkflow, warnings)
    }

    // MARK: - Conversion Helpers

    /// Follows Reroute chains to find the real source node and output slot
    private static func resolveSource(
        nodeID: Int, slot: Int,
        linkMap: [Int: (fromID: Int, fromSlot: Int, toID: Int, toSlot: Int, type: String)],
        nodeByID: [Int: [String: Any]],
        rerouteIDs: Set<Int>
    ) -> (nodeID: Int, slot: Int) {
        var currentID = nodeID
        var currentSlot = slot
        var visited: Set<Int> = []

        while rerouteIDs.contains(currentID) {
            if visited.contains(currentID) { break }  // Prevent infinite loops
            visited.insert(currentID)

            // Find the link going INTO this reroute node
            guard let rerouteNode = nodeByID[currentID],
                  let rerouteInputs = rerouteNode["inputs"] as? [[String: Any]],
                  let firstInput = rerouteInputs.first,
                  let incomingLinkID = firstInput["link"] as? Int,
                  let incomingLink = linkMap[incomingLinkID] else { break }

            currentID = incomingLink.fromID
            currentSlot = incomingLink.fromSlot
        }

        return (currentID, currentSlot)
    }

    /// Determines if an input definition represents a widget type (consumes a widgets_values entry)
    /// vs a connection-only type (MODEL, LATENT, IMAGE, etc.)
    private static func isWidgetType(_ inputDef: [Any]?) -> Bool {
        guard let inputDef = inputDef, !inputDef.isEmpty else { return false }
        let first = inputDef[0]

        if let typeName = first as? String {
            switch typeName {
            case "INT", "FLOAT", "STRING", "BOOLEAN", "IMAGEUPLOAD", "COMBO":
                return true
            default:
                // Distinguish connection types from flat combo arrays.
                // Connection types are always ALL UPPERCASE: IMAGE, MODEL, LATENT, etc.
                // Flat combo options contain lowercase: nearest-exact, euler, lanczos, etc.
                // Some object_info stores combos as ["opt1","opt2"] instead of [["opt1","opt2"]]
                let isUpperOnly = !typeName.isEmpty && typeName == typeName.uppercased()
                return !isUpperOnly
            }
        }

        // First element is NOT a string → nested combo/dropdown options array.
        return true
    }

    /// Checks if a value is a control_after_generate phantom entry
    private static func isControlAfterGenerateValue(_ value: Any) -> Bool {
        guard let str = value as? String else { return false }
        return ["fixed", "increment", "decrement", "randomize"].contains(str)
    }

    /// Advances widgetIdx past a control_after_generate phantom value if present
    private static func advancePastControlAfterGenerate(
        inputName: String,
        inputDef: [Any]?,
        widgetsValues: [Any],
        widgetIdx: inout Int
    ) {
        // Check metadata from object_info first (most robust)
        if let inputDef = inputDef, inputDef.count >= 2,
           let metadata = inputDef[1] as? [String: Any],
           metadata["control_after_generate"] != nil {
            if widgetIdx < widgetsValues.count,
               isControlAfterGenerateValue(widgetsValues[widgetIdx]) {
                widgetIdx += 1
            }
            return
        }

        // Fallback: check by name for older object_info that may lack the flag
        if ["seed", "noise_seed"].contains(inputName.lowercased()) {
            if widgetIdx < widgetsValues.count,
               isControlAfterGenerateValue(widgetsValues[widgetIdx]) {
                widgetIdx += 1
            }
        }
    }

    // MARK: - Pre-Submit Validation

    /// Structural check that a stored workflow is API-shaped (safe to POST to /prompt).
    /// Returns nil when valid, otherwise a short description of the problem.
    static func validateAPIShape(_ workflow: [String: Any]) -> String? {
        if workflow.isEmpty {
            return "The workflow is empty."
        }
        if isUIFormat(workflow) {
            return "The workflow is still in ComfyUI's UI (editor) format — it has top-level 'nodes' and 'links' arrays instead of API-format node entries."
        }
        if workflow["nodes"] != nil || workflow["links"] != nil {
            return "The workflow contains top-level 'nodes'/'links' data left over from ComfyUI's UI format."
        }

        var nodeCount = 0
        var missingClassType: [String] = []
        for (key, value) in workflow {
            guard let nodeDict = value as? [String: Any] else { continue }
            nodeCount += 1
            if nodeDict["class_type"] as? String == nil {
                missingClassType.append(key)
            }
        }
        if nodeCount == 0 {
            return "No nodes found — API-format workflows map node IDs to entries with 'class_type' and 'inputs'."
        }
        if !missingClassType.isEmpty {
            let sample = missingClassType.sorted().prefix(5).joined(separator: ", ")
            return "\(missingClassType.count) node entr\(missingClassType.count == 1 ? "y is" : "ies are") missing 'class_type' (\(sample))."
        }
        return nil
    }

    /// Lists required inputs that are absent from an (already backfilled) API-format
    /// workflow, according to the server's object_info. Nodes whose class_type is not in
    /// object_info are skipped. Each entry reads "Node <id> (<class_type>): <input>".
    static func missingRequiredInputs(
        workflow: [String: Any],
        objectInfo: [String: Any],
        restrictTo reachable: Set<String>? = nil
    ) -> [String] {
        var missing: [String] = []
        for (nodeID, nodeValue) in workflow {
            // ComfyUI only executes the dependency chains of output nodes, so orphaned
            // nodes never trigger a server-side validation error. When a reachable set is
            // supplied, skip anything the server would never run. (finding #1)
            if let reachable = reachable, !reachable.contains(nodeID) { continue }
            guard let nodeDict = nodeValue as? [String: Any],
                  let classType = nodeDict["class_type"] as? String,
                  let nodeInfo = objectInfo[classType] as? [String: Any],
                  let inputDefs = nodeInfo["input"] as? [String: Any],
                  let requiredInputs = inputDefs["required"] as? [String: Any] else { continue }

            let currentInputs = nodeDict["inputs"] as? [String: Any] ?? [:]
            for inputName in requiredInputs.keys where currentInputs[inputName] == nil {
                missing.append("Node \(nodeID) (\(classType)): \(inputName)")
            }
        }
        return missing.sorted()
    }

    /// True when a node class_type matches an output (Save/Preview) pattern. Mirrors the
    /// detection in `GenerationState.isOutputNode` so reachability can be computed here
    /// without a GenerationState instance.
    static func isOutputNodeClass(_ classType: String) -> Bool {
        let lower = classType.lowercased()
        if lower.contains("saveimage") || lower.contains("previewimage") { return true }
        if lower.contains("savevideo") || lower.contains("videosave") { return true }
        if lower.contains("videocombine") || lower.contains("combinevideo") { return true }
        if lower.contains("savegif") || lower.contains("gifsave") { return true }
        if lower.contains("savewebm") || lower.contains("webmsave") { return true }
        if lower.contains("saveanimated") { return true }
        return false
    }

    /// Node IDs reachable (via backward link traversal) from every output-class node in an
    /// API-format workflow — i.e. the nodes ComfyUI would actually execute. Returns `nil`
    /// when no output node is present, signalling the caller can't safely prune (validate
    /// everything). Cycle-safe. (finding #1)
    static func reachableFromOutputs(workflow: [String: Any]) -> Set<String>? {
        func linkSourceID(_ value: Any?) -> String? {
            guard let link = value as? [Any], link.count == 2 else { return nil }
            if let id = link[0] as? String { return id }
            if let id = link[0] as? Int { return String(id) }
            return nil
        }

        // Roots: all output-class nodes (safest — includes the selected one and any siblings).
        var frontier: [String] = []
        for (nodeID, nodeValue) in workflow {
            guard let nodeDict = nodeValue as? [String: Any],
                  let classType = nodeDict["class_type"] as? String else { continue }
            if isOutputNodeClass(classType) { frontier.append(nodeID) }
        }
        guard !frontier.isEmpty else { return nil }

        var reachable: Set<String> = []
        while let id = frontier.popLast() {
            guard !reachable.contains(id) else { continue }
            reachable.insert(id)
            guard let node = workflow[id] as? [String: Any],
                  let inputs = node["inputs"] as? [String: Any] else { continue }
            for (_, value) in inputs {
                if let sourceID = linkSourceID(value) { frontier.append(sourceID) }
            }
        }
        return reachable
    }

    // MARK: - Conditioning Role Classification

    /// Traces which prompt nodes feed `positive` vs `negative` conditioning inputs in an
    /// API-format workflow. Any node with a link-valued `positive`/`negative` input
    /// (KSampler variants, ControlNetApply, etc.) is used as a trace root; links are
    /// followed upstream (depth-capped, cycle-safe) until a prompt node is reached.
    /// A node appearing only in `negative` should never be auto-selected as the prompt node.
    static func classifyConditioningRoles(
        apiWorkflow: [String: Any],
        isPromptNode: (String) -> Bool
    ) -> (positive: Set<String>, negative: Set<String>) {
        func linkSourceID(_ value: Any?) -> String? {
            guard let link = value as? [Any], link.count == 2 else { return nil }
            if let id = link[0] as? String { return id }
            if let id = link[0] as? Int { return String(id) }
            return nil
        }

        func trace(from nodeID: String, into set: inout Set<String>) {
            var visited: Set<String> = []
            var frontier: [String] = [nodeID]
            var depth = 0
            while !frontier.isEmpty && depth < 8 {
                var next: [String] = []
                for id in frontier {
                    guard !visited.contains(id) else { continue }
                    visited.insert(id)
                    guard let node = apiWorkflow[id] as? [String: Any],
                          let classType = node["class_type"] as? String else { continue }
                    if isPromptNode(classType) {
                        set.insert(id)
                        continue
                    }
                    for (_, value) in (node["inputs"] as? [String: Any]) ?? [:] {
                        if let sourceID = linkSourceID(value) {
                            next.append(sourceID)
                        }
                    }
                }
                frontier = next
                depth += 1
            }
        }

        var positive: Set<String> = []
        var negative: Set<String> = []
        for (_, nodeValue) in apiWorkflow {
            guard let nodeDict = nodeValue as? [String: Any],
                  nodeDict["class_type"] is String,
                  let inputs = nodeDict["inputs"] as? [String: Any] else { continue }
            if let sourceID = linkSourceID(inputs["positive"]) {
                trace(from: sourceID, into: &positive)
            }
            if let sourceID = linkSourceID(inputs["negative"]) {
                trace(from: sourceID, into: &negative)
            }
        }
        return (positive, negative)
    }
}
