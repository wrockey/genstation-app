#if os(macOS)
import Foundation
import GenStationCore

@MainActor
enum AgentStyleService {
    private static func entries(_ app: AppState) throws -> [(id: String, style: PromptStyle, source: String)] {
        guard let db = StyleManager.shared.database else { throw AgentImageError("The bundled style palette could not be loaded.") }
        var rows: [(String, PromptStyle, String)] = []
        var seen = Set<String>()
        for style in db.categories.flatMap(\.subcategories).flatMap(\.allGroups).flatMap(\.styles) {
            let id = "builtin:" + style.id
            if seen.insert(id).inserted { rows.append((id, style, "builtin")) }
        }
        for style in app.ui.customStyles {
            let id = "custom:" + style.id
            if seen.insert(id).inserted { rows.append((id, style, "custom")) }
        }
        return rows
    }

    static func list(_ params: [String: Any], app: AppState) throws -> [String: Any] {
        guard Set(params.keys).isSubset(of: ["query", "source"]),
              params["query"] == nil || params["query"] is String,
              params["source"] == nil || ["builtin", "custom"].contains(params["source"] as? String ?? "") else {
            throw AgentImageError("Use optional query text and source builtin or custom.")
        }
        let query = (params["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.utf8.count <= 1000 else { throw AgentImageError("Search query is too long.") }
        let rows = try entries(app).filter { row in
            (params["source"] == nil || row.source == params["source"] as? String) &&
            (query.isEmpty || ([row.style.name] + row.style.tags).joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
        return ["styles": rows.map { ["style_id": $0.id, "name": $0.style.name, "tags": $0.style.tags, "source": $0.source] as [String: Any] },
                "count": rows.count, "generation_submitted": false]
    }

    static func compose(_ params: [String: Any], app: AppState) throws -> [String: Any] {
        guard Set(params.keys) == ["prompt", "style_ids"], let prompt = params["prompt"] as? String,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.utf8.count <= 32_000,
              let ids = params["style_ids"] as? [String], ids.count <= 12, Set(ids).count == ids.count else {
            throw AgentImageError("Use prompt (1–32,000 UTF-8 bytes) and up to 12 distinct style_ids, in the order to apply them.")
        }
        let rows = try entries(app)
        let selected = try ids.map { id -> PromptStyle in
            guard let row = rows.first(where: { $0.id == id }) else { throw AgentImageError("Unknown style_id. Discover current IDs with list_styles.") }
            return row.style
        }
        let composed = StyleManager.applyStyles(selected, to: prompt)
        guard composed.utf8.count <= 32_000 else { throw AgentImageError("Combined prompt exceeds 32,000 UTF-8 bytes.") }
        return ["prompt": composed, "negative_prompt": StyleManager.combineNegativePrompts(selected), "style_ids": ids,
                "generation_submitted": false, "ui_selection_changed": false,
                "instructions": "Use this exact prompt with image preflight/generation or a saved workflow prompt override. Negative prompt is separate: use it only if the selected model schema accepts negative_prompt; saved workflow overrides do not apply it. Freeze returned text when assigning a request_id."]
    }
}
#endif
