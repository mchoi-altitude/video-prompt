// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "VideoPrompt",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "VPCore"),
        .target(name: "VPMedia", dependencies: ["VPCore"]),
        .target(name: "VPProcess", dependencies: ["VPCore", "VPMedia"]),
        .target(name: "VPMCP", dependencies: ["VPCore"]),
        .executableTarget(name: "vp-mcp", dependencies: ["VPMCP"]),
        .executableTarget(name: "vp-process", dependencies: ["VPProcess"]),
        .target(name: "VPApp", dependencies: ["VPCore", "VPProcess"]),
        .executableTarget(name: "VideoPrompt", dependencies: ["VPApp", "VPCore", "VPProcess"]),
        .target(name: "VPTestSupport", dependencies: ["VPCore", "VPMedia"], path: "Tests/Support"),
        .testTarget(name: "VPCoreTests", dependencies: ["VPCore"], resources: [.copy("Golden")]),
        .testTarget(name: "VPProcessTests", dependencies: ["VPProcess", "VPTestSupport"]),
        .testTarget(name: "VPMCPTests", dependencies: ["VPMCP", "VPTestSupport"]),
        .testTarget(name: "VPAppTests", dependencies: ["VPApp", "VPTestSupport", "VPProcess"]),
        .testTarget(name: "VPMediaTests", dependencies: ["VPMedia", "VPTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
