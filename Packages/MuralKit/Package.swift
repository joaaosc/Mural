// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "MuralKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "MuralKit", targets: ["MuralKit"])
    ],
    dependencies: [
        // Dependência remota usada pelos recursos de seleção e geração de texto.
        .package(url: "https://github.com/joaaosc/StretchText.git", from: "1.0.0")
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
