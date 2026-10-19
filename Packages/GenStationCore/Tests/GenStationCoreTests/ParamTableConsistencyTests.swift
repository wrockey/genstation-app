// Two properties of the descriptor tables that no other test looks at, both about the **display**
// half of Stage 2.
//
// The golden harness (`PayloadEquivalenceTests`) proves the tables emit what the 68 legacy
// `JSONBuilder`s emitted, across all 209 ids. That is the whole of its reach: it feeds probe values in
// and compares dictionaries coming out, so it never evaluates a `label`, an option list, or a
// `defaultValue` that is not on the wire. Every defect in this file's two classes was invisible to it,
// and both classes were found by reading rather than by testing — which is the argument for the file.

import XCTest
@testable import GenStationCore

final class ParamTableConsistencyTests: XCTestCase {

    /// Every `.picker` row's `defaultValue` is one of the options that picker offers.
    ///
    /// A SwiftUI `Picker` whose selection matches no `tag` renders **empty** — no row highlighted, the
    /// menu button blank. So this is not a question of showing a debatable number: a default outside
    /// the option list is a control the user cannot read, on a parameter they cannot see the value of.
    ///
    /// 20 rows across 13 tables failed this when it was written, all from one cause. Spec § 5 freezes
    /// `defaultValue` as *struct default where non-nil, else parser default*, and `ModelParameters`
    /// has one `duration`, one `resolution`, one `frameRate` shared by every model. So Sora's picker
    /// (4/8/12s) inherited the struct's `5`, LTXV-2's (6/8/10s) inherited `5`, and every model whose
    /// picker spells resolution `720P` or `1K` or `2k` inherited the struct's `"720p"`. The third
    /// default — the legacy view's own binding fallback, which was in-list by construction because a
    /// human wrote the two together — is the one the rule discarded (drift ledger § B.11).
    ///
    /// The fallbacks are back, read from the deleted views, and they are per-row data with no derivable
    /// rule: `?? 8` of `[4,8,12]` is the middle option for Sora, `?? 8` of `[4,6,8]` is the last for
    /// Veo, and `?? 6` of `[6,8,10]` is the first for LTXV-2. `defaultValue` reaches the wire only on an
    /// `alwaysEmit` row, and all 20 are `alwaysEmit: false`, so none of it moved a payload — the golden
    /// harness stayed green through the change, which is the check that says so.
    func testEveryPickerDefaultIsOneOfItsOwnOptions() {
        var offenders: [String] = []
        for id in ParamCatalog.migratedIds.sorted() {
            for descriptor in ParamCatalog.descriptors(forModelId: id) ?? [] {
                guard case .picker(let options, _) = descriptor.control,
                      let value = descriptor.defaultValue,
                      !options.contains(value)
                else { continue }
                offenders.append("\(id) · \(descriptor.wireKey): default \(value) not in \(options)")
            }
        }
        XCTAssertEqual(offenders, [], "Pickers that will render blank:\n" + offenders.joined(separator: "\n"))
    }

    /// Every `.slider` row that reaches the wire carries a `defaultValue`, and it sits inside the
    /// slider's own range.
    ///
    /// A nil default is not neutral here. `ParamDescriptorView.doubleBinding` has to show the user
    /// *something* when the field is nil, and with no `defaultValue` it falls back to
    /// `range.lowerBound` — so the control opens pinned to the far left of its track, which reads as a
    /// deliberate minimum rather than an absence. The four Flux Kontext `guidance_scale` sliders opened
    /// at 1.0 where their views had all shown 7.5, and 1.0 is a value nobody would choose: it is the
    /// bottom of a 1...20 range on a parameter whose useful band starts around 3.
    ///
    /// The exemption is a row with an empty `wireKey`, which is not rendered by `sliderCard` at all —
    /// Kling's `movement_value` belongs to `Control.custom(.klingCameraControl)`, which draws its own
    /// slider and supplies its own fallback.
    func testEverySliderThatShipsCarriesAnInRangeDefault() {
        var offenders: [String] = []
        for id in ParamCatalog.migratedIds.sorted() {
            for descriptor in ParamCatalog.descriptors(forModelId: id) ?? [] {
                guard case .slider(let range, _) = descriptor.control, !descriptor.wireKey.isEmpty
                else { continue }
                switch descriptor.defaultValue {
                case .none:
                    offenders.append("\(id) · \(descriptor.wireKey): no default, so the slider opens at \(range.lowerBound)")
                case .double(let value) where !range.contains(value):
                    offenders.append("\(id) · \(descriptor.wireKey): default \(value) is outside \(range)")
                case .int(let value) where !range.contains(Double(value)):
                    offenders.append("\(id) · \(descriptor.wireKey): default \(value) is outside \(range)")
                default:
                    break
                }
            }
        }
        XCTAssertEqual(offenders, [], "Sliders with no usable default:\n" + offenders.joined(separator: "\n"))
    }

    /// Every `emitClamp` rule's allowed set is exactly the option list the user is choosing from, or is
    /// listed below with the reason it differs.
    ///
    /// An `emitClamp` rewrites a value on its way to the wire (`ParamDescriptor.emitClamp`). Nothing
    /// else checks that the set it permits is the set the control offers, so a mistranscribed allowed
    /// list is silent in both directions and both are bad: too narrow and the user's explicit choice is
    /// swapped for the fallback with no indication, too wide and the clamp stops catching the stale
    /// value it exists to catch.
    ///
    /// A rule's `fallback` is checked too — substituting a value the picker does not offer would leave
    /// the control disagreeing with the payload no matter what the user does.
    func testEmitClampAllowedSetsMatchTheOfferedOptions() {
        var offenders: [String] = []
        for id in ParamCatalog.migratedIds.sorted() {
            for descriptor in ParamCatalog.descriptors(forModelId: id) ?? [] {
                guard let clamp = descriptor.emitClamp else { continue }
                guard case .picker(let options, _) = descriptor.control else {
                    // A clamp on a row with no picker cannot be compared to anything; it is checked by
                    // the documented-divergence list below instead.
                    for rule in clamp.rules where !Self.documented.contains(Divergence(wireKey: descriptor.wireKey, allowed: rule.allowed.map(Self.describe))) {
                        offenders.append("\(id) · \(descriptor.wireKey): clamp on a non-picker row, allowed \(rule.allowed)")
                    }
                    continue
                }
                for rule in clamp.rules {
                    let divergence = Divergence(wireKey: descriptor.wireKey, allowed: rule.allowed.map(Self.describe))
                    if Set(rule.allowed.map(Self.describe)) != Set(options.map(Self.describe)),
                       !Self.documented.contains(divergence) {
                        offenders.append("\(id) · \(descriptor.wireKey): clamp allows \(rule.allowed) but the picker offers \(options)")
                    }
                    if !options.contains(rule.fallback), !Self.documented.contains(divergence) {
                        offenders.append("\(id) · \(descriptor.wireKey): clamp falls back to \(rule.fallback), which the picker does not offer")
                    }
                }
            }
        }
        XCTAssertEqual(offenders, [], "Undocumented clamp/option divergences:\n" + offenders.joined(separator: "\n"))
    }

    /// Every rendered control carries a label, and every panel carries text.
    ///
    /// `ParamDescriptorView` writes `descriptor.label` straight into the card header — and for a
    /// slider, into `"\(label): \(value)"`. An empty label is therefore not a missing decoration, it
    /// is a control the user cannot identify: Topaz's two face-enhancement sliders rendered as
    /// adjacent `": 0.80"` and `": 0.00"` rows, two 0-to-1 tracks with nothing to say which was
    /// Strength and which was Creativity.
    ///
    /// `.info` is exempt from the label rule and only that rule — `infoCard` omits the header when the
    /// label is empty, which is what a bare "Notes" paragraph wants — but its text must be there, or
    /// the row draws an empty card.
    ///
    /// `.none` is exempt from everything: it is emitted and never rendered.
    func testEveryRenderedControlIsLabelled() {
        var offenders: [String] = []
        for id in ParamCatalog.migratedIds.sorted() {
            for descriptor in ParamCatalog.descriptors(forModelId: id) ?? [] {
                switch descriptor.control {
                case .none:
                    continue
                case .info(let text):
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        offenders.append("\(id) · info \"\(descriptor.label)\": empty text, so the card draws blank")
                    }
                case .picker, .text, .slider, .toggle, .seed, .imageSize, .custom:
                    if descriptor.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        offenders.append("\(id) · \(descriptor.wireKey.isEmpty ? "(no wire key)" : descriptor.wireKey): rendered with an empty label")
                    }
                }
                if let help = descriptor.help, help.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    offenders.append("\(id) · \(descriptor.wireKey): empty help string")
                }
            }
        }
        XCTAssertEqual(offenders, [], "Controls the user cannot identify:\n" + offenders.joined(separator: "\n"))
    }

    /// No picker offers an option the user cannot read, and none offers the same value twice.
    ///
    /// A `Text("")` menu row is a blank line with nothing to click; a repeated value gives two rows
    /// the same SwiftUI `tag`, so selecting either highlights the first. Both survive the golden
    /// harness untouched, because neither changes what the *selected* value encodes to.
    ///
    /// One empty option is real and stays: PixVerse's `style` picker offers `""` so the style can be
    /// switched back off, and `ParamOptionLabel` renders that value as "None" — the label its legacy
    /// view hand-wrote. It is the only one in any table, and the whitelist is keyed on the wire key so
    /// a second one anywhere else still fails.
    func testNoPickerOffersABlankOrDuplicatedOption() {
        let optionalOffSwitches: Set<String> = ["style"]
        var offenders: [String] = []
        for id in ParamCatalog.migratedIds.sorted() {
            for descriptor in ParamCatalog.descriptors(forModelId: id) ?? [] {
                guard case .picker(let options, _) = descriptor.control else { continue }
                if options.isEmpty {
                    offenders.append("\(id) · \(descriptor.wireKey): picker with no options at all")
                }
                if Set(options.map(Self.describe)).count != options.count {
                    offenders.append("\(id) · \(descriptor.wireKey): duplicated option in \(options)")
                }
                for option in options {
                    guard case .string(let raw) = option, raw.isEmpty,
                          !optionalOffSwitches.contains(descriptor.wireKey)
                    else { continue }
                    offenders.append("\(id) · \(descriptor.wireKey): offers an empty-string option")
                }
            }
        }
        XCTAssertEqual(offenders, [], "Pickers with unreadable rows:\n" + offenders.joined(separator: "\n"))
    }

    /// No slider's `defaultValue` sits outside its own track — including the rows
    /// `testEverySliderThatShipsCarriesAnInRangeDefault` exempts.
    ///
    /// That test requires a default and so has to skip the rows with no wire key, which are the ones
    /// `Control.custom` draws itself. This one asks the weaker question of *every* slider: if there is
    /// a default, the track can represent it. A default below `lowerBound` or above `upperBound` shows
    /// the thumb pinned at the end while the stored value is something else, so the control lies about
    /// what will be sent until the user touches it.
    func testNoSliderDefaultSitsOutsideItsTrack() {
        var offenders: [String] = []
        for id in ParamCatalog.migratedIds.sorted() {
            for descriptor in ParamCatalog.descriptors(forModelId: id) ?? [] {
                guard case .slider(let range, _) = descriptor.control else { continue }
                let value: Double? = {
                    switch descriptor.defaultValue {
                    case .double(let raw): return raw
                    case .int(let raw):    return Double(raw)
                    default:               return nil
                    }
                }()
                guard let value, !range.contains(value) else { continue }
                offenders.append("\(id) · \(descriptor.wireKey.isEmpty ? "(no wire key)" : descriptor.wireKey): default \(value) is outside \(range)")
            }
        }
        XCTAssertEqual(offenders, [], "Sliders whose track cannot show their default:\n" + offenders.joined(separator: "\n"))
    }

    // MARK: - The divergences that are real

    private struct Divergence: Hashable {
        let wireKey: String
        let allowed: [String]
    }

    private static func describe(_ value: ParamValue) -> String {
        switch value {
        case .string(let raw): return "s:\(raw)"
        case .int(let raw):    return "i:\(raw)"
        case .double(let raw): return "d:\(raw)"
        case .bool(let raw):   return "b:\(raw)"
        }
    }

    /// Clamp sets that deliberately differ from the offered options. Each is read out of a legacy
    /// builder, so narrowing the clamp to match the picker would change the wire — which is a drift
    /// ledger decision, not a table edit.
    ///
    /// - `duration` allowing `[4, 6, 8]` where the picker offers `[8]`: the Veo 3.0 and Veo 3.1 i2v
    ///   tables were generated from one shared view, `buildGoogleVeo31I2VFastParamsView`, whose option
    ///   list is computed at runtime (`isVeo31 ? [4,6,8] : [8]`) while its **builder** clamps to
    ///   `[4,6,8]` for both. Veo 3.0 therefore offers one duration and would accept three. Harmless in
    ///   the offered direction — 8 is allowed — and the extra breadth is unreachable from the UI.
    /// - `aspect_ratio` differing on the same pair of tables: the builder's clamp is resolution-
    ///   dependent (`1:1` is legal only at 720p) but `Control.picker` is static, so one table carries
    ///   the superset and the other the subset. Drift ledger § B.7 already records this and calls for a
    ///   `Condition`-driven option list; until that exists, the clamp is what protects the wire.
    /// - `resolution` allowing `[720p]` on Sora 2: a `.none` control — the row is emitted and never
    ///   rendered, so there are no options to agree with. Sora 2 has exactly one resolution.
    private static let documented: Set<Divergence> = [
        Divergence(wireKey: "duration", allowed: ["i:4", "i:6", "i:8"]),
        Divergence(wireKey: "aspect_ratio", allowed: ["s:16:9", "s:9:16"]),
        Divergence(wireKey: "aspect_ratio", allowed: ["s:16:9", "s:9:16", "s:1:1"]),
        Divergence(wireKey: "resolution", allowed: ["s:720p"])
    ]
}
