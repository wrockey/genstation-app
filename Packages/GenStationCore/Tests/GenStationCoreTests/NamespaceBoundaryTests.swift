import XCTest

/// Enforces the package namespace rule: `GenStationCore`'s top level is reserved for domain
/// vocabulary (`HistoryItem`, `Provider`, `GenerationStatus`, …) plus one namespace enum per
/// provider or subsystem. **Behaviour** — free functions, the result types they return, and the
/// wire DTOs they decode — nests inside the namespace that owns it.
///
/// Without this, every new provider helper lands as a bare `public func` and the package's API
/// surface becomes a flat list where nothing says which provider a symbol belongs to. Stage 1
/// accumulated ten such symbols before the rule was applied (`friendlyGenerationError`,
/// `formatOpenAICompatibleError`, …); Stage 2 adds ~121 descriptor tables, so the rule is
/// enforced here rather than left to review.
///
/// The compiler cannot express this, so — exactly like `PackageBoundaryTests` and its
/// UI-framework ban — a test scans the sources instead.
///
/// Scope note: only `public func` is checked. A top-level `internal` func is invisible outside
/// the package and so cannot pollute its API surface; top-level `public` *types* are how domain
/// vocabulary and the namespace enums themselves are declared, so they are the rule, not a
/// violation.
final class NamespaceBoundaryTests: XCTestCase {

    func testNoTopLevelPublicFunctions() throws {
        let sourcesURL = URL(fileURLWithPath: #filePath)
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
            for (offset, line) in contents.split(
                separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // A declaration at column 0 is top-level; anything nested in a type or an
                // extension is indented, which is what separates the two cases textually.
                if line.hasPrefix("public func ") || line.hasPrefix("public static func ") {
                    violations.append("\(fileURL.lastPathComponent):\(offset + 1): \(line)")
                }
            }
        }

        // Guard against a path mistake silently making this test vacuously green forever.
        // This bound is deliberately NOT the current file count — it was written as "15 source files
        // today", was 45 by Stage 3, and changed again inside Stage 3. A number that has to be updated
        // is a number that goes stale. All this needs to do is fail when the path resolves to the
        // wrong directory (or to nothing); any small positive floor does that.
        XCTAssertGreaterThan(
            scannedSwiftFileCount, 10,
            "Only \(scannedSwiftFileCount) .swift files were scanned under \(sourcesURL.path) — "
            + "the path is likely wrong, which would make this test pass without checking anything."
        )

        XCTAssertTrue(
            violations.isEmpty,
            "GenStationCore's top level is for domain vocabulary and namespace enums; behaviour "
            + "must nest inside the namespace that owns it (e.g. AIMLEndpoints.friendlyError, "
            + "OpenAICompatible.formatError). Found top-level public functions:\n"
            + violations.joined(separator: "\n")
        )
    }
}
