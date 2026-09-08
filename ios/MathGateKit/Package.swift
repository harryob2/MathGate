// swift-tools-version: 6.0
import PackageDescription

// Pure Foundation. No FamilyControls / ManagedSettings here on purpose: everything in this
// package must build and test on macOS, so `swift test` gives a fast loop with no simulator,
// mirroring the Android side's plain-JVM unit tests.
let package = Package(
    name: "MathGateKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MathGateKit", targets: ["MathGateKit"])
    ],
    targets: [
        .target(name: "MathGateKit"),
        .testTarget(name: "MathGateKitTests", dependencies: ["MathGateKit"]),
    ]
)
