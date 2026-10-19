import XCTest
@testable import GenStationCore

/// `ModelRegistry.initializeDefaultParams` seeds a fresh `ModelParameters` from the selected model's
/// own descriptor defaults, and it did it as one hand-written `if params.x == nil { … }` line per
/// field — 40 lines for 41 properties. `audioURL` was the one with no line, so the `audio_url` row's
/// default could never apply to any model. These tests pin the rule against `ParamField.allCases`
/// instead, where that omission is unrepresentable.
final class ParamDefaultsTests: XCTestCase {

    func testMergeFillsEveryNilFieldIncludingAudioURL() {
        var defaults = ModelParameters()
        for field in ParamField.allCases {
            switch field.kind {
            case .string: defaults[field] = .string("seeded")
            case .int:    defaults[field] = .int(7)
            case .double: defaults[field] = .double(0.25)
            case .bool:   defaults[field] = .bool(true)
            }
        }

        var params = ModelParameters()
        for field in ParamField.allCases { params[field] = nil }
        ParamDefaults.merge(defaults, into: &params)

        let unfilled = ParamField.allCases.filter { params[$0] == nil }
        XCTAssertEqual(unfilled, [], "merge() left these fields nil: \(unfilled.map(\.rawValue))")
        XCTAssertEqual(params.audioURL, "seeded",
                       "audioURL is the field the 40 hand-written lines omitted")
    }

    /// The rule is "fill what is nil", not "overwrite with defaults". `ModelParameters` has 17
    /// non-nil struct defaults and for those the model's own default never applies — frozen
    /// behaviour (drift ledger § A.3), preserved here deliberately.
    func testMergeNeverOverwritesAValueThatIsAlreadySet() {
        var defaults = ModelParameters()
        defaults.duration = 8
        defaults.audioURL = "https://defaults.example/a.mp3"

        var params = ModelParameters()   // struct default duration = 5, audioURL = nil
        ParamDefaults.merge(defaults, into: &params)

        XCTAssertEqual(params.duration, 5, "a non-nil struct default must still win")
        XCTAssertEqual(params.audioURL, "https://defaults.example/a.mp3")
    }

    /// Closing the `audioURL` hole moved nothing, and this is the check that says so: the only
    /// `.audioURL` row in the tables (`omniHuman`, `Tables/VideoByteDance.swift:22-34`) has
    /// `defaultValue: nil` and `parseFallback: .setNil`, so `merge` writes nil over nil for it.
    ///
    /// **If this goes red the omission has become load-bearing** — some table now has an `audio_url`
    /// default that will start reaching the wire, and that needs a group-A drift-ledger row before
    /// it lands. Do not silence it by exempting the table.
    func testNoDescriptorTableGivesAudioURLADefault() {
        var offenders: [String] = []
        for id in ParamCatalog.migratedIds.sorted() {
            guard let table = ParamCatalog.descriptors(forModelId: id) else { continue }
            if let value = ParamDecoder.defaults(table).audioURL {
                offenders.append("\(id): audio_url default \(value)")
            }
        }
        XCTAssertEqual(offenders, [],
                       "audio_url now carries defaults — read this test's doc comment:\n"
                       + offenders.joined(separator: "\n"))
    }
}
