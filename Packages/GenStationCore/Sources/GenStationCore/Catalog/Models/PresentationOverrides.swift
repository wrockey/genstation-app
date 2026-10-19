// Presentation overrides — the small set of names we show INSTEAD of the vendor's own.
//
// Stage 3 Task 12. Design § 3.4 (revised 2026-07-27): `displayName` comes from the API's
// `info.name`, which the captured /models response carries on 907 of 907 entries. This file is the
// documented exception list, and it has exactly two halves.
//
// 1. `geminiOverrides` — the pre-existing case. Gemini's model list is a live `v1beta/models`
//    fetch, so there are no static Gemini rows in the catalog; what IS static is the handful of
//    names the app shows instead of Google's live `displayName`, plus the one id that carries a
//    "NEW" capsule. Both were written inline in ConfigurationSection.swift — the display-name
//    switch TWICE. Keys are `GeminiModel.shortName` (GenStationApp.swift:92-94), i.e. the API name
//    with the leading "models/" stripped. Values reproduce today's strings byte-for-byte, emoji
//    included. These entries are why the override mechanism exists at all: the app has always
//    disagreed with Google here, deliberately.
//
// 2. `displayNameOverrides` — the catalog's half. The AI/ML API gives TWELVE models only FIVE
//    names: both FLUX Dev variants are "Flux Dev", both Kontext Max variants are "Flux Kontext
//    Max", both Kontext Pro variants are "Flux Kontext Pro", all three Veo 3.1 directions are
//    "Veo 3.1", and all three Veo 3.1 Fast directions are "Veo 3.1 Fast". Two rows with the same
//    name are indistinguishable in a picker, so each gets the vendor's name plus the direction the
//    id already states. `CatalogPresentationTests.testNoTwoModelsShareADisplayName` is what forces
//    this list to stay complete, and
//    `testEveryDisplayNameIsTheVendorsUnlessExplicitlyOverridden` is what forces it to stay short.
//
// Do NOT add an entry here to fix a name you merely dislike. An entry is a standing disagreement
// with the vendor that no test can adjudicate; a vendor rename is caught by the fixture test and
// should usually be accepted rather than overridden.

import Foundation

extension Catalog {

    /// What the UI shows for a live provider row, when we override the provider's own name.
    public struct PresentationOverride: Sendable, Hashable {
        public let displayName: String
        public let family: String
        /// Renders the green "NEW" capsule (ConfigurationSection.swift).
        public let isNew: Bool

        public init(displayName: String, family: String, isNew: Bool = false) {
            self.displayName = displayName
            self.family = family
            self.isNew = isNew
        }
    }

    /// Absent key ⇒ Google's live `displayName` is used unchanged, which is what the `default:` arm
    /// of both switches did. Do not add ids that are not in those switches today: adding one
    /// changes what the Gemini menu says, and nothing in this package can check that it is right.
    public static let geminiOverrides: [String: PresentationOverride] = [
        "gemini-3-pro-image-preview": PresentationOverride(
            displayName: "Gemini 3 Pro Image Preview (Nano Banana Pro) 🍌",
            family: "Gemini 3 Pro Image",
            isNew: true
        ),
        "gemini-2.5-flash-image": PresentationOverride(
            displayName: "Gemini 2.5 Flash Image (Nano Banana) 🍌",
            family: "Gemini 2.5 Flash Image"
        ),
        "gemini-2.5-flash-image-preview": PresentationOverride(
            displayName: "Gemini 2.5 Flash Image (Nano Banana) 🍌",
            family: "Gemini 2.5 Flash Image"
        ),
    ]

    /// Canonical AI/ML id -> the name shown instead of that model's `info.name`. Twelve entries,
    /// five vendor collisions. `tools/stage3-catalog-gen/apply_presentation.py` parses this
    /// dictionary out of this file, so it is the single source: there is no second copy in Python.
    public static let displayNameOverrides: [String: String] = [
        // "Flux Dev" names both the text-to-image model and its image-to-image sibling.
        "flux/dev": "Flux Dev Text to Image",
        "flux/dev/image-to-image": "Flux Dev Image to Image",
        // "Flux Kontext Max" and "Flux Kontext Pro" each name both directions.
        "flux/kontext-max/text-to-image": "Flux Kontext Max Text to Image",
        "flux/kontext-max/image-to-image": "Flux Kontext Max Image to Image",
        "flux/kontext-pro/text-to-image": "Flux Kontext Pro Text to Image",
        "flux/kontext-pro/image-to-image": "Flux Kontext Pro Image to Image",
        // "Veo 3.1" names three different models; "Veo 3.1 Fast" names the same three again.
        "google/veo-3.1-t2v": "Veo 3.1 Text to Video",
        "google/veo-3.1-i2v": "Veo 3.1 Image to Video",
        "google/veo-3.1-first-last-image-to-video": "Veo 3.1 First-Last Frame",
        "google/veo-3.1-t2v-fast": "Veo 3.1 Text to Video Fast",
        "google/veo-3.1-i2v-fast": "Veo 3.1 Image to Video Fast",
        "google/veo-3.1-first-last-image-to-video-fast": "Veo 3.1 First-Last Frame Fast",
    ]
}
