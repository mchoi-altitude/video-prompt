// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "VideoPrompt",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VPCore"),
        .target(name: "VPMedia", dependencies: ["VPCore"]),
        .target(name: "VPTestSupport", dependencies: ["VPCore", "VPMedia"], path: "Tests/Support"),
        .testTarget(name: "VPCoreTests", dependencies: ["VPCore"], resources: [.copy("Golden")]),
        .testTarget(name: "VPMediaTests", dependencies: ["VPMedia", "VPTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
