// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NotchApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotchApp", targets: ["NotchApp"])
    ],
    targets: [
        .executableTarget(
            name: "NotchApp",
            path: "Sources/NotchApp"
        )
    ]
)
