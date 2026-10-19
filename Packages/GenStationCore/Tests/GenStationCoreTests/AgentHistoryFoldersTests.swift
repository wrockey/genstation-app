import XCTest
@testable import GenStationCore

final class AgentHistoryFoldersTests: XCTestCase {
    func testCreateReplayRenameAndRoundTrip() throws {
        let id = UUID(), child = UUID()
        var entries = try AgentHistoryFolders.create([], id: id, name: "Task", parent: nil)
        XCTAssertEqual(try AgentHistoryFolders.create(entries, id: id, name: "Task", parent: nil), entries)
        entries = try AgentHistoryFolders.create(entries, id: child, name: "Revision", parent: id)
        entries = try AgentHistoryFolders.rename(entries, id: id, expectedName: "Task", newName: "Study")
        XCTAssertEqual(try AgentHistoryFolders.rename(entries, id: id, expectedName: "Task", newName: "Study"), entries)
        XCTAssertThrowsError(try AgentHistoryFolders.rename(entries, id: id, expectedName: "Task", newName: "Other"))
        XCTAssertThrowsError(try AgentHistoryFolders.create(entries, id: id, name: "Other", parent: nil))
        let restored = try JSONDecoder().decode([HistoryEntry].self, from: JSONEncoder().encode(entries))
        XCTAssertEqual(AgentHistoryFolders.folders(restored).count, 2)
        XCTAssertEqual(AgentHistoryFolders.folders(restored)[1].1, id)
    }
    func testAtomicScopedMoveKeepsPrivateContentsAndOriginalIdentity() throws {
        let source = UUID(), target = UUID()
        var asset = HistoryItem(prompt: "private prompt", imagePath: "/original.png", date: Date(), parentItemId: UUID())
        asset.agentGenerated = true
        let hidden = HistoryItem(prompt: "unshared", date: Date())
        let initial: [HistoryEntry] = [.folder(Folder(id: source, name: "Source", children: [.item(asset), .item(hidden)])), .folder(Folder(id: target, name: "Target"))]
        let allowed: (UUID) -> Bool = { $0 == asset.id }
        XCTAssertThrowsError(try AgentHistoryFolders.move(initial, ids: [asset.id, hidden.id], parent: target, allowed: allowed))
        XCTAssertEqual(initial.flatMap(\.allItems), [asset, hidden])
        let moved = try AgentHistoryFolders.move(initial, ids: [asset.id], parent: target, allowed: allowed)
        XCTAssertEqual(AgentHistoryFolders.folders(moved)[0].0.children, [.item(hidden)])
        XCTAssertEqual(AgentHistoryFolders.folders(moved)[1].0.children, [.item(asset)])
        XCTAssertEqual(try AgentHistoryFolders.move(moved, ids: [asset.id], parent: target, allowed: allowed), moved)
        let root = try AgentHistoryFolders.move(moved, ids: [asset.id], parent: nil, allowed: allowed)
        XCTAssertEqual(root.last, .item(asset))
        XCTAssertThrowsError(try AgentHistoryFolders.move(root, ids: [asset.id], parent: UUID(), allowed: allowed))
        XCTAssertThrowsError(try AgentHistoryFolders.move(root, ids: [asset.id], parent: source, allowed: { _ in false }))
        XCTAssertThrowsError(try AgentHistoryFolders.move(root, ids: [source], parent: target, allowed: { _ in true }))
    }
    func testPersistenceFailureLeavesPriorSnapshotIntact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original: [HistoryEntry] = [.folder(Folder(name: "Original"))]
        let file = directory.appendingPathComponent("history.json")
        try AgentHistoryFolders.persist(original, to: file)
        let bytes = try Data(contentsOf: file)
        // A file cannot be a parent directory; no permissions or global state needed.
        XCTAssertThrowsError(try AgentHistoryFolders.persist([], to: file.appendingPathComponent("child.json")))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testManifestCanonicalHashAndUnknownMetadataRoundTrip() throws {
        let bytes = Data("abc".utf8), id = UUID()
        let manifest = AgentAssetManifest(assetID: id, data: bytes, mediaType: "image/png", width: 1, height: 1, model: "test", prompt: "private prompt")
        XCTAssertEqual(manifest.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(manifest.byteCount, 3)
        XCTAssertEqual(manifest.json["seed_status"] as? String, "unknown")
        XCTAssertNil(manifest.json["prompt"])
        XCTAssertEqual(try JSONDecoder().decode(AgentAssetManifest.self, from: JSONEncoder().encode(manifest)), manifest)
        XCTAssertNotEqual(manifest.sha256, AgentAssetManifest(assetID: id, data: Data("changed".utf8), mediaType: "image/png", width: nil, height: nil, model: nil, prompt: "private prompt").sha256)
    }
}
