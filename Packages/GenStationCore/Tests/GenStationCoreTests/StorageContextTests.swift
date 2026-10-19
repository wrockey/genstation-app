import XCTest
@testable import GenStationCore

final class StorageContextTests: XCTestCase {
    private func context(_ id: String, demo: Bool) throws -> StorageContext {
        try StorageContext(bundleID: id, demoEnabled: demo,
                           applicationSupport: URL(fileURLWithPath: "/sentinel/Support"),
                           documents: URL(fileURLWithPath: "/sentinel/Documents"),
                           temporary: URL(fileURLWithPath: "/sentinel/Temporary"))
    }

    func testProductionPathsRemainCompatible() throws {
        let value = try context(StorageContext.productionID, demo: false)
        XCTAssertEqual(value.historyURL.path, "/sentinel/Support/art.genstation.app/history_v2.json")
        XCTAssertEqual(value.socketURL.path, "/sentinel/Support/art.genstation.app/mcp.sock")
        XCTAssertEqual(value.outputDirectory.path, "/sentinel/Documents/GenStation")
        XCTAssertEqual(value.temporaryDirectory.path, "/sentinel/Temporary")
        XCTAssertEqual(value.keychainService, StorageContext.productionID)
    }

    func testDemoNamespacesNeverUseProductionLocations() throws {
        let production = try context(StorageContext.productionID, demo: false)
        let demo = try context(StorageContext.demoID, demo: true)
        XCTAssertNotEqual(demo.keychainService, production.keychainService)
        XCTAssertNotEqual(demo.agentDirectory, production.agentDirectory)
        for url in [demo.historyURL, demo.stylesURL, demo.socketURL, demo.outputDirectory, demo.temporaryDirectory] {
            XCTAssertTrue(url.path.hasPrefix("/sentinel/Support/art.genstation.demo/"))
        }
    }

    func testMismatchedDemoConfigurationFailsClosed() {
        XCTAssertThrowsError(try context(StorageContext.productionID, demo: true))
        XCTAssertThrowsError(try context(StorageContext.demoID, demo: false))
        XCTAssertThrowsError(try context("unknown", demo: true))
    }

    func testLeaseRejectsProductionConcurrentAccessAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let production = try StorageContext(bundleID: StorageContext.productionID, demoEnabled: false,
                                            applicationSupport: root, documents: root, temporary: root)
        let demo = try StorageContext(bundleID: StorageContext.demoID, demoEnabled: true,
                                      applicationSupport: root, documents: root, temporary: root)
        try FileManager.default.createDirectory(at: production.supportDirectory, withIntermediateDirectories: true)
        let sentinel = production.historyURL
        try Data("production sentinel".utf8).write(to: sentinel)
        XCTAssertThrowsError(try DemoWorkspaceLease(context: production))
        var lease: DemoWorkspaceLease? = try DemoWorkspaceLease(context: demo)
        XCTAssertThrowsError(try DemoWorkspaceLease(context: demo))
        try FileManager.default.createDirectory(at: demo.supportDirectory, withIntermediateDirectories: true)
        try lease?.validateTree()
        let link = demo.supportDirectory.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: production.supportDirectory)
        XCTAssertThrowsError(try lease?.validateTree())
        try FileManager.default.removeItem(at: link)
        lease = nil
        let reopened = try DemoWorkspaceLease(context: demo)
        try reopened.validateTree()
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("production sentinel".utf8))
    }

    func testSeedResetAndRestartPreserveProductionSentinel() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let context = try StorageContext(bundleID: StorageContext.demoID, demoEnabled: true,
                                         applicationSupport: root, documents: root, temporary: root)
        let sentinel = root.appendingPathComponent("production-history.json")
        try Data("sentinel".utf8).write(to: sentinel)
        var lease: DemoWorkspaceLease? = try DemoWorkspaceLease(context: context)
        try lease?.prepare()
        let manifest = root.appendingPathComponent("seed.json")
        let assetID = UUID()
        let record: [String: Any] = ["id": assetID.uuidString, "relativePath": "image.png", "title": "Fixture", "provenance": "Test-only imported artwork", "importedAt": "2026-09-14T00:00:00Z"]
        try JSONSerialization.data(withJSONObject: ["version": 1, "assets": [record]]).write(to: manifest)
        // Missing media must fail before writing history or originals.
        XCTAssertThrowsError(try DemoSeed.install(manifest: manifest, context: context, lease: lease!))
        XCTAssertFalse(files.fileExists(atPath: context.historyURL.path))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        try png.write(to: root.appendingPathComponent("image.png"))
        try DemoSeed.install(manifest: manifest, context: context, lease: lease!)
        XCTAssertThrowsError(try DemoSeed.install(manifest: manifest, context: context, lease: lease!))
        lease = nil
        lease = try DemoWorkspaceLease(context: context)
        try lease?.prepare()
        let result = try HistoryFile.decode(Data(contentsOf: context.historyURL))
        guard case .item(var item) = try XCTUnwrap(result.entries.first) else { return XCTFail("Missing imported item") }
        XCTAssertEqual(item.id, assetID)
        XCTAssertNil(item.jobId)
        XCTAssertNil(item.costUSD)
        XCTAssertNil(item.agentGenerated)
        XCTAssertTrue(item.responseText.contains("Imported demo artwork"))
        item.status = .queued
        try HistoryFile.encode([.item(item)]).write(to: context.historyURL, options: .atomic)
        XCTAssertThrowsError(try lease?.reset())
        item.status = nil
        try HistoryFile.encode([.item(item)]).write(to: context.historyURL, options: .atomic)
        let backup = try XCTUnwrap(lease?.reset())
        XCTAssertTrue(files.fileExists(atPath: backup.appendingPathComponent("history_v2.json").path))
        XCTAssertFalse(files.fileExists(atPath: context.historyURL.path))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("sentinel".utf8))
        lease = nil
        lease = try DemoWorkspaceLease(context: context)
        try lease?.prepare()
    }
}
