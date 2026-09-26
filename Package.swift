// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Prompts, the model client and the Markdown parser. No UI, so it can be tested.
        .target(
            name: "PromptBarKit",
            path: "Sources/PromptBarKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Menu bar app: status item, result panel, settings.
        .executableTarget(
            name: "PromptBar",
            dependencies: ["PromptBarKit"],
            path: "Sources/PromptBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PromptBarKitTests",
            dependencies: ["PromptBarKit"],
            path: "Tests/PromptBarKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
