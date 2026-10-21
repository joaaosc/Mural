// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "MuralKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "MuralKit", targets: ["MuralKit"])
    ],
    dependencies: [
        // Pacote irmão, desenvolvido junto: ~/Projects/Workbench/StretchText.
        .package(path: "../../../Workbench/StretchText")
    ],
    targets: [
        .target(
            name: "MuralKit",
            dependencies: [
                .product(name: "StretchText", package: "StretchText"),
                .product(name: "StretchTextGeneration", package: "StretchText"),
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")],
        ),
        .testTarget(
            name: "MuralKitTests",
            dependencies: ["MuralKit"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")],
        ),
    ]
)
