// Catalog rows — xAI / Grok, native provider (Stage 3, Task 14).
//
// These two ids are NOT registry keys. The registry's only Grok line
// (`reg(["x-ai/grok-imagine-image", "x-ai/grok-imagine-image-pro"])`, ModelRegistry.swift:1845)
// names the AI/ML-routed pair, which is a different pair of ids and a different provider. The ids
// below are the ones the Grok picker actually sends, and before this file existed they were an
// inline 2-tuple array in ConfigurationSection.swift with no catalog counterpart at all.
//
// `displayName` is the picker's own label, moved verbatim — em dash included.
//
// Grok's PARAMETERS are deliberately not here. `grokAspectRatio` and `grokResolution` are two
// @AppStorage strings (GenStationApp.swift:155-156) driving a hand-written picker pair
// (ConfigurationSection.swift:448-468); folding them into `ParamCatalog` is out of scope for
// Stage 3 (design § 8). See the discrepancy note at the foot of CatalogGrokTests.swift.

import Foundation

extension Catalog {

    /// Internal on purpose: the only reader is the canonical store in `Catalog.swift`. Nothing
    /// outside the package should enumerate one provider's rows — that is `selectable(task:)`
    /// plus a provider filter.
    static let grokRows: [CatalogModel] = [
        CatalogModel(
            id: "grok-imagine-image-2.0",
            aliases: [],
            provider: .grok,
            displayName: "Grok Imagine Image 2.0",
            family: "Grok Imagine",
            lifecycle: .current,
            // Image model: nil, and CatalogWallClockTests enforces it.
            typicalWallClock: nil,
            isRegistered: true,
            task: .image,
            isI2I: true,
            requiresInputImage: false,
            supportsMask: false,
            maxInputImages: 1,
            imageInputParam: "image",
            secondImageParam: nil,
            acceptsMultiImages: false,
            acceptsBase64: true,
            acceptsPublicURL: false,
            acceptsBinary: false,
            // One POST, image comes back in the response body — nothing to poll.
            generationEndpoint: GrokClient.imageGenerationsURL.absoluteString,
            pollingEndpoint: nil
        ),
        CatalogModel(
            id: "grok-imagine-image",
            aliases: [],
            provider: .grok,
            displayName: "Grok Imagine Image",
            family: "Grok Imagine",
            lifecycle: .current,
            // Image model: nil, and CatalogWallClockTests enforces it.
            typicalWallClock: nil,
            isRegistered: true,
            task: .image,
            // AppState.canAddImages returns false for .grok (GenStationApp.swift:2441-2442) and
            // maxImageSlots returns 0 (:2453-2454); the row says the same thing as data.
            isI2I: false,
            requiresInputImage: false,
            supportsMask: false,
            maxInputImages: 0,
            imageInputParam: "",
            secondImageParam: nil,
            acceptsMultiImages: false,
            acceptsBase64: false,
            acceptsPublicURL: false,
            acceptsBinary: false,
            // One POST, image comes back in the response body — nothing to poll.
            generationEndpoint: GrokClient.imageGenerationsURL.absoluteString,
            pollingEndpoint: nil
        ),
        CatalogModel(
            id: "grok-imagine-image-quality",
            aliases: [],
            provider: .grok,
            displayName: "Grok Imagine Image — Quality (2K)",
            family: "Grok Imagine",
            lifecycle: .current,
            typicalWallClock: nil,
            isRegistered: true,
            task: .image,
            isI2I: false,
            requiresInputImage: false,
            supportsMask: false,
            maxInputImages: 0,
            imageInputParam: "",
            secondImageParam: nil,
            acceptsMultiImages: false,
            acceptsBase64: false,
            acceptsPublicURL: false,
            acceptsBinary: false,
            generationEndpoint: GrokClient.imageGenerationsURL.absoluteString,
            pollingEndpoint: nil
        ),
    ]
}
