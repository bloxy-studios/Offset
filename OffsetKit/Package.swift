// swift-tools-version: 6.3
// OffsetKit — pure logic package for Offset (models, engine, scheduling, news, AI, storage).
// Concurrency posture per docs/02-ARCHITECTURE.md §2: default MainActor isolation at the
// module level; model/engine types opt out explicitly with `nonisolated`.

import PackageDescription

let package = Package(
    name: "OffsetKit",
    platforms: [.iOS(.v26)],
    products: [
        .library(
            name: "OffsetKit",
            targets: ["OffsetKit"]
        ),
    ],
    targets: [
        .target(
            name: "OffsetKit",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "OffsetKitTests",
            dependencies: ["OffsetKit"],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
