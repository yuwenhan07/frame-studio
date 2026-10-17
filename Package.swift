// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FrameStudio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FrameStudio", targets: ["FrameApp"]),
        .executable(name: "FrameChecks", targets: ["FrameChecks"])
    ],
    targets: [
        .target(name: "FrameCore"),
        .executableTarget(name: "FrameApp", dependencies: ["FrameCore"]),
        .executableTarget(name: "FrameChecks", dependencies: ["FrameCore"])
    ]
)
