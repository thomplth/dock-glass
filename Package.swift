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
            dependencies: ["DockGlassShims"],
            path: "Sources/DockGlass"
        ),
        // Calls SwiftUI's internal window-active environment setter, which needs the `swiftself`
        // register; see FocusState.swift.
        .target(
            name: "DockGlassShims",
            path: "Sources/DockGlassShims"
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
        // Showcase used for README media and visual checks. Not a product.
        .executableTarget(
            name: "dockglass-demo",
            dependencies: ["DockGlass"],
            path: "Examples/dockglass-demo",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "DockGlassTests",
            dependencies: ["DockGlass"],
            path: "Tests/DockGlassTests"
        ),
    ]
)
