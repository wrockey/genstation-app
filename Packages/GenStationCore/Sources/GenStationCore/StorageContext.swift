import Foundation

/// Storage identities are build-selected, never supplied by a graph, agent or imported file.
public struct StorageContext: Equatable, Sendable {
    public static let productionID = "art.genstation.app"
    public static let demoID = "art.genstation.demo"
    public let bundleID: String
    public let isDemo: Bool
    public let supportDirectory: URL
    public let outputDirectory: URL
    public let temporaryDirectory: URL
    public var keychainService: String { bundleID }
    public var historyURL: URL { supportDirectory.appendingPathComponent("history_v2.json") }
    public var stylesURL: URL { supportDirectory.appendingPathComponent("custom_styles.json") }
    public var agentDirectory: URL {
        isDemo ? supportDirectory : supportDirectory.deletingLastPathComponent().appendingPathComponent(Self.productionID)
    }
    public var socketURL: URL { agentDirectory.appendingPathComponent("mcp.sock") }

    public enum ConfigurationError: Error { case invalidDemoIdentity }

    public init(bundleID: String, demoEnabled: Bool, applicationSupport: URL,
                documents: URL, temporary: URL) throws {
        // A demo bundle must explicitly opt in; a production bundle cannot opt in.
        guard demoEnabled == (bundleID == Self.demoID) else {
            throw ConfigurationError.invalidDemoIdentity
        }
        self.bundleID = bundleID
        self.isDemo = demoEnabled
        supportDirectory = applicationSupport.appendingPathComponent(bundleID, isDirectory: true)
        outputDirectory = demoEnabled
            ? supportDirectory.appendingPathComponent("Originals", isDirectory: true)
            : documents.appendingPathComponent("GenStation", isDirectory: true)
        temporaryDirectory = demoEnabled
            ? supportDirectory.appendingPathComponent("Staging", isDirectory: true)
            : temporary
    }
}
