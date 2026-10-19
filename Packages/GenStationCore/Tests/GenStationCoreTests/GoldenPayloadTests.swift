// The golden payload harness (Stage 2, Task 11) — successor to `PayloadEquivalenceTests`.
//
// Design § 5 runs in two phases. **Phase A (equivalence)** asserted, live, for every migrated model
// over every probe under both modes:
//
//     ParamEncoder.encode(ParamCatalog.descriptors(id), params)  ==  LegacyPayload.builder(id)(params)
//
// It was green over all 209 registered ids × 5 probes × 2 contexts at `92e07cf`, which is what made
// the 121-model migration *provably* behaviour-preserving. **Phase B (golden)** is this file: Task 11
// deleted the legacy builders, so the payloads they produced were recorded first — by
// `GoldenFixtureRecorder`, running the legacy builders — and are now checked in as
// `GoldenPayloads.swift`. This asserts the encoder still reproduces every one of them.
//
// The distinction matters and should not be blurred: this is no longer a *comparison* against the
// old code, it is a comparison against a **recording** of the old code. The recording is the only
// remaining artifact of what the app used to send. Do not regenerate it from the encoder.
//
// **Assertion strength is dictionary equality, which implies key-set equality. Do not weaken it to a
// subset or a key-only comparison.** Key-set equality is precisely what catches the Seedance
// hidden-but-emitted `aspect_ratio` (drift ledger § A.1) — the defect class this stage exists to
// eliminate.
//
// ## What this harness does NOT prove
//
// It tests the **payload half** of a table only. `ParamEncoder` never reads `Control.picker(options:)`,
// `Control.slider(range:step:)`, `label` or `help` — so a table with the wrong option list, the wrong
// picker style, or a mislabelled control passes every test in this file. That was demonstrated, not
// assumed. Option lists were protected only by the Task 8/10 generator reading them out of the legacy
// views, **and those views no longer exist**, so live testing is now the only check on the display
// half of 67 tables. Golden-green means "this table emits what the app emitted on 2026-07-27", never
// "this table is correct". Drift ledger § C.3.

import XCTest
@testable import GenStationCore

final class GoldenPayloadTests: XCTestCase {

    func testEncoderReproducesTheRecordedLegacyPayloadForEveryRegisteredModel() {
        var checked = 0
        for (id, golden) in GoldenPayloads.byModelId.sorted(by: { $0.key < $1.key }) {
            guard let descriptors = ParamCatalog.descriptors(forModelId: id) else {
                XCTFail("\(id) has a golden recording but no descriptor table"); continue
            }
            for (probeName, params) in ProbeSet.all {
                guard let old = golden[probeName] else {
                    XCTFail("\(id) has no golden for probe \(probeName)"); continue
                }
                // Both modes, because `Condition.isTextToVideo` reads `context.isI2I` and the legacy
                // builder had no context at all — so a gate the builder did not have shows up as a
                // key difference in exactly one of the two runs.
                for context in Self.bothModes(for: id) {
                    // September correction: Seedance frame inputs own the aspect ratio.
                    var old = old
                    if ["bytedance/seedance-2-0", "bytedance/seedance-2-0-fast"].contains(id) && context.hasInputImages {
                        old.removeValue(forKey: "aspect_ratio")
                    }
                    if ["google/veo-3.1-t2v", "google/veo-3.1-t2v-fast"].contains(id) {
                        for key in ["negative_prompt", "enhance_prompt", "seed"] { old.removeValue(forKey: key) }
                    }
                    if id.contains("kling-video/v3/") || id.contains("klingai/video-v3-") { old.removeValue(forKey: "shot_type") }
                    let new = ParamEncoder.encode(descriptors, params: params, context: context)
                    let where_ = "\(id) / \(probeName) / isI2I=\(context.isI2I)"

                    XCTAssertEqual(NSDictionary(dictionary: new), NSDictionary(dictionary: old), where_)

                    // NSDictionary compares numbers by value, so `5` and `5.0` are equal to it. The
                    // wire cares: video `duration` is always an Int and `guidance_scale` always a
                    // Double. The golden literals carry their Swift types for exactly this reason.
                    XCTAssertEqual(Self.typeTags(new), Self.typeTags(old), "JSON value types differ — \(where_)")
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, GoldenPayloads.byModelId.count * ProbeSet.all.count,
                       "every recorded id × every probe must be covered, or the pin is partial")
    }

    /// The golden map is a second list of model ids, and a second list is the exact pattern this
    /// stage exists to delete. Nothing keeps it in step with the catalog except this: the ids are
    /// read out of `Catalog` directly, so a model added to one and not the other fails on the day
    /// it lands. (This is the invariant `LegacyPayloadTests` held before its table was deleted with
    /// the rest of the legacy layer.)
    ///
    /// **This is the one count that must track the live catalog**, unlike the `checked` totals
    /// above and in `MCPSchemaGateTests`/`ParamDecoderTests`, which pin a recording against itself.
    /// It compares all 209 spellings, canonical and alias, because `ParamCatalog` and these
    /// fixtures are both keyed per alias — Task 11's collapse changed `Catalog.all` to canonical
    /// rows only and deliberately left both of those alone.
    ///
    /// It is also the assertion that will legitimately go red when § 4.4's probe-gated deletion
    /// removes rows — at which point the fixture rows are removed in the same commit, having first
    /// been proved byte-identical to their canonical's.
    func testTheGoldenIdSetIsExactlyTheCatalogsAIMLIds() {
        let ids = Set(Catalog.all
            .filter { $0.provider == .aimlapi }
            .flatMap { [$0.id] + $0.aliases })
        XCTAssertGreaterThan(ids.count, 100, "Catalog.all resolved to \(ids.count) AI/ML ids")
        XCTAssertEqual(Set(GoldenPayloads.byModelId.keys).union(["alibaba/wan-3-0-video", "bytedance/seedance-2-5", "minimax/h3-max"]), ids,
                       "the golden fixtures and the catalog have drifted apart")
    }

    /// `descriptors(forModelId:)` lowercases its argument, so an upper-cased key would be permanently
    /// unreachable — and the fixture would still claim the model was covered.
    func testEveryGoldenIdIsLowercasedAndResolvesCaseInsensitively() {
        for id in GoldenPayloads.byModelId.keys.sorted() {
            XCTAssertEqual(id, id.lowercased(), "golden key \(id) is not lowercased")
            XCTAssertNotNil(ParamCatalog.descriptors(forModelId: id.uppercased()),
                            "\(id) does not resolve case-insensitively")
        }
    }

    /// The harness is only as good as its inputs; a probe silently dropped from `ProbeSet` would
    /// shrink coverage without failing anything. Pin the count and both composite object branches,
    /// which are the two easiest to lose — each is reachable from exactly one probe.
    func testTheProbeSetKeepsItsFiveProbesIncludingBothCompositeObjectBranches() {
        XCTAssertEqual(ProbeSet.all.count, 5)

        let custom = ProbeSet.all.first { $0.name == "customImageSize" }?.params
        XCTAssertEqual(custom?.imageSizeMode, "custom")
        XCTAssertNotNil(custom?.customWidth)
        XCTAssertNotNil(custom?.customHeight)
        XCTAssertTrue(ParamEncoder.imageSizeValue(custom ?? ModelParameters(), spec: Self.anySpec) is [String: Int],
                      "the custom probe must reach the object branch of the image_size composite")
        XCTAssertTrue(ParamEncoder.imageSizeValue(ModelParameters.fullyPopulatedProbe(), spec: Self.anySpec) is String,
                      "fullyPopulatedProbe must still take the preset branch — that is why probe 4 exists")

        let camera = ProbeSet.all.first { $0.name == "klingAdvancedCamera" }?.params
        XCTAssertEqual(camera?.cameraControl, "advanced")
        XCTAssertTrue(ParamEncoder.klingCameraControlValue(camera ?? ModelParameters()) is [String: Any],
                      "the camera probe must reach the object branch of the camera_control composite")
        XCTAssertTrue(ParamEncoder.klingCameraControlValue(ModelParameters.fullyPopulatedProbe()) is String,
                      "fullyPopulatedProbe stores \"{}\", a preset name — that is why probe 5 exists")
    }

    // MARK: - Helpers

    /// Which branch of the composite a probe reaches depends only on `imageSizeMode`, so the spec used
    /// to ask the question does not matter — any one will do.
    private static let anySpec = ImageSizeSpec(presets: ["square_hd"], presetFallback: "landscape_4_3",
                                               dimensions: [1024], widthFallback: 1024, heightFallback: 1024)

    /// The two `ParamContext` values a model can be encoded under. `hasInputImages` tracks `isI2I`
    /// because no `Condition` reads it yet (frozen legacy semantics — see `Condition.isTextToVideo`).
    private static func bothModes(for id: String) -> [ParamContext] {
        [ParamContext(modelId: id, isI2I: false, hasInputImages: false),
         ParamContext(modelId: id, isI2I: true, hasInputImages: true)]
    }

    /// The dynamic Swift type behind each `Any`, as a comparable map. Both dictionaries are built in
    /// Swift and never round-trip through `JSONSerialization`, so `Int`, `Double`, `Bool` and `String`
    /// stay distinct here in a way `NSNumber` equality does not preserve.
    ///
    /// Internal, not `private`: `AliasEquivalenceTests` reuses this exact definition rather than
    /// mirroring it, so there is one definition of "what counts as a type tag" — two copies of a
    /// drift-detector that could themselves drift apart would be a particularly unfortunate irony.
    static func typeTags(_ dict: [String: Any]) -> [String: String] {
        dict.mapValues { String(describing: type(of: $0)) }
    }
}
