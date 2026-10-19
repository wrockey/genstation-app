// ParamBinding — the rule the renderer's picker binding follows, as testable logic.
//
// `ParamDescriptorView` is app-target code and the app target has no test harness, so a defect in
// what a control *displays* has never been visible to `swift test`. The rule is pure
// `ModelParameters` -> `ParamValue?` logic, so it lives here and the view calls it.

import Foundation

public enum ParamBinding {

    /// The value a `.picker` control opens on, given the parameters currently stored.
    ///
    /// A SwiftUI `Picker` whose selection matches no `tag` renders **blank**, so the property that
    /// matters is: a non-nil return is always one of `options`. The stored value is preferred, but
    /// only if the picker can actually show it — `ModelParameters` has one `duration`, one
    /// `resolution` and one `frameRate` shared by every model, and their non-nil struct defaults
    /// (5, "720p", 30) sit outside the option list of 47 models' pickers. Drift ledger § B.11's fix
    /// made every `defaultValue` in-list, which is necessary and not sufficient: the binding only
    /// consults `defaultValue` when the stored field is nil, and after
    /// `ConfigurationSection.handleSelectedModelChange()` those fields are never nil.
    ///
    /// **Display only.** The stored value is not rewritten, so this changes no payload; what an
    /// untouched control *sends* is still drift ledger § A.3 / § B.11's open decision.
    ///
    /// Returns nil when neither the stored value nor `defaultValue` is displayable; the renderer
    /// then falls back to the picker's first option, which is in-list by construction.
    ///
    /// Non-picker controls have no option list to violate, so their stored value passes through.
    public static func pickerSelection(for descriptor: ParamDescriptor,
                                       in params: ModelParameters) -> ParamValue? {
        guard case .picker(let options, _) = descriptor.control else {
            if let field = descriptor.field, let stored = params[field] { return stored }
            return descriptor.defaultValue
        }
        if let field = descriptor.field, let stored = params[field], options.contains(stored) {
            return stored
        }
        if let fallback = descriptor.defaultValue, options.contains(fallback) {
            return fallback
        }
        return nil
    }
}
