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
        .executable(name: "ManifoldApp", targets: ["ManifoldApp"]),
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
        .executableTarget(
            name: "ManifoldApp",
            dependencies: ["ManifoldKit"],
            path: "ManifoldApp/ManifoldApp"
        ),
        .testTarget(
            name: "ManifoldKitTests",
            dependencies: ["ManifoldKit"],
            path: "Tests/ManifoldKitTests"
        ),
    ]
)
