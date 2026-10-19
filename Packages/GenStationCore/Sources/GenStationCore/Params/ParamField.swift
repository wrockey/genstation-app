// ParamField — the generic get/set bridge over `ModelParameters` (Stage 2, Task 6).
//
// One case per stored property, so a descriptor can read and write a field it names as data without
// reflection. This is 41 hand-written accessor pairs and nothing else in the app exercises them: a
// single swapped case (`.cfgScale` reading `guidanceScale`) would silently corrupt exactly one
// model's payload and pass every other test. `ParamEncoderTests` therefore round-trips every case and
// asserts no two cases touch the same storage.

import Foundation

public enum ParamField: String, CaseIterable, Hashable, Sendable {
    case seed
    case numImages
    case enableSafetyChecker
    case negativePrompt
    case imageSizeMode
    case imageSizePreset
    case customWidth
    case customHeight
    case guidanceScale
    case duration
    case frameRate
    case numInferenceSteps
    case stylePreset
    case resolution
    case geminiResolution
    case cameraControl
    case generateAudio
    case strength
    case watermark
    case promptExpansionMode
    case enhancePrompt
    case aspectRatio
    case acceleration
    case safetyTolerance
    case size
    case background
    case moderation
    case quality
    case loop
    case cfgScale
    case cameraMovementType
    case cameraMovementValue
    case shotType
    case topazMode
    case subjectDetection
    case faceEnhancement
    case faceEnhancementCreativity
    case faceEnhancementStrength
    case focusBoost
    case minorDenoise
    case outputFormat
    case audioURL
}

extension ParamField {
    /// The `ParamValue` case this field's storage accepts. Callers reading untyped JSON coerce to
    /// this before writing (`ParamDecoder`), and the subscript setter uses it to reject a
    /// mismatched write outright rather than silently storing nil.
    public var kind: ParamValue.Kind {
        switch self {
        case .seed, .numImages, .customWidth, .customHeight, .duration, .frameRate,
             .numInferenceSteps, .cameraMovementValue:
            return .int
        case .enableSafetyChecker, .generateAudio, .watermark, .enhancePrompt, .loop, .faceEnhancement:
            return .bool
        case .guidanceScale, .strength, .cfgScale, .faceEnhancementCreativity,
             .faceEnhancementStrength, .focusBoost, .minorDenoise:
            return .double
        case .negativePrompt, .imageSizeMode, .imageSizePreset, .stylePreset, .resolution,
             .geminiResolution, .cameraControl, .aspectRatio, .acceleration, .safetyTolerance,
             .promptExpansionMode, .size, .background, .moderation, .quality, .cameraMovementType, .shotType,
             .topazMode, .subjectDetection, .outputFormat, .audioURL:
            return .string
        }
    }
}

extension ModelParameters {

    /// Reads and writes the named field. A write whose `ParamValue` case does not match the field's
    /// `kind` is ignored — it does **not** clear the property. Callers coming from untyped JSON
    /// coerce first (`ParamDecoder`).
    public subscript(field: ParamField) -> ParamValue? {
        get {
            switch field {
            case .seed:                      return seed.map(ParamValue.int)
            case .numImages:                 return numImages.map(ParamValue.int)
            case .enableSafetyChecker:       return enableSafetyChecker.map(ParamValue.bool)
            case .negativePrompt:            return negativePrompt.map(ParamValue.string)
            case .imageSizeMode:             return imageSizeMode.map(ParamValue.string)
            case .imageSizePreset:           return imageSizePreset.map(ParamValue.string)
            case .customWidth:               return customWidth.map(ParamValue.int)
            case .customHeight:              return customHeight.map(ParamValue.int)
            case .guidanceScale:             return guidanceScale.map(ParamValue.double)
            case .duration:                  return duration.map(ParamValue.int)
            case .frameRate:                 return frameRate.map(ParamValue.int)
            case .numInferenceSteps:         return numInferenceSteps.map(ParamValue.int)
            case .stylePreset:               return stylePreset.map(ParamValue.string)
            case .resolution:                return resolution.map(ParamValue.string)
            case .geminiResolution:          return geminiResolution.map(ParamValue.string)
            case .cameraControl:             return cameraControl.map(ParamValue.string)
            case .generateAudio:             return generateAudio.map(ParamValue.bool)
            case .strength:                  return strength.map(ParamValue.double)
            case .watermark:                 return watermark.map(ParamValue.bool)
            case .promptExpansionMode:       return promptExpansionMode.map(ParamValue.string)
            case .enhancePrompt:             return enhancePrompt.map(ParamValue.bool)
            case .aspectRatio:               return aspectRatio.map(ParamValue.string)
            case .acceleration:              return acceleration.map(ParamValue.string)
            case .safetyTolerance:           return safetyTolerance.map(ParamValue.string)
            case .size:                      return size.map(ParamValue.string)
            case .background:                return background.map(ParamValue.string)
            case .moderation:                return moderation.map(ParamValue.string)
            case .quality:                   return quality.map(ParamValue.string)
            case .loop:                      return loop.map(ParamValue.bool)
            case .cfgScale:                  return cfgScale.map(ParamValue.double)
            case .cameraMovementType:        return cameraMovementType.map(ParamValue.string)
            case .cameraMovementValue:       return cameraMovementValue.map(ParamValue.int)
            case .shotType:                  return shotType.map(ParamValue.string)
            case .topazMode:                 return topazMode.map(ParamValue.string)
            case .subjectDetection:          return subjectDetection.map(ParamValue.string)
            case .faceEnhancement:           return faceEnhancement.map(ParamValue.bool)
            case .faceEnhancementCreativity: return faceEnhancementCreativity.map(ParamValue.double)
            case .faceEnhancementStrength:   return faceEnhancementStrength.map(ParamValue.double)
            case .focusBoost:                return focusBoost.map(ParamValue.double)
            case .minorDenoise:              return minorDenoise.map(ParamValue.double)
            case .outputFormat:              return outputFormat.map(ParamValue.string)
            case .audioURL:                  return audioURL.map(ParamValue.string)
            }
        }
        set {
            guard newValue == nil || newValue?.kind == field.kind else { return }
            switch field {
            case .seed:                      seed = newValue?.intValue
            case .numImages:                 numImages = newValue?.intValue
            case .enableSafetyChecker:       enableSafetyChecker = newValue?.boolValue
            case .negativePrompt:            negativePrompt = newValue?.stringValue
            case .imageSizeMode:             imageSizeMode = newValue?.stringValue
            case .imageSizePreset:           imageSizePreset = newValue?.stringValue
            case .customWidth:               customWidth = newValue?.intValue
            case .customHeight:              customHeight = newValue?.intValue
            case .guidanceScale:             guidanceScale = newValue?.doubleValue
            case .duration:                  duration = newValue?.intValue
            case .frameRate:                 frameRate = newValue?.intValue
            case .numInferenceSteps:         numInferenceSteps = newValue?.intValue
            case .stylePreset:               stylePreset = newValue?.stringValue
            case .resolution:                resolution = newValue?.stringValue
            case .geminiResolution:          geminiResolution = newValue?.stringValue
            case .cameraControl:             cameraControl = newValue?.stringValue
            case .generateAudio:             generateAudio = newValue?.boolValue
            case .strength:                  strength = newValue?.doubleValue
            case .watermark:                 watermark = newValue?.boolValue
            case .promptExpansionMode:       promptExpansionMode = newValue?.stringValue
            case .enhancePrompt:             enhancePrompt = newValue?.boolValue
            case .aspectRatio:               aspectRatio = newValue?.stringValue
            case .acceleration:              acceleration = newValue?.stringValue
            case .safetyTolerance:           safetyTolerance = newValue?.stringValue
            case .size:                      size = newValue?.stringValue
            case .background:                background = newValue?.stringValue
            case .moderation:                moderation = newValue?.stringValue
            case .quality:                   quality = newValue?.stringValue
            case .loop:                      loop = newValue?.boolValue
            case .cfgScale:                  cfgScale = newValue?.doubleValue
            case .cameraMovementType:        cameraMovementType = newValue?.stringValue
            case .cameraMovementValue:       cameraMovementValue = newValue?.intValue
            case .shotType:                  shotType = newValue?.stringValue
            case .topazMode:                 topazMode = newValue?.stringValue
            case .subjectDetection:          subjectDetection = newValue?.stringValue
            case .faceEnhancement:           faceEnhancement = newValue?.boolValue
            case .faceEnhancementCreativity: faceEnhancementCreativity = newValue?.doubleValue
            case .faceEnhancementStrength:   faceEnhancementStrength = newValue?.doubleValue
            case .focusBoost:                focusBoost = newValue?.doubleValue
            case .minorDenoise:              minorDenoise = newValue?.doubleValue
            case .outputFormat:              outputFormat = newValue?.stringValue
            case .audioURL:                  audioURL = newValue?.stringValue
            }
        }
    }
}

extension ParamValue {
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var intValue: Int? { if case .int(let v) = self { return v }; return nil }
    var doubleValue: Double? { if case .double(let v) = self { return v }; return nil }
    var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
}
