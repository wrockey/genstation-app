import Foundation
import GenStationCore

/// Initialized before the first settings/history/keychain read. No environment override
/// can turn the shipping app into a demo or redirect it to another user's library.
enum AppStorageContext {
    private static var demoLease: DemoWorkspaceLease?
    static let current: StorageContext = {
        let files = FileManager.default
        guard let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let documents = files.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("GenStation storage directories are unavailable.")
        }
        do {
            let demoFlag = Bundle.main.object(forInfoDictionaryKey: "GenStationDemoStorageEnabled")
            let context = try StorageContext(
                bundleID: Bundle.main.bundleIdentifier ?? StorageContext.productionID,
                demoEnabled: (demoFlag as? Bool == true) || (demoFlag as? String == "YES"),
                applicationSupport: support, documents: documents, temporary: files.temporaryDirectory)
            if context.isDemo {
                // Require the dedicated sandbox container, not an unsandboxed build
                // with a changed bundle ID that still shares external locations.
                guard NSHomeDirectory().contains("/Library/Containers/art.genstation.demo/Data") else {
                    fatalError("Demo storage requires the dedicated sandbox container.")
                }
                let lease = try DemoWorkspaceLease(context: context)
                try lease.prepare()
                demoLease = lease
            }
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--genstation-demo-reset") {
                guard let lease = demoLease else { throw DemoWorkspaceLease.Failure.productionTarget }
                try lease.reset()
                UserDefaults.standard.removePersistentDomain(forName: StorageContext.demoID)
            }
            try files.createDirectory(at: context.supportDirectory, withIntermediateDirectories: true)
            if context.isDemo {
                try files.createDirectory(at: context.outputDirectory, withIntermediateDirectories: true)
                try files.createDirectory(at: context.temporaryDirectory, withIntermediateDirectories: true)
            }
            if let index = arguments.firstIndex(of: "--genstation-demo-seed") {
                guard let lease = demoLease, arguments.indices.contains(index + 1) else {
                    throw DemoWorkspaceLease.Failure.productionTarget
                }
                try DemoSeed.install(manifest: URL(fileURLWithPath: arguments[index + 1]), context: context, lease: lease)
            }
            return context
        } catch {
            fatalError("GenStation storage configuration failed: \(error)")
        }
    }()

    /// The dedicated bundle/container isolates standard defaults, including system-owned
    /// window restoration. All app reads explicitly initialize/validate the context first.
    static var defaults: UserDefaults {
        _ = current
        return .standard
    }

    static var fallbackOutputDirectory: URL? {
        current.isDemo ? current.outputDirectory
            : FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    static func permitsOriginal(_ url: URL) -> Bool {
        !current.isDemo || url.resolvingSymlinksInPath().path.hasPrefix(current.supportDirectory.resolvingSymlinksInPath().path + "/")
    }
}
