// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Manifold",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ManifoldKit", targets: ["ManifoldKit"]),
        .executable(name: "manifold-cli", targets: ["ManifoldCLI"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ManifoldKit",
            dependencies: [],
            path: "Sources/ManifoldKit"
        ),
        .executableTarget(
            name: "ManifoldCLI",
            dependencies: ["ManifoldKit"],
            path: "Sources/ManifoldCLI"
        ),
        .testTarget(
            name: "ManifoldKitTests",
            dependencies: ["ManifoldKit"],
            path: "Tests/ManifoldKitTests"
        ),
    ]
)
