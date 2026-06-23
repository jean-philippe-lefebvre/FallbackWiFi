// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FallbackWiFi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FallbackWiFi",
            path: "FallbackWiFi"
        ),
        .testTarget(
            name: "FallbackWiFiTests",
            dependencies: ["FallbackWiFi"],
            path: "FallbackWiFiTests"
        ),
    ]
)
