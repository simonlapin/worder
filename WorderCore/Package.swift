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
    targets: [
        .target(name: "WorderCore"),
        .testTarget(name: "WorderCoreTests", dependencies: ["WorderCore"]),
    ]
)
