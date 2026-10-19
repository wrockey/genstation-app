import XCTest
@testable import GenStationCore

final class WorkflowLibraryStoreTests: XCTestCase {
    private func withStore(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("workflows_v1.json"))
    }
    private func workflow(_ name: String = "Same name") -> SavedWorkflow {
        SavedWorkflow(name: name, workflowJSON: Data("{}".utf8))
    }

    func testUpdatePreservesIdentityAndCopyDoesNotUseNameAsIdentity() throws {
        try withStore { url in
            var store = try WorkflowLibraryStore(fileURL: url)
            let first = try store.save(workflow())
            let updated = try store.save(workflow("Renamed"), replacingID: first.id)
            XCTAssertEqual(updated.id, first.id)
            XCTAssertEqual(updated.dateAdded, first.dateAdded)
            XCTAssertEqual(updated.revision, 2)
            let copy = try store.save(workflow("Renamed"))
            XCTAssertNotEqual(copy.id, first.id)
            XCTAssertEqual(store.workflows.count, 2)
            let reloaded = try WorkflowLibraryStore(fileURL: url)
            XCTAssertEqual(reloaded.workflows, store.workflows)
            XCTAssertThrowsError(try store.save(workflow(), replacingID: UUID()))
            XCTAssertEqual(store.workflows.count, 2)
        }
    }

    func testRetentionBeyondTenWithSeparateRecents() throws {
        try withStore { url in
            var store = try WorkflowLibraryStore(fileURL: url)
            for index in 0..<15 { _ = try store.save(workflow("Workflow \(index)")) }
            let first = store.workflows[0]
            try store.markUsed(id: first.id, now: Date.distantFuture)
            XCTAssertEqual(store.recentWorkflows.first?.id, first.id)
            XCTAssertEqual(store.recentWorkflows.count, 10)
            XCTAssertEqual(try WorkflowLibraryStore(fileURL: url).workflows.count, 15)
        }
    }

    func testLegacyMigrationAndCorruptStoreProtection() throws {
        try withStore { url in
            let item = workflow()
            // Actual old schema has no revision field.
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode([item])) as! [[String: Any]]
            object[0].removeValue(forKey: "revision")
            let legacy = try JSONSerialization.data(withJSONObject: object)
            let migrated = try WorkflowLibraryStore(fileURL: url, legacyData: legacy)
            XCTAssertEqual(migrated.workflows.first?.id, item.id)
            XCTAssertEqual(migrated.workflows.first?.revision, 1)
            let corrupt = Data("unreadable".utf8)
            try corrupt.write(to: url)
            XCTAssertThrowsError(try WorkflowLibraryStore(fileURL: url, legacyData: legacy))
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
        }
        try withStore { url in
            XCTAssertThrowsError(try WorkflowLibraryStore(fileURL: url, legacyData: Data("broken".utf8)))
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            let duplicate = workflow()
            XCTAssertThrowsError(try WorkflowLibraryStore(fileURL: url, legacyData: JSONEncoder().encode([duplicate, duplicate])))
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testWriteFailureLeavesSnapshotUnchanged() throws {
        try withStore { url in
            var store = try WorkflowLibraryStore(fileURL: url)
            let item = try store.save(workflow())
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            XCTAssertThrowsError(try store.rename(id: item.id, to: "Changed"))
            XCTAssertEqual(store.workflows.first?.name, item.name)
            XCTAssertThrowsError(try store.delete(id: item.id))
            XCTAssertEqual(store.workflows.count, 1)
        }
    }
}
