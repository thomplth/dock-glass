// swift-tools-version: 6.2
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "DockGlass",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DockGlass", targets: ["DockGlass"]),
    ],
    targets: [
        .target(
            name: "DockGlass",
            path: "Sources/DockGlass"
        ),
        // Development tool that captures the native switcher and fits tuning tables. Not a product,
        // so apps depending on DockGlass never build it.
        .executableTarget(
            name: "glass-fit",
            dependencies: ["DockGlass"],
            path: "Tools/glass-fit",
            // A single-threaded script driven by the main run loop.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "DockGlassTests",
            dependencies: ["DockGlass"],
            path: "Tests/DockGlassTests"
        ),
    ]
)
