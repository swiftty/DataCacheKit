// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DataCacheKit",
    platforms: [
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v2),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DataCacheKit",
            targets: ["DataCacheKit"]),
    ],
    dependencies: [
        // .package(url: "https://github.com/swiftty/swift-project-starter.git", from: "0.2.0"),
        // AUTO GENERATED ↓: swift-project-starter: deps
        .package(url: "https://github.com/swiftty/swift-format-plugin", from: "1.0.0")
        // AUTO GENERATED ↑: swift-project-starter: deps
    ],
    targets: [
        .target(
            name: "DataCacheKit",
            dependencies: ["LRUCache"]),
        .testTarget(
            name: "DataCacheKitTests",
            dependencies: ["DataCacheKit"]),

        .target(
            name: "LRUCache",
            dependencies: []),
        .testTarget(
            name: "LRUCacheTests",
            dependencies: ["LRUCache"]),
    ]
)

// AUTO GENERATED ↓: swift-project-starter: settings
for target in package.targets {
    if [.executable, .test, .regular].contains(target.type) {
        do {
            var swiftSettings = target.swiftSettings ?? []
            defer {
                target.swiftSettings = swiftSettings
            }
            swiftSettings += [
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("ImmutableWeakCaptures"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        }
        do {
            var plugins = target.plugins ?? []
            defer {
                target.plugins = plugins
            }
            plugins += [
                .plugin(name: "Lint", package: "swift-format-plugin")
            ]
        }
    }
}
// AUTO GENERATED ↑: swift-project-starter: settings
