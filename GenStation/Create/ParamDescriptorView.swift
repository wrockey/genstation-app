// ParamDescriptorView — the one renderer over `[ParamDescriptor]` (Stage 2, Task 9).
//
// Replaces the 61 hand-written `build*ParamsView` functions with a single generic view. It renders
// the same card chrome those views used, verbatim, so the migration is invisible: a
// `VStack(alignment: .leading, spacing: 8)` per row, `.padding()`, and a
// `RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1))` behind it, all inside a
// `VStack(spacing: 16)` that is itself padded and stretched.
//
// **Every write defers through `DispatchQueue.main.async`.** This is not stylistic. The binding chain
// terminates in `@Published aimlAdvancedParams` on `SettingsState`, whose `didSet` clears
// `customAIMLPayload` and `customAIMLEndpoint` — two more `@Published` properties; `AppState.init`
// re-forwards each substate's `objectWillChange` through a second `DispatchQueue.main.async`; and
// `AdvancedAIMLSettingsView` has `.onChange(of: params)` rebuilding the payload preview. A synchronous
// write during body evaluation therefore re-enters. Commit `e3ba96e` ("Fix view-update publishing")
// is the scar. All 315 legacy setters deferred for this reason and so does every setter here.
//
// The one deliberate exception, also inherited: the seed "randomize" button writes **synchronously**,
// because a button action runs after body evaluation, not during it.
//
// Visibility is not decided here. `ParamDescriptor.isVisible(params:context:)` is the single predicate
// the encoder also calls — that identity is the design (§ 3.2), and it is what stops a hidden control
// shipping on the wire.

import SwiftUI
import GenStationCore

struct ParamDescriptorView: View {

    let descriptors: [ParamDescriptor]
    @Binding var params: ModelParameters
    let context: ParamContext

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Indexed rather than filtered so a row's view identity does not shift when a
            // conditional row above it appears or disappears.
            ForEach(descriptors.indices, id: \.self) { index in
                row(descriptors[index])
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    // MARK: - Row dispatch

    @ViewBuilder
    private func row(_ descriptor: ParamDescriptor) -> some View {
        if descriptor.isVisible(params: params, context: context), !isOwnedByACustomControl(descriptor) {
            switch descriptor.control {
            case .picker(let options, let style):
                pickerCard(descriptor, options: options, style: style)
            case .text(let placeholder):
                textCard(descriptor, placeholder: placeholder)
            case .slider(let range, let step):
                sliderCard(descriptor, range: range, step: step)
            case .toggle:
                toggleCard(descriptor)
            case .seed(let range):
                seedCard(descriptor, range: range)
            case .imageSize(let spec):
                imageSizeCard(descriptor, spec: spec)
            case .info(let text):
                infoCard(descriptor, text: text)
            case .none:
                // Emitted but not rendered — `enable_safety_checker`, the constant `aspect_ratio`
                // rows, Wan 2.6's seed.
                EmptyView()
            case .custom(let token):
                customCard(descriptor, token: token)
            }
        }
    }

    /// A `.custom` control renders a whole block, not a single row, so the table's companion rows for
    /// the fields it owns must not also render — Kling's advanced movement type and value live inside
    /// the camera-control card in the legacy view, and they carry `wireKey: ""` precisely because the
    /// custom row emits for them.
    private func isOwnedByACustomControl(_ descriptor: ParamDescriptor) -> Bool {
        if case .custom = descriptor.control { return false }
        guard let field = descriptor.field else { return false }
        return ownedFields.contains(field)
    }

    private var ownedFields: Set<ParamField> {
        var fields: Set<ParamField> = []
        for descriptor in descriptors {
            if case .custom(let token) = descriptor.control {
                fields.formUnion(CustomParamControls.ownedFields(token))
            }
        }
        return fields
    }

    // MARK: - Controls

    @ViewBuilder
    private func pickerCard(_ descriptor: ParamDescriptor,
                            options: [ParamValue],
                            style: Control.PickerStyle) -> some View {
        card {
            header(descriptor.label)

            // The tag type has to be concrete, so the picker is built per storage kind. Only `.int`
            // and `.string` appear in any table; the other two fall through to a string picker.
            switch descriptor.field?.kind ?? options.first?.kind ?? .string {
            case .int:
                styledPicker(descriptor,
                             selection: intBinding(descriptor, fallback: firstInt(options)),
                             options: options,
                             style: style) { value in
                    if case .int(let raw) = value { return raw } else { return nil }
                }
            default:
                styledPicker(descriptor,
                             selection: stringBinding(descriptor, fallback: firstString(options)),
                             options: options,
                             style: style) { value in
                    if case .string(let raw) = value { return raw } else { return nil }
                }
            }

            helpCaption(descriptor.help)
        }
    }

    @ViewBuilder
    private func styledPicker<T: Hashable>(_ descriptor: ParamDescriptor,
                                           selection: Binding<T>,
                                           options: [ParamValue],
                                           style: Control.PickerStyle,
                                           tag: @escaping (ParamValue) -> T?) -> some View {
        let picker = Picker(descriptor.label, selection: selection) {
            ForEach(options.indices, id: \.self) { index in
                if let tagValue = tag(options[index]) {
                    Text(ParamOptionLabel.text(for: options[index], field: descriptor.field))
                        .tag(tagValue)
                }
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .paramHelp(descriptor.help)

        switch style {
        case .menu:      picker.pickerStyle(.menu)
        case .segmented: picker.pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func textCard(_ descriptor: ParamDescriptor, placeholder: String) -> some View {
        card {
            header(descriptor.label)
            textField(descriptor, placeholder: placeholder)
            helpCaption(descriptor.help)
        }
    }

    /// The iOS keyboard modifiers are per-field, and dropping them reaches the wire: without
    /// `.textInputAutocapitalization(.never)` iOS capitalises the first letter of a typed URL, so
    /// `bytedance/omnihuman`'s `audio_url` ships as `"Https://…"` and the request fails. The legacy
    /// views carried these under `#if os(iOS)` and so do we; `.audioURL` is the only URL-valued text
    /// row in any table (every other `.text` row is a negative prompt, where sentence capitalisation
    /// is right and legacy set nothing).
    @ViewBuilder
    private func textField(_ descriptor: ParamDescriptor, placeholder: String) -> some View {
        let field = TextField(placeholder, text: optionalStringBinding(descriptor))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
            .paramHelp(descriptor.help)

        #if os(iOS)
        if descriptor.field == .audioURL {
            field
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            field
        }
        #else
        field
        #endif
    }

    @ViewBuilder
    private func sliderCard(_ descriptor: ParamDescriptor,
                            range: ClosedRange<Double>,
                            step: Double) -> some View {
        let isInteger = descriptor.field?.kind == .int
        let value = doubleBinding(descriptor, fallback: range.lowerBound, isInteger: isInteger)

        card {
            // Legacy sliders put the live value in the header — "CFG Scale: 0.50",
            // "Inference Steps: 12" — rather than beside the track.
            header("\(descriptor.label): \(formatted(value.wrappedValue, isInteger: isInteger, step: step))")

            Slider(value: value, in: range, step: step)
                .paramHelp(descriptor.help)

            helpCaption(descriptor.help)
        }
    }

    @ViewBuilder
    private func toggleCard(_ descriptor: ParamDescriptor) -> some View {
        card {
            // A toggle carries its own label, so it gets no separate header — matching the legacy
            // views, where the toggle is the only thing in its card.
            Toggle(descriptor.label, isOn: boolBinding(descriptor))
                .toggleStyle(.switch)
                .paramHelp(descriptor.help)

            helpCaption(descriptor.help)
        }
    }

    @ViewBuilder
    private func seedCard(_ descriptor: ParamDescriptor, range: ClosedRange<Int>) -> some View {
        let seedText = seedTextBinding(descriptor)
        let boundParams = $params

        card {
            header(descriptor.label)

            HStack {
                seedField(seedText)

                Button(action: {
                    // Synchronous on purpose: a button action runs outside body evaluation, so the
                    // re-entrancy the deferred setters avoid cannot happen here. The 31 legacy
                    // randomize buttons all write this way.
                    guard let field = descriptor.field else { return }
                    boundParams.wrappedValue[field] = .int(Int.random(in: range))
                }) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .paramHelp(descriptor.help)

            helpCaption(descriptor.help)
        }
    }

    /// A seed is an `Int?` edited as text, so iOS gets the numeric keypad. Two of the legacy seed
    /// fields (`RunwayGen4ParamsView`, `RunwayGen4AlephParamsView`) set `.keyboardType(.numberPad)`
    /// and the other 29 set nothing; the field only ever accepts digits, so this applies it to all of
    /// them rather than reproducing that inconsistency. Recorded in the drift ledger.
    @ViewBuilder
    private func seedField(_ text: Binding<String>) -> some View {
        let field = TextField("Random if empty", text: text)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)

        #if os(iOS)
        field.keyboardType(.numberPad)
        #else
        field
        #endif
    }

    /// The `image_size` composite, across the 16 image models that carry one.
    ///
    /// Every list and every nil fallback comes from the row's `ImageSizeSpec`, never from a constant
    /// here: the legacy views disagree on all of them. `seedream45` offers `2K`/`4K` where the other
    /// fifteen offer the `square_hd` family; the six Flux views fall back to a 768px **height** where
    /// everyone else uses 1024; and there are eight distinct width/height lists. Hard-coding one set
    /// would have shown thirteen models a size they do not accept — and, because the binding fallbacks
    /// are also what the encoder emits for a nil field, sent it too.
    @ViewBuilder
    private func imageSizeCard(_ descriptor: ParamDescriptor, spec: ImageSizeSpec) -> some View {
        let boundParams = $params
        let mode = Binding<String>(
            get: { boundParams.wrappedValue.imageSizeMode ?? "preset" },
            set: { newValue in DispatchQueue.main.async { boundParams.wrappedValue.imageSizeMode = newValue } }
        )
        let preset = Binding<String>(
            get: { boundParams.wrappedValue.imageSizePreset ?? spec.presetFallback },
            set: { newValue in DispatchQueue.main.async { boundParams.wrappedValue.imageSizePreset = newValue } }
        )
        let width = Binding<Int>(
            get: { boundParams.wrappedValue.customWidth ?? spec.widthFallback },
            set: { newValue in DispatchQueue.main.async { boundParams.wrappedValue.customWidth = newValue } }
        )
        let height = Binding<Int>(
            get: { boundParams.wrappedValue.customHeight ?? spec.heightFallback },
            set: { newValue in DispatchQueue.main.async { boundParams.wrappedValue.customHeight = newValue } }
        )

        card {
            header(descriptor.label)

            Picker("Mode", selection: mode) {
                Text("Preset").tag("preset")
                Text("Custom").tag("custom")
            }
            .pickerStyle(.segmented).labelsHidden()
            .frame(maxWidth: .infinity)

            if mode.wrappedValue == "preset" {
                Picker("Preset", selection: preset) {
                    ForEach(spec.presets, id: \.self) { value in
                        Text(Self.presetLabel(value)).tag(value)
                    }
                }
                .pickerStyle(.menu).labelsHidden()
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Width").font(.caption).foregroundStyle(.secondary)
                    dimensionPicker("Width", selection: width, options: spec.dimensions)

                    Text("Height").font(.caption).foregroundStyle(.secondary)
                    dimensionPicker("Height", selection: height, options: spec.dimensions)
                }
            }

            // The composite is the one card whose guidance never reached the user: it is the only
            // control whose `help` this renderer used to drop. Flux 2 Pro's is load-bearing — its
            // encoder silently omits `image_size` altogether above 2048.
            helpCaption(descriptor.help)
        }
        .paramHelp(descriptor.help)
    }

    private func dimensionPicker(_ title: String, selection: Binding<Int>, options: [Int]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.self) { value in
                Text("\(value) px").tag(value)
            }
        }
        .pickerStyle(.menu).labelsHidden()
        .frame(maxWidth: .infinity)
    }

    /// `square_hd` → "Square HD", `portrait_4_3` → "Portrait 4:3", `2K` → "2K".
    ///
    /// Derived rather than tabulated because the wire values are the data and the display strings are
    /// not: adding a preset to a table should not also require adding a label to a second list here.
    /// The rule reproduces every one of the labels the 16 legacy views hand-wrote.
    static func presetLabel(_ preset: String) -> String {
        let parts = preset.split(separator: "_").map(String.init)
        guard parts.count > 1 else { return preset.prefix(1).uppercased() + preset.dropFirst() }

        var words: [String] = []
        var index = 0
        while index < parts.count {
            let part = parts[index]
            if part.allSatisfy(\.isNumber), index + 1 < parts.count, parts[index + 1].allSatisfy(\.isNumber) {
                words.append("\(part):\(parts[index + 1])")
                index += 2
            } else {
                words.append(part == "hd" ? "HD" : part.prefix(1).uppercased() + part.dropFirst())
                index += 1
            }
        }
        return words.joined(separator: " ")
    }

    @ViewBuilder
    private func infoCard(_ descriptor: ParamDescriptor, text: String) -> some View {
        card {
            if !descriptor.label.isEmpty {
                header(descriptor.label)
            }
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func customCard(_ descriptor: ParamDescriptor, token: Control.CustomControl) -> some View {
        CustomParamControls.view(for: token, descriptor: descriptor, params: $params)
    }

    // MARK: - Chrome

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.semibold)
    }

    /// `help` on iOS.
    ///
    /// `ParamDescriptor.help` carries ~94 strings the legacy views rendered as a visible
    /// `.font(.caption).foregroundColor(.secondary)` line under the control. `.help(_:)` is a *hover*
    /// tooltip, and there is no hover on iOS or iPadOS — so on those platforms every one of them
    /// rendered as nothing at all. This puts them back the way the legacy views drew them. macOS keeps
    /// the tooltip and gets no extra line, so its layout is unchanged.
    @ViewBuilder
    private func helpCaption(_ text: String?) -> some View {
        #if os(macOS)
        EmptyView()
        #else
        if let text, !text.isEmpty {
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        #endif
    }

    private func formatted(_ value: Double, isInteger: Bool, step: Double) -> String {
        if isInteger { return "\(Int(value))" }
        // Legacy views show two decimals for fine steps (Kling's 0.05 cfg_scale) and one otherwise
        // (Flux's 0.5 guidance_scale).
        return String(format: step < 0.1 ? "%.2f" : "%.1f", value)
    }

    // MARK: - Bindings
    //
    // Each of these captures `$params` — the `Binding`, not `self` — so the setter is the legacy
    // idiom exactly: `DispatchQueue.main.async { params.wrappedValue[field] = newValue }`.

    /// The getter defers to `ParamBinding.pickerSelection`, which refuses a stored value this
    /// picker's own option list cannot show — a `Picker` whose selection matches no tag renders
    /// blank, and 47 models opened that way. `fallback` stays as the last resort (the picker's first
    /// option) for a row with no displayable default at all. **The setter is untouched**: the
    /// deferred-write idiom is load-bearing, and nothing here rewrites storage, so no payload moves.
    private func stringBinding(_ descriptor: ParamDescriptor, fallback: String) -> Binding<String> {
        let boundParams = $params
        let field = descriptor.field
        return Binding<String>(
            get: {
                guard case .string(let value)? = ParamBinding.pickerSelection(
                    for: descriptor, in: boundParams.wrappedValue) else { return fallback }
                return value
            },
            set: { newValue in
                guard let field else { return }
                DispatchQueue.main.async { boundParams.wrappedValue[field] = .string(newValue) }
            }
        )
    }

    /// The text-field variant: an empty string stores `nil`, not `""`.
    ///
    /// This is load-bearing, not tidiness. `wan25I2V`'s `negative_prompt` row has
    /// `omitWhenEmpty: false`, so storing `""` would make the encoder emit `"negative_prompt": ""`
    /// where the legacy builder's `if let` emitted nothing. Ten of the sixteen legacy text setters
    /// wrote `nil`; the other six sat on rows whose builder gated on `!isEmpty`, where both spellings
    /// emit the same thing. `nil` is therefore correct for every row.
    private func optionalStringBinding(_ descriptor: ParamDescriptor) -> Binding<String> {
        let boundParams = $params
        let field = descriptor.field
        return Binding<String>(
            get: {
                guard let field, case .string(let value)? = boundParams.wrappedValue[field] else { return "" }
                return value
            },
            set: { newValue in
                guard let field else { return }
                DispatchQueue.main.async {
                    boundParams.wrappedValue[field] = newValue.isEmpty ? nil : .string(newValue)
                }
            }
        )
    }

    /// Same rule as `stringBinding`, for the `.int` pickers (`duration`, `fps`, `num_images`).
    private func intBinding(_ descriptor: ParamDescriptor, fallback: Int) -> Binding<Int> {
        let boundParams = $params
        let field = descriptor.field
        return Binding<Int>(
            get: {
                guard case .int(let value)? = ParamBinding.pickerSelection(
                    for: descriptor, in: boundParams.wrappedValue) else { return fallback }
                return value
            },
            set: { newValue in
                guard let field else { return }
                DispatchQueue.main.async { boundParams.wrappedValue[field] = .int(newValue) }
            }
        )
    }

    private func boolBinding(_ descriptor: ParamDescriptor) -> Binding<Bool> {
        let boundParams = $params
        let field = descriptor.field
        let fallbackValue: Bool = {
            if case .bool(let value)? = descriptor.defaultValue { return value }
            return false
        }()
        return Binding<Bool>(
            get: {
                guard let field, case .bool(let value)? = boundParams.wrappedValue[field] else { return fallbackValue }
                return value
            },
            set: { newValue in
                guard let field else { return }
                DispatchQueue.main.async { boundParams.wrappedValue[field] = .bool(newValue) }
            }
        )
    }

    /// Sliders always drive a `Double`; `isInteger` rounds on the way back into `Int` storage, the way
    /// the legacy `Int(newValue)` setters did.
    private func doubleBinding(_ descriptor: ParamDescriptor,
                               fallback: Double,
                               isInteger: Bool) -> Binding<Double> {
        let boundParams = $params
        let field = descriptor.field
        let fallbackValue: Double = {
            switch descriptor.defaultValue {
            case .double(let value): return value
            case .int(let value):    return Double(value)
            default:                 return fallback
            }
        }()
        return Binding<Double>(
            get: {
                guard let field, let stored = boundParams.wrappedValue[field] else { return fallbackValue }
                switch stored {
                case .double(let value): return value
                case .int(let value):    return Double(value)
                default:                 return fallbackValue
                }
            },
            set: { newValue in
                guard let field else { return }
                DispatchQueue.main.async {
                    boundParams.wrappedValue[field] = isInteger ? .int(Int(newValue)) : .double(newValue)
                }
            }
        )
    }

    /// The seed field is an `Int?` edited as text: empty means "random at generation time", so it
    /// stores `nil`, and a non-numeric string stores `nil` too — both exactly as the legacy
    /// `newValue.isEmpty ? nil : Int(newValue)` did.
    private func seedTextBinding(_ descriptor: ParamDescriptor) -> Binding<String> {
        let boundParams = $params
        let field = descriptor.field
        return Binding<String>(
            get: {
                guard let field, case .int(let value)? = boundParams.wrappedValue[field] else { return "" }
                return String(value)
            },
            set: { newValue in
                guard let field else { return }
                DispatchQueue.main.async {
                    boundParams.wrappedValue[field] = newValue.isEmpty ? nil : Int(newValue).map(ParamValue.int)
                }
            }
        )
    }

    private func firstString(_ options: [ParamValue]) -> String {
        for option in options { if case .string(let value) = option { return value } }
        return ""
    }

    private func firstInt(_ options: [ParamValue]) -> Int {
        for option in options { if case .int(let value) = option { return value } }
        return 0
    }
}

// MARK: - Option labels

/// The display text for a picker option.
///
/// `Control.picker` carries option **values**, not labels — the Task 8 generator read them off the
/// wire, where `Text("5 seconds").tag(5)` is just `5`. So the label has to be derived. These rules
/// reproduce the legacy text for the common cases ("720p", "16:9", "5 seconds"); where a legacy view
/// decorated a value ("16:9 (Landscape)" in the Kling and Seedance views) the decoration is lost.
/// Recorded for the drift ledger — the fix is an `optionLabels` field on `ParamDescriptor` and a
/// regenerate, not a lookup table here.
enum ParamOptionLabel {

    static func text(for value: ParamValue, field: ParamField?) -> String {
        switch value {
        case .string(let raw):
            return prettified(raw)
        case .int(let raw):
            // The only int pickers are duration, num_images and frame_rate; only duration reads as a
            // unit in the legacy views.
            return field == .duration ? "\(raw) second\(raw == 1 ? "" : "s")" : "\(raw)"
        case .double(let raw):
            return String(format: "%g", raw)
        case .bool(let raw):
            return raw ? "On" : "Off"
        }
    }

    /// `square_hd` → `Square HD`; `720p`, `16:9` and `Super Focus V2` are returned untouched.
    ///
    /// The empty string is a real option value, not a missing one: PixVerse's `style` picker offers
    /// `Text("None").tag("")` so the user can switch the style back off, and the row's `omitWhenEmpty`
    /// then keeps `""` off the wire. Rendered literally it is a blank menu row with nothing to click,
    /// so it keeps the legacy label. This is the only empty-valued option in any table.
    private static func prettified(_ raw: String) -> String {
        guard !raw.isEmpty else { return "None" }
        guard raw.contains("_") else { return raw }
        return raw.split(separator: "_").map { word -> String in
            let lower = word.lowercased()
            if let acronym = acronyms[lower] { return acronym }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }

    private static let acronyms: [String: String] = [
        "hd": "HD", "sd": "SD", "hdr": "HDR", "3d": "3D",
        "1k": "1K", "2k": "2K", "4k": "4K", "8k": "8K",
        "png": "PNG", "jpeg": "JPEG", "jpg": "JPG", "webp": "WebP"
    ]
}

// MARK: - Conditional help

extension View {
    /// The macOS hover tooltip for `descriptor.help`, without materialising an empty one when the
    /// descriptor has none.
    ///
    /// macOS only, deliberately: `.help(_:)` compiles on iOS but only ever surfaces as an
    /// accessibility hint there, which is why the same strings also render as a visible caption via
    /// `ParamDescriptorView.helpCaption(_:)`. Applying both would read the text twice to VoiceOver.
    @ViewBuilder
    func paramHelp(_ text: String?) -> some View {
        #if os(macOS)
        if let text, !text.isEmpty {
            self.help(text)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
