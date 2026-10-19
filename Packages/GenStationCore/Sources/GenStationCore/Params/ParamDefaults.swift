// ParamDefaults — seeding a fresh `ModelParameters` from a model's own descriptor defaults.
//
// The app spelled this out as one `if params.x == nil { params.x = defaults.x }` line per field, and
// shipped 40 lines for 41 properties: `audioURL` had no line, so no model's descriptor default for
// `audio_url` could ever apply. Enumerating `ParamField.allCases` makes that class of omission
// unrepresentable — a new `ModelParameters` property needs a new `ParamField` case, and
// `ParamEncoderTests` already fails if the two drift.
//
// This is the ONLY place defaults are applied. Anything that wants a model's defaults in a payload
// calls `merge`; nobody re-writes the per-field loop, and nobody adds a second entry point.

import Foundation

public enum ParamDefaults {

    /// Copies `defaults` into every field of `params` that is currently nil, and leaves every field
    /// that already holds a value untouched.
    ///
    /// This is **not** "overwrite with defaults". `ModelParameters` carries 17 non-nil struct
    /// defaults, so for those fields the model's own default never applies — the struct's
    /// video-shaped `duration: 5` / `resolution: "720p"` / `frameRate: 30` win for every model. That
    /// asymmetry is frozen behaviour and an open decision (drift ledger § A.3, § B.11); this type
    /// changes *which fields are considered*, never the rule.
    public static func merge(_ defaults: ModelParameters, into params: inout ModelParameters) {
        for field in ParamField.allCases where params[field] == nil {
            params[field] = defaults[field]
        }
    }
}
