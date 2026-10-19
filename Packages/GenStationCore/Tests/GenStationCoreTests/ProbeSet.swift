// The shared `ModelParameters` probe set (Stage 2, Task 7).
//
// Every per-model equivalence assertion runs the legacy builder and the descriptor encoder over the
// same inputs, so those inputs are the harness's real coverage: a payload difference that no probe
// provokes is a difference the harness cannot see. Four probes, each covering a branch the others
// cannot reach:
//
//   1. `structDefaults`  — 18 of the 41 fields have non-nil struct defaults, and every `if let`
//                          builder gate is open for them.
//   2. `fullyPopulated`  — every optional non-nil, so every conditional key is emitted at least once.
//   3. `allNil`          — every optional nil, so every `if let` gate is *closed*. This is the probe
//                          that catches an `alwaysEmit` a table sets and the builder does not.
//   4. `customImageSize` — `imageSizeMode = "custom"`. Load-bearing and easy to omit: `imageSizeMode`
//                          has no struct default and `fullyPopulatedProbe()` sets it to `"preset"`, so
//                          probes 1-3 all take the String branch of the `image_size` composite and its
//                          `{width, height}` *object* branch is never exercised at all. That composite
//                          is the one control whose emitted JSON **type** changes, across 16 files.
//   5. `klingAdvancedCamera` — `cameraControl = "advanced"`. The same argument for the *other*
//                          composite, added in Task 8: `fullyPopulatedProbe()` sets `cameraControl`
//                          to `"{}"`, which takes the preset-String branch, so probes 1-4 leave the
//                          `{movement_type, movement_value}` object branch of `camera_control`
//                          unexercised across all 23 ids of the `klingVideo` table.
//
// Test-target only. Nothing ships these.

@testable import GenStationCore

enum ProbeSet {

    static let all: [(name: String, params: ModelParameters)] = [
        ("structDefaults", ModelParameters()),
        ("fullyPopulated", ModelParameters.fullyPopulatedProbe()),
        ("allNil", allNil),
        ("customImageSize", customImageSize),
        ("klingAdvancedCamera", klingAdvancedCamera)
    ]

    /// Built by clearing every case of `ParamField` rather than by listing 41 nils, so a field added
    /// to `ModelParameters` is covered here the moment it gets a `ParamField` case.
    private static let allNil: ModelParameters = {
        var params = ModelParameters()
        for field in ParamField.allCases { params[field] = nil }
        return params
    }()

    /// Struct defaults plus the custom-dimensions branch of the `image_size` composite.
    private static let customImageSize: ModelParameters = {
        var params = ModelParameters()
        params.imageSizeMode = "custom"
        params.customWidth = 1280
        params.customHeight = 720
        return params
    }()

    /// Struct defaults plus the object branch of Kling's `camera_control` composite. Both movement
    /// fields are set because the legacy builder's advanced branch is `if let type, let value` — a
    /// half-configured advanced mode emits nothing, which `ParamEncoderTests` pins separately.
    private static let klingAdvancedCamera: ModelParameters = {
        var params = ModelParameters()
        params.cameraControl = "advanced"
        params.cameraMovementType = "zoom"
        params.cameraMovementValue = -4
        return params
    }()
}
