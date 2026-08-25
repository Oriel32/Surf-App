// swift-tools-version: 6.0
import PackageDescription

// SurfCore is a LIBRARY, so it deliberately does NOT set
// `.defaultIsolation(MainActor.self)`. Per Apple's WWDC25 doctrine, libraries
// expose a nonisolated API and let the app target decide what to offload.
// The app target is the place for "Default Actor Isolation = MainActor".
let package = Package(
    name: "SurfCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SurfCore", targets: ["SurfCore"])
    ],
    targets: [
        .target(
            name: "SurfCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SurfCoreTests",
            dependencies: ["SurfCore"],
            resources: [.process("Fixtures")]
        ),
        // Live smoke test. Deliberately NOT part of the test suite: the unit
        // tests must stay hermetic and fixture-driven, while this one exists
        // precisely to hit the real endpoints and prove the decoders match
        // what the providers actually send.
        .executableTarget(name: "smoke", dependencies: ["SurfCore"])
    ]
)
