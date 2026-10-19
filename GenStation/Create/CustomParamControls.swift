// CustomParamControls — the token → view map for `Control.custom` (Stage 2, Task 9).
//
// `GenStationCore` bans SwiftUI, so a control that cannot be expressed as a flat descriptor row
// travels as a `Control.CustomControl` token and is resolved here. That indirection is what keeps the
// descriptor tables pure data and therefore testable against the legacy builders.
//
// One token exists today. Kling's `camera_control` is a mode picker that reveals a movement type and
// an intensity slider and collapses to a nested object on the wire — three `ModelParameters` fields,
// one wire key, three possible JSON shapes. `ParamEncoder.klingCameraControlValue` is its emit half;
// this is its render half.

import SwiftUI
import GenStationCore

enum CustomParamControls {

    /// The fields a token's view renders itself.
    ///
    /// `ParamDescriptorView` skips any other row that names one of these, because the table carries
    /// companion rows for Kling's advanced movement type and value — they exist so the *table* records
    /// their controls and their `advanced`-only visibility, but they carry `wireKey: ""` and are drawn
    /// inside the camera-control card, not as cards of their own.
    static func ownedFields(_ token: Control.CustomControl) -> Set<ParamField> {
        switch token {
        case .klingCameraControl:
            return [.cameraControl, .cameraMovementType, .cameraMovementValue]
        }
    }

    @ViewBuilder
    static func view(for token: Control.CustomControl,
                     descriptor: ParamDescriptor,
                     params: Binding<ModelParameters>) -> some View {
        switch token {
        case .klingCameraControl:
            KlingCameraControlView(descriptor: descriptor, params: params)
        }
    }
}

/// Kling's camera-control card, reproducing `buildKlingVideoParamsView`'s block exactly.
///
/// The preset names are hard-coded because they are UI vocabulary, not wire vocabulary: the whole
/// block emits through one `camera_control` key, so the Task 8 generator had nothing to read them
/// off. `"none"` stores `nil`, which is what makes the encoder omit the key.
private struct KlingCameraControlView: View {

    let descriptor: ParamDescriptor
    let params: Binding<ModelParameters>

    var body: some View {
        let cameraControl = Binding<String>(
            get: { params.wrappedValue.cameraControl ?? "none" },
            set: { newValue in
                DispatchQueue.main.async {
                    params.wrappedValue.cameraControl = newValue == "none" ? nil : newValue
                }
            }
        )
        let movementType = Binding<String>(
            get: { params.wrappedValue.cameraMovementType ?? "horizontal" },
            set: { newValue in
                DispatchQueue.main.async { params.wrappedValue.cameraMovementType = newValue }
            }
        )
        let movementValue = Binding<Double>(
            get: { Double(params.wrappedValue.cameraMovementValue ?? 0) },
            set: { newValue in
                DispatchQueue.main.async { params.wrappedValue.cameraMovementValue = Int(newValue) }
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            Text(descriptor.label)
                .font(.subheadline)
                .fontWeight(.semibold)

            Picker("Camera Preset", selection: cameraControl) {
                Text("None").tag("none")
                Text("Down Back").tag("down_back")
                Text("Forward Up").tag("forward_up")
                Text("Right Turn Forward").tag("right_turn_forward")
                Text("Left Turn Forward").tag("left_turn_forward")
                Text("Advanced").tag("advanced")
            }
            .pickerStyle(.menu).labelsHidden()
            .frame(maxWidth: .infinity)

            if cameraControl.wrappedValue == "advanced" {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Movement Type", selection: movementType) {
                        Text("Horizontal").tag("horizontal")
                        Text("Vertical").tag("vertical")
                        Text("Pan").tag("pan")
                        Text("Tilt").tag("tilt")
                        Text("Roll").tag("roll")
                        Text("Zoom").tag("zoom")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)

                    Text("Movement Value: \(Int(movementValue.wrappedValue))")
                        .font(.caption)
                        .fontWeight(.medium)

                    Slider(value: movementValue, in: -10...10, step: 1)

                    if let help = descriptor.help, !help.isEmpty {
                        Text(help)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
    }
}
