import XCTest
@testable import GenStationCore

final class ComfyUIEndpointsTests: XCTestCase {

    private let host = "http://localhost:8188"

    func testNormalizationAddsAMissingScheme() {
        XCTAssertEqual(ComfyUIEndpoints.normalizedServerURL("localhost:8188"),
                       "http://localhost:8188")
        XCTAssertEqual(ComfyUIEndpoints.normalizedServerURL("192.0.2.10:8188"),
                       "http://192.0.2.10:8188")
    }

    func testNormalizationLeavesAnExplicitSchemeAlone() {
        XCTAssertEqual(ComfyUIEndpoints.normalizedServerURL("http://localhost:8188"),
                       "http://localhost:8188")
        XCTAssertEqual(ComfyUIEndpoints.normalizedServerURL("https://comfy.example.com"),
                       "https://comfy.example.com")
    }

    func testNormalizationTrimsWhitespaceAndTrailingSlashes() {
        XCTAssertEqual(ComfyUIEndpoints.normalizedServerURL("  localhost:8188/  "),
                       "http://localhost:8188")
    }

    func testPathBuildersMatchTheLiteralsTheyReplace() {
        XCTAssertEqual(ComfyUIEndpoints.objectInfoURL(serverURL: host)?.absoluteString,
                       "http://localhost:8188/object_info")
        XCTAssertEqual(
            ComfyUIEndpoints.objectInfoURL(serverURL: host, classType: "KSampler")?.absoluteString,
            "http://localhost:8188/object_info/KSampler")
        XCTAssertEqual(ComfyUIEndpoints.promptURL(serverURL: host)?.absoluteString,
                       "http://localhost:8188/prompt")
        XCTAssertEqual(ComfyUIEndpoints.uploadImageURL(serverURL: host)?.absoluteString,
                       "http://localhost:8188/upload/image")
        XCTAssertEqual(
            ComfyUIEndpoints.historyURL(serverURL: host, promptID: "abc-123")?.absoluteString,
            "http://localhost:8188/history/abc-123")
        XCTAssertEqual(ComfyUIEndpoints.interruptURL(serverURL: host)?.absoluteString,
                       "http://localhost:8188/interrupt")
    }

    /// Filenames routinely contain spaces and the subfolder can be empty; the query must be
    /// encoded or the download 404s.
    func testViewURLEncodesItsQueryItems() {
        let url = ComfyUIEndpoints.viewURL(
            serverURL: host, filename: "my render 001.png", subfolder: "", type: "output")
        let string = try! XCTUnwrap(url?.absoluteString)
        XCTAssertTrue(string.hasPrefix("http://localhost:8188/view?"), string)
        XCTAssertTrue(string.contains("filename=my%20render%20001.png"), string)
        XCTAssertTrue(string.contains("type=output"), string)
        XCTAssertTrue(string.contains("subfolder="), string)
    }

    /// http -> ws, https -> wss. Getting this wrong silently disables progress reporting.
    func testWebSocketURLSwapsTheScheme() {
        XCTAssertEqual(
            ComfyUIEndpoints.webSocketURL(serverURL: host, clientID: "cid")?.absoluteString,
            "ws://localhost:8188/ws?clientId=cid")
        XCTAssertEqual(
            ComfyUIEndpoints.webSocketURL(serverURL: "https://comfy.example.com",
                                          clientID: "cid")?.absoluteString,
            "wss://comfy.example.com/ws?clientId=cid")
    }

    /// `/ws` must be APPENDED to whatever path the host already has, not replace it —
    /// a ComfyUI behind a reverse-proxy subpath is a real deployment, and the live code
    /// this replaces appended. Overwriting the path would break those users silently.
    func testWebSocketURLPreservesAReverseProxySubpath() {
        XCTAssertEqual(
            ComfyUIEndpoints.webSocketURL(serverURL: "http://host/comfy",
                                          clientID: "cid")?.absoluteString,
            "ws://host/comfy/ws?clientId=cid")
    }

    /// The live code guards with `if !path.hasSuffix("/ws")`, so asking twice is a no-op.
    func testWebSocketURLIsIdempotentWhenThePathAlreadyEndsInWS() {
        XCTAssertEqual(
            ComfyUIEndpoints.webSocketURL(serverURL: "http://host/ws",
                                          clientID: "cid")?.absoluteString,
            "ws://host/ws?clientId=cid")
    }

    /// The host comes from a text field the user types into, so every builder is optional.
    func testAnUnparseableHostYieldsNil() {
        XCTAssertNil(ComfyUIEndpoints.promptURL(serverURL: ""))
        XCTAssertNil(ComfyUIEndpoints.webSocketURL(serverURL: "", clientID: "cid"))
        XCTAssertNil(ComfyUIEndpoints.viewURL(
            serverURL: "http://", filename: "a.png", subfolder: "", type: "output"))
    }
}
