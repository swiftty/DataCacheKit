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
    dependencies: [],
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
