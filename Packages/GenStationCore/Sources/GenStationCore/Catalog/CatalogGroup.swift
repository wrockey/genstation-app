import Foundation

/// One family's worth of selectable models. **Data only** — no `Color`, no `Image`, no SwiftUI,
/// AppKit or UIKit type. The picker maps this onto sections; MCP maps it onto a list; neither
/// shape belongs in the package (`PackageBoundaryTests` enforces the framework half of that).
///
/// It is a value rather than a `[String: [CatalogModel]]` so the ordering `selectable(task:)`
/// establishes — families by name, models by id — survives being passed around. A dictionary
/// would throw it away at the first hop.
public struct CatalogGroup: Sendable, Hashable {
    public let family: String
    public let models: [CatalogModel]

    public init(family: String, models: [CatalogModel]) {
        self.family = family
        self.models = models
    }
}
