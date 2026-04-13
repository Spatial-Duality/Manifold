// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Manifold",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "ManifoldKit", targets: ["ManifoldKit"]),
        .library(name: "ManifoldRuntime", targets: ["ManifoldRuntime"]),
        .library(name: "ManifoldXPC", targets: ["ManifoldXPC"]),
        .executable(name: "manifold-cli", targets: ["ManifoldCLI"]),
        .executable(name: "manifold-mcp", targets: ["ManifoldMCP"]),
        .executable(name: "ManifoldAgent", targets: ["ManifoldAgent"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ManifoldKit",
            dependencies: [],
            path: "Sources/ManifoldKit"
        ),
        .target(
            name: "ManifoldRuntime",
            dependencies: ["ManifoldKit"],
            path: "Sources/ManifoldRuntime"
        ),
        .target(
            name: "ManifoldXPC",
            dependencies: ["ManifoldKit", "ManifoldRuntime"],
            path: "Sources/ManifoldXPC"
        ),
        .executableTarget(
            name: "ManifoldCLI",
            dependencies: ["ManifoldKit", "ManifoldXPC"],
            path: "Sources/ManifoldCLI"
        ),
        .executableTarget(
            name: "ManifoldMCP",
            dependencies: ["ManifoldXPC"],
            path: "Sources/ManifoldMCP"
        ),
        .executableTarget(
            name: "ManifoldAgent",
            dependencies: ["ManifoldRuntime", "ManifoldXPC"],
            path: "Sources/ManifoldAgent"
        ),
        .testTarget(
            name: "ManifoldKitTests",
            dependencies: ["ManifoldKit", "ManifoldMCP", "ManifoldRuntime", "ManifoldXPC"],
            path: "Tests/ManifoldKitTests"
        ),
    ]
)
