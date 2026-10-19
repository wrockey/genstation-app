import XCTest
@testable import GenStationCore

final class ComfyUIServerProfileTests: XCTestCase {
    private func withFile(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("servers.json"))
    }

    func testAddressNormalizationPreservesProxyPathAndRejectsEmbeddedSecrets() throws {
        let profile = try ComfyUIServerProfile(name: " Studio ", baseURL: " localhost:8188/comfy/ ")
        XCTAssertEqual(profile.name, "Studio")
        XCTAssertEqual(profile.baseURL, "http://localhost:8188/comfy")
        XCTAssertEqual(ComfyUIEndpoints.objectInfoURL(serverURL: profile.baseURL)?.path, "/comfy/object_info")
        for address in ["", "http://", "ftp://host", "https://user:secret@host", "https://host?token=secret", "https://host/#secret", "https://host/\npath"] {
            XCTAssertThrowsError(try ComfyUIServerProfile(name: "Studio", baseURL: address), address)
        }
    }

    func testMigrationHappensOnceAndRetainsIdentityOnRelaunch() throws {
        try withFile { url in
            let migrated = try ComfyUIServerProfileStore(fileURL: url, legacyServerURL: "localhost:8188")
            let first = try XCTUnwrap(migrated.selected)
            let reloaded = try ComfyUIServerProfileStore(fileURL: url, legacyServerURL: "different:8188")
            XCTAssertEqual(reloaded.selected, first)
            XCTAssertEqual(reloaded.profiles.count, 1)
        }
    }

    func testUpdateAndSelectionKeepInventorySeparated() throws {
        try withFile { url in
            var store = try ComfyUIServerProfileStore(fileURL: url)
            let first = try store.save(ComfyUIServerProfile(name: "Studio", baseURL: "localhost:8188"))
            let second = try store.save(ComfyUIServerProfile(name: "Studio", baseURL: first.baseURL))
            XCTAssertNotEqual(first.inventoryKey, second.inventoryKey)
            XCTAssertEqual(store.selectedID, first.id)
            try store.select(id: second.id)
            let changed = try store.save(ComfyUIServerProfile(name: "Remote", baseURL: "https://studio.example/comfy"), replacingID: second.id)
            XCTAssertEqual(changed.id, second.id)
            XCTAssertEqual(changed.revision, 2)
            XCTAssertNotEqual(changed.inventoryKey, second.inventoryKey)
            XCTAssertEqual(try ComfyUIServerProfileStore(fileURL: url).selected, changed)
            try store.delete(id: changed.id)
            XCTAssertNil(store.selected)
            XCTAssertEqual(store.profiles, [first])
            XCTAssertThrowsError(try store.select(id: changed.id))
        }
    }

    func testCorruptAndFutureVersionsAreNeverReplacedByMigration() throws {
        for contents in ["broken", "{\"schemaVersion\":99,\"profiles\":[]}", "{\"schemaVersion\":1,\"profiles\":[],\"selectedID\":\"\(UUID().uuidString)\"}"] {
            try withFile { url in
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = Data(contents.utf8)
                try data.write(to: url)
                XCTAssertThrowsError(try ComfyUIServerProfileStore(fileURL: url, legacyServerURL: "localhost:8188"))
                XCTAssertEqual(try Data(contentsOf: url), data)
            }
        }
    }

    func testPersistedProfilesCannotBypassAddressValidationOrDuplicateIdentity() throws {
        try withFile { url in
            let profile = try ComfyUIServerProfile(name: "Studio", baseURL: "localhost:8188")
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            for records in [[object, object], [object.merging(["baseURL": "https://user:password@host"]) { _, new in new }]] {
                let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "profiles": records])
                try data.write(to: url)
                XCTAssertThrowsError(try ComfyUIServerProfileStore(fileURL: url))
                XCTAssertEqual(try Data(contentsOf: url), data)
            }
        }
    }

    func testWriteFailureKeepsCurrentSelectionAndProfiles() throws {
        try withFile { url in
            var store = try ComfyUIServerProfileStore(fileURL: url, legacyServerURL: "localhost:8188")
            let original = try XCTUnwrap(store.selected)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            XCTAssertThrowsError(try store.delete(id: original.id))
            XCTAssertEqual(store.selected, original)
            XCTAssertThrowsError(try store.save(ComfyUIServerProfile(name: "Other", baseURL: "https://other.example")))
            XCTAssertEqual(store.profiles, [original])
        }
    }
}
