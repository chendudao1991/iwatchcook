// swift-tools-version: 5.9
import PackageDescription

// The shared wire protocol and segment planner are intentionally independent of Apple SDKs.
let package = Package(
    name: "WristNoteCore",
    platforms: [.iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "WristNoteCore", targets: ["WristNoteCore"])],
    targets: [
        .target(name: "WristNoteCore", path: "Shared"),
        .testTarget(name: "WristNoteCoreTests", dependencies: ["WristNoteCore"], path: "Tests")
    ]
)
