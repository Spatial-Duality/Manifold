// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Manifold",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "ManifoldKit", targets: ["ManifoldKit"]),
        .executable(name: "manifold-cli", targets: ["ManifoldCLI"]),
        .executable(name: "manifold-mcp", targets: ["ManifoldMCP"]),
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
            name: "ManifoldMCP",
            dependencies: ["ManifoldKit"],
            path: "Sources/ManifoldMCP"
        ),
        .testTarget(
            name: "ManifoldKitTests",
            dependencies: ["ManifoldKit", "ManifoldMCP"],
            path: "Tests/ManifoldKitTests"
        ),
    ]
)
