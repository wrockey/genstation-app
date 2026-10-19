import XCTest
@testable import GenStationCore

/// What a picker *displays*, which no other test in this package can see.
///
/// `ParamDescriptorView` is app-target code and the app target has no test harness, so the
/// binding-resolution rule is extracted here as pure `ModelParameters` -> `ParamValue?` logic and
/// tested against every registered table.
final class ParamBindingTests: XCTestCase {

    /// The parameter state the renderer is handed on a model switch:
    /// `ConfigurationSection.handleSelectedModelChange()` assigns a fresh `ModelParameters` (17 of
    /// its 41 properties carry non-nil struct defaults) and then lets
    /// `ModelRegistry.initializeDefaultParams` fill only what is still nil.
    private func stateOnModelSwitch(_ table: [ParamDescriptor]) -> ModelParameters {
        var params = ModelParameters()
        ParamDefaults.merge(ParamDecoder.defaults(table), into: &params)
        return params
    }

    /// Every picker opens on a value it can display.
    ///
    /// `ParamTableConsistencyTests.testEveryPickerDefaultIsOneOfItsOwnOptions` checks the table:
    /// `defaultValue` ∈ `options`. That has been green since drift-ledger § B.11's fix and it is not
    /// enough — the binding reads `defaultValue` only when the stored field is nil, and the shared
    /// `duration` (5), `resolution` ("720p") and `frameRate` (30) are never nil after a model
    /// switch. So the stored value wins over the in-list default and a SwiftUI `Picker` whose
    /// selection matches no tag renders **blank**.
    func testEveryPickerOpensOnAValueItCanDisplay() {
        var offenders: [String] = []
        for id in ParamCatalog.migratedIds.sorted() {
            guard let table = ParamCatalog.descriptors(forModelId: id) else { continue }
            let params = stateOnModelSwitch(table)
            for descriptor in table {
                guard case .picker(let options, _) = descriptor.control,
                      let shown = ParamBinding.pickerSelection(for: descriptor, in: params),
                      !options.contains(shown)
                else { continue }
                offenders.append("\(id) · \(descriptor.wireKey): shows \(shown), options \(options)")
            }
        }
        XCTAssertEqual(offenders, [],
                       "\(offenders.count) pickers open blank:\n" + offenders.joined(separator: "\n"))
    }

    /// The fix must not turn every control back into its default: a stored value the picker *can*
    /// show still wins, which is what makes the user's own choice stick.
    func testAStoredValueThePickerCanShowIsPreferredOverTheDefault() {
        let descriptor = ParamDescriptor(
            wireKey: "resolution",
            field: .resolution,
            label: "Resolution",
            help: nil,
            control: .picker(options: [.string("720p"), .string("1080p")], style: .menu),
            defaultValue: .string("720p"),
            visibleWhen: nil,
            alwaysEmit: false,
            omitWhenEmpty: true,
            parseFallback: .setNil
        )
        var params = ModelParameters()
        params.resolution = "1080p"
        XCTAssertEqual(ParamBinding.pickerSelection(for: descriptor, in: params), .string("1080p"))
    }
}
