// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenTimeSharing",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ScreenTimeSharingCore",
            targets: ["ScreenTimeSharingCore"]
        )
    ],
    targets: [
        .target(
            name: "ScreenTimeSharingCore"
        ),
        .testTarget(
            name: "ScreenTimeSharingCoreTests",
            dependencies: ["ScreenTimeSharingCore"]
        )
    ]
)
