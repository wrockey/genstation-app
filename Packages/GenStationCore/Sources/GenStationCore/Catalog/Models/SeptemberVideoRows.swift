import Foundation

extension AIMLRegisteredModels {
    static let septemberVideoRows: [CatalogModel] = [
        CatalogModel(id: "alibaba/wan-3-0-video", aliases: [], provider: .aimlapi,
            displayName: "Wan 3.0 Video", family: "Wan 3.0", lifecycle: .current,
            typicalWallClock: nil, isRegistered: true,
            task: .video, isI2I: true, requiresInputImage: false, supportsMask: false,
            maxInputImages: 2, imageInputParam: "image_url", secondImageParam: "last_image_url",
            acceptsMultiImages: false, acceptsBase64: false, acceptsPublicURL: true,
            acceptsBinary: false, generationEndpoint: AIMLEndpoints.videoGeneration,
            pollingEndpoint: AIMLEndpoints.videoGenerationPoll),
        CatalogModel(id: "bytedance/seedance-2-5", aliases: [], provider: .aimlapi,
            displayName: "Seedance 2.5", family: "Seedance 2.5", lifecycle: .current,
            typicalWallClock: nil, isRegistered: true,
            task: .video, isI2I: true, requiresInputImage: false, supportsMask: false,
            maxInputImages: 2, imageInputParam: "image_url", secondImageParam: "last_image_url",
            acceptsMultiImages: false, acceptsBase64: true, acceptsPublicURL: true,
            acceptsBinary: false, generationEndpoint: AIMLEndpoints.videoGeneration,
            pollingEndpoint: AIMLEndpoints.videoGenerationPoll),
        CatalogModel(id: "minimax/h3-max", aliases: [], provider: .aimlapi,
            displayName: "MiniMax H3 Max", family: "MiniMax H3", lifecycle: .current,
            typicalWallClock: nil, isRegistered: true,
            task: .video, isI2I: true, requiresInputImage: false, supportsMask: false,
            maxInputImages: 2, imageInputParam: "image_url", secondImageParam: "last_image_url",
            acceptsMultiImages: false, acceptsBase64: true, acceptsPublicURL: true,
            acceptsBinary: false, generationEndpoint: AIMLEndpoints.videoGeneration,
            pollingEndpoint: AIMLEndpoints.videoGenerationPoll),
    ]
}
