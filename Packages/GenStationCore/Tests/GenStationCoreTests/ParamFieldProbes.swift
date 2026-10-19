// Test-only probe values for the `ParamField` get/set bridge (Stage 2, Task 6).
//
// This lives in the test target, not in `ParamField` itself: it exists solely to drive the
// round-trip and aliasing tests, and the exhaustive `switch` means adding a case to `ParamField`
// without giving it a probe is a compile error rather than a silently unverified field.
//
// Every probe must differ from the property's struct default — otherwise the aliasing test cannot
// tell "wrote nothing" from "wrote the default". `testEveryProbeValueDiffersFromTheStructDefault`
// enforces that.

@testable import GenStationCore

extension ParamField {
    var probeValue: ParamValue? {
        switch self {
        case .seed:                      return .int(42)
        case .numImages:                 return .int(3)
        case .enableSafetyChecker:       return .bool(false)
        case .negativePrompt:            return .string("probe-negative")
        case .imageSizeMode:             return .string("custom")
        case .imageSizePreset:           return .string("square_hd")
        case .customWidth:               return .int(1280)
        case .customHeight:              return .int(720)
        case .guidanceScale:             return .double(7.5)
        case .duration:                  return .int(9)
        case .frameRate:                 return .int(24)
        case .numInferenceSteps:         return .int(28)
        case .stylePreset:               return .string("anime")
        case .resolution:                return .string("1080p")
        case .geminiResolution:          return .string("2K")
        case .cameraControl:             return .string("advanced")
        case .generateAudio:             return .bool(false)
        case .strength:                  return .double(0.35)
        case .watermark:                 return .bool(true)
        case .promptExpansionMode:       return .string("quality")
        case .enhancePrompt:             return .bool(false)
        case .aspectRatio:               return .string("9:16")
        case .acceleration:              return .string("high")
        case .safetyTolerance:           return .string("5")
        case .size:                      return .string("1536x1024")
        case .background:                return .string("transparent")
        case .moderation:                return .string("low")
        case .quality:                   return .string("high")
        case .loop:                      return .bool(true)
        case .cfgScale:                  return .double(0.9)
        case .cameraMovementType:        return .string("zoom")
        case .cameraMovementValue:       return .int(-4)
        case .shotType:                  return .string("multi")
        case .topazMode:                 return .string("sharpen-gen")
        case .subjectDetection:          return .string("Foreground")
        case .faceEnhancement:           return .bool(true)
        case .faceEnhancementCreativity: return .double(0.25)
        case .faceEnhancementStrength:   return .double(0.75)
        case .focusBoost:                return .double(0.6)
        case .minorDenoise:              return .double(0.15)
        case .outputFormat:              return .string("tiff")
        case .audioURL:                  return .string("https://example.com/a.mp3")
        }
    }
}
