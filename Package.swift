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
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "BlackBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedFramework("AppKit"),
                .linkedFramework("Charts"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
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
