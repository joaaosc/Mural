// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "MuralKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "MuralKit", targets: ["MuralKit"]),
    ],
    targets: [
        .target(
            name: "MuralKit",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")],
        ),
        .testTarget(
            name: "MuralKitTests",
            dependencies: ["MuralKit"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")],
        ),
    ]
)
