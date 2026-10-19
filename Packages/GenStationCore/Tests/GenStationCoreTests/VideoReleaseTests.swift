import XCTest
@testable import GenStationCore

final class VideoReleaseTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/" + name + ".json"))
    }
    func testEverySupportedAIMLVideoChoiceMatchesOneCompleteCurrentSchemaBranch() throws {
        let fixtures = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("2026-09-video-intake-schemas")) as? [String: [String: Any]])
        XCTAssertEqual(Set(fixtures.keys), ReleaseModelPolicy.videoIDs)
        for id in ReleaseModelPolicy.videoIDs.sorted() {
            let model = try XCTUnwrap(Catalog.model(for: id))
            let doc = try XCTUnwrap(fixtures[id])
            let paths = try XCTUnwrap(doc["paths"] as? [String: [String: Any]])
            let post = try XCTUnwrap(paths.values.first?["post"] as? [String: Any])
            let request = try XCTUnwrap(post["requestBody"] as? [String: Any])
            let content = try XCTUnwrap(request["content"] as? [String: [String: Any]])
            let schema = try XCTUnwrap(content["application/json"]?["schema"] as? [String: Any])
            let branches = schema["anyOf"] as? [[String: Any]] ?? [schema]
            let rows = ParamCatalog.descriptors(for: model)
            let defaults = ParamDecoder.defaults(rows)
            var probes: [(String, ModelParameters)] = [("defaults", defaults)]
            for row in rows {
                guard let field = row.field else { continue }
                var values: [ParamValue] = []
                switch row.control {
                case .picker(let options, _): values = options
                case .toggle: values = [.bool(false), .bool(true)]
                case .seed: values = [.int(42)]
                default: continue
                }
                for value in values { var p = defaults; p[field] = value; probes.append((row.wireKey + "=\(value)", p)) }
            }
            for count in 0...model.maxInputImages {
                if model.requiresInputImage && count == 0 { continue }
                for (label, params) in probes {
                    if VideoRequestPolicy.parameterIssue(model: model, params: params, imageCount: count) != nil { continue }
                    var body = ParamEncoder.encode(rows, params: params, context: ParamCatalog.context(for: model, hasInputImages: count > 0))
                    body["model"] = id; body["prompt"] = "A teapot turns slowly on a table."
                    if count > 0 { body[model.imageInputParam] = "https://example.com/start.png" }
                    if count > 1, let second = model.secondImageParam { body[second] = "https://example.com/end.png" }
                    XCTAssertNil(VideoRequestPolicy.payloadIssue(model: model, body: body), "\(id) \(label) images=\(count)")
                    let matches = branches.contains { branch in
                        let props = branch["properties"] as? [String: [String: Any]] ?? [:]
                        let required = branch["required"] as? [String] ?? []
                        guard required.allSatisfy({ body[$0] != nil }) else { return false }
                        return body.allSatisfy { key, value in
                            guard let spec = props[key] else { return false }
                            if let choices = spec["enum"] as? [Any], !choices.contains(where: { NSDictionary(dictionary: ["v": $0]).isEqual(to: ["v": value]) }) { return false }
                            if let n = value as? NSNumber {
                                if let min = spec["minimum"] as? Double, n.doubleValue < min { return false }
                                if let max = spec["maximum"] as? Double, n.doubleValue > max { return false }
                            }
                            return true
                        }
                    }
                    XCTAssertTrue(matches, "\(id) \(label) images=\(count): \(body)")
                }
            }
        }
    }
    func testFrameAndOperationConstraints() throws {
        let seedance = try XCTUnwrap(Catalog.model(for: "bytedance/seedance-2-5"))
        var body: [String: Any] = ["model": seedance.id, "prompt": "Move", "image_url": "https://example.com/start.png", "aspect_ratio": "16:9"]
        XCTAssertNotNil(VideoRequestPolicy.payloadIssue(model: seedance, body: body))
        body.removeValue(forKey: "aspect_ratio")
        XCTAssertNil(VideoRequestPolicy.payloadIssue(model: seedance, body: body))
        body["video_url"] = "https://example.com/input.mp4"
        XCTAssertNotNil(VideoRequestPolicy.payloadIssue(model: seedance, body: body))
        let kling = try XCTUnwrap(Catalog.model(for: "kling-video/v3/standard/image-to-video"))
        XCTAssertNotNil(VideoRequestPolicy.parameterIssue(model: kling, params: ParamDecoder.defaults(ParamCatalog.descriptors(for: kling)), imageCount: 2))
        let h3 = try XCTUnwrap(Catalog.model(for: "minimax/h3-max"))
        var params = ParamDecoder.defaults(ParamCatalog.descriptors(for: h3))
        XCTAssertEqual(params.resolution, "480p")
        params.resolution = "720p"
        XCTAssertNotNil(VideoRequestPolicy.parameterIssue(model: h3, params: params, imageCount: 0))
    }
    func testGuideAndIntakeMetadataCoverage() throws {
        for id in ReleaseModelPolicy.videoIDs.union([GrokVideoClient.model]) {
            let guide = try XCTUnwrap(VideoWorkflowGuide.guide(for: id), id)
            XCTAssertFalse(guide.tips.isEmpty)
        }
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("2026-09-video-intake-models")) as? [[String: Any]])
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            let model = try XCTUnwrap(Catalog.model(for: row["id"] as? String ?? ""))
            XCTAssertEqual(model.displayName, (row["info"] as? [String: Any])?["name"] as? String)
            XCTAssertEqual(model.task, .video)
            XCTAssertEqual(model.secondImageParam, "last_image_url")
        }
    }
}
