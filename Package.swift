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
        .executable(
            name: "click-trace",
            targets: ["ClickTrace"]
        ),
        .executable(
            name: "kickr-probe",
            targets: ["KickrProbe"]
        ),
    ],
    targets: [
        .target(
            name: "VirtualShiftCore"
        ),
        // A macOS command-line tool that prints what a Zwift Click really
        // sends. Kept out of the app: it exists to answer questions about the
        // hardware, not to ship.
        .executableTarget(
            name: "ClickTrace",
            dependencies: ["VirtualShiftCore"],
            path: "Tools/ClickTrace",
            exclude: ["Info.plist", "run.sh"],
            // macOS refuses Bluetooth to a program that does not say why it
            // wants it, and a command-line tool has no bundle to say it in, so
            // the description is written straight into the binary.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Tools/ClickTrace/Info.plist",
                ])
            ]
        ),
        // A macOS command-line tool that measures how a real KICKR responds,
        // so the app's timing rules can be checked rather than assumed. Kept
        // out of the app for the same reason as the Click tracer.
        .executableTarget(
            name: "KickrProbe",
            dependencies: ["VirtualShiftCore"],
            path: "Tools/KickrProbe",
            exclude: ["Info.plist", "run.sh"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Tools/KickrProbe/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "VirtualShiftCoreTests",
            dependencies: ["VirtualShiftCore"]
        ),
    ]
)

