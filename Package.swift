// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "VideoPrompt",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VPCore"),
        .testTarget(name: "VPCoreTests", dependencies: ["VPCore"], resources: [.copy("Golden")]),
    ],
    swiftLanguageModes: [.v6]
)
