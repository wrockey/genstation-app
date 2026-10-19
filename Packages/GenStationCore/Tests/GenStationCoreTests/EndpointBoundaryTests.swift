import XCTest

/// Enforces the Stage 1 rule that no app source names an API host. The compiler cannot
/// express this, so — exactly like `PackageBoundaryTests` and its UI-framework ban — a test
/// scans the sources instead.
///
/// Scope note: only *hosted* API hosts are checked. ComfyUI's host is user-supplied and has no
/// literal to ban, so its path fragments are guarded by review, not by this test.
///
/// There are no file exemptions: a whole-file exemption hides any genuine future endpoint added
/// to that file. Every exception is an inline `endpoint-boundary:` marker on the specific line —
/// visible, reviewable, and immune to line-number drift.
final class EndpointBoundaryTests: XCTestCase {

    /// Hosts that must only ever appear inside `GenStationCore/Providers`.
    private static let bannedHosts = [
        "https://api.aimlapi.com",
        "https://billing.aimlapi.com",
        "https://generativelanguage.googleapis.com",
        "https://api.x.ai",
        "https://api.imgbb.com",
    ]

    /// A line containing this marker is exempted — it is a reviewed, informational mention
    /// (a docs link or help text), not a request. New endpoints must not be exempted this way;
    /// they must be added to a `GenStationCore/Providers` client instead.
    private static let exemptionMarker = "endpoint-boundary:"

    /// Empty, and it must stay empty. `ModelRegistry.swift` held the last exemption — its 198
    /// per-model endpoint strings collapsed onto named `AIMLEndpoints` members in Stage 2 Task 3,
    /// so the file no longer names a host and the boundary now covers every app source.
    private static let exemptFiles: [String] = []

    func testAppSourcesDoNotNameAPIHosts() throws {
        let appSourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../../GenStation")
            .standardizedFileURL

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: appSourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            XCTFail("Could not create enumerator for \(appSourcesURL.path)")
            return
        }

        var scannedSwiftFileCount = 0
        var violations: [String] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            guard !Self.exemptFiles.contains(fileURL.lastPathComponent) else { continue }
            scannedSwiftFileCount += 1

            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for (offset, line) in contents.split(
                separator: "\n", omittingEmptySubsequences: false).enumerated() {
                guard !line.contains(Self.exemptionMarker) else { continue }
                for host in Self.bannedHosts where line.contains(host) {
                    violations.append("\(fileURL.lastPathComponent):\(offset + 1): \(host)")
                }
            }
        }

        // Guard against a path mistake silently making this test vacuously green forever.
        //
        // The bound is deliberately well below the current file count, and is not itself a count.
        // Stage 2 Task 11 deleted `Params View/` (57 files) once the descriptor tables replaced it,
        // and Stage 3 deleted `Catalog/ModelRegistry.swift` when the catalog moved into the package;
        // a tighter bound would have failed for a reason that has nothing to do with an endpoint
        // literal. The guard only needs to be large enough that a wrong *path*, which yields 0, fails.
        XCTAssertGreaterThan(
            scannedSwiftFileCount, 60,
            "Only \(scannedSwiftFileCount) .swift files were scanned under \(appSourcesURL.path) — "
            + "the path is likely wrong, which would make this test pass without checking anything."
        )

        XCTAssertTrue(
            violations.isEmpty,
            "App sources must not name an API host — the owning provider type in "
            + "GenStationCore/Providers does. Found:\n" + violations.joined(separator: "\n")
        )
    }
}
