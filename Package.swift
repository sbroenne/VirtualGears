// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VirtualShift",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "VirtualShiftCore",
            targets: ["VirtualShiftCore"]
        ),
    ],
    targets: [
        .target(
            name: "VirtualShiftCore"
        ),
        .testTarget(
            name: "VirtualShiftCoreTests",
            dependencies: ["VirtualShiftCore"]
        ),
    ]
)

