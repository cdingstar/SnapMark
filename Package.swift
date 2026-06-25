// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SnapMark",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SnapMark", targets: ["SnapMark"])
    ],
    targets: [
        .executableTarget(
            name: "SnapMark",
            path: "Sources/SnapMark"
        )
    ]
)
