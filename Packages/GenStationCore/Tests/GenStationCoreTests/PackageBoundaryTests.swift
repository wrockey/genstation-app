import XCTest

final class PackageBoundaryTests: XCTestCase {

    /// These frameworks are UI frameworks. `GenStationCore` is meant to be UI-free so it can be
    /// shared between the app's platform layers without pulling in a specific presentation
    /// framework. The compiler cannot enforce this on its own — SwiftUI/AppKit/UIKit are system
    /// frameworks in the SDK, importable from any Swift target — so this test enforces it instead.
    private static let bannedImports = ["import SwiftUI", "import AppKit", "import UIKit"]

    func testSourcesDoNotImportUIFrameworks() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourcesURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/GenStationCore")
            .standardizedFileURL

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            XCTFail("Could not create enumerator for \(sourcesURL.path)")
            return
        }

        var scannedSwiftFileCount = 0
        var violations: [String] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            scannedSwiftFileCount += 1

            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                for bannedImport in Self.bannedImports {
                    if trimmed.hasPrefix(bannedImport) {
                        violations.append("\(fileURL.lastPathComponent): \(bannedImport)")
                    }
                }
            }
        }

        // Guard against a path mistake silently making this test vacuously green forever.
        XCTAssertGreaterThan(
            scannedSwiftFileCount, 0,
            "No .swift files were scanned under \(sourcesURL.path) — the path is likely wrong, " +
            "which would make this test pass without checking anything."
        )

        XCTAssertTrue(
            violations.isEmpty,
            "GenStationCore must not import UI frameworks, but found:\n" +
            violations.joined(separator: "\n")
        )
    }
}
