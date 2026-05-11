// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BlackBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BlackBar", targets: ["BlackBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1")
    ],
    targets: [
        .executableTarget(
            name: "BlackBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "BlackBarTests",
            dependencies: ["BlackBar"]
        )
    ]
)
