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
        .executable(name: "ManifoldApp", targets: ["ManifoldApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
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
            dependencies: [
                "ManifoldKit",
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/ManifoldMCP"
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
