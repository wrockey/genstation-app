// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GenStationCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "GenStationCore", targets: ["GenStationCore"]),
    ],
    targets: [
        .target(name: "GenStationCore"),
        .testTarget(
            name: "GenStationCoreTests",
            dependencies: ["GenStationCore"],
            // `Fixtures/` holds captured wire responses and schemas that tests read off disk through
            // a `#filePath`-relative URL, the same way the source-scanning tests read app sources.
            // They are not bundle resources, so they are excluded from the build graph rather than
            // processed — without this, SwiftPM warns on every build about unhandled files.
            exclude: ["Fixtures"]
        ),
    ]
)
