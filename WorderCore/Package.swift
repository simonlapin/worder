// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorderCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v14),
    ],
    products: [
        .library(name: "WorderCore", targets: ["WorderCore"]),
    ],
    dependencies: [
        // FSRS-6 exists only on main; the latest tag (v5.0.0) is still FSRS-5.
        .package(
            url: "https://github.com/open-spaced-repetition/swift-fsrs.git",
            revision: "4fbaf20184d62f82a9f44f343337c61a2c5483e9"
        ),
    ],
    targets: [
        .target(
            name: "WorderCore",
            dependencies: [.product(name: "FSRS", package: "swift-fsrs")]
        ),
        .testTarget(name: "WorderCoreTests", dependencies: ["WorderCore"]),
    ]
)
