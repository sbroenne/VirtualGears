// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VirtualGears",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "VirtualGearsCore",
            targets: ["VirtualGearsCore"]
        ),
        .executable(
            name: "click-trace",
            targets: ["ClickTrace"]
        ),
        .executable(
            name: "kickr-probe",
            targets: ["KickrProbe"]
        ),
        .executable(
            name: "name-scan",
            targets: ["NameScan"]
        ),
        .executable(
            name: "ride-sim",
            targets: ["RideSim"]
        ),
    ],
    targets: [
        .target(
            name: "VirtualGearsCore"
        ),
        .target(
            name: "ToolSupport"
        ),
        // A macOS command-line tool that prints what a Zwift Click really
        // sends. Kept out of the app: it exists to answer questions about the
        // hardware, not to ship.
        .executableTarget(
            name: "ClickTrace",
            dependencies: ["VirtualGearsCore", "ToolSupport"],
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
            dependencies: ["VirtualGearsCore", "ToolSupport"],
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
        // A macOS command-line tool that reads the name a fitness machine
        // broadcasts, so what a riding app displays can be checked rather than
        // guessed at.
        .executableTarget(
            name: "NameScan",
            dependencies: ["VirtualGearsCore", "ToolSupport"],
            path: "Tools/NameScan",
            exclude: ["Info.plist", "run.sh"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Tools/NameScan/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "VirtualGearsCoreTests",
            dependencies: ["VirtualGearsCore"]
        ),
        // A macOS command-line tool that connects to the app on the phone the
        // way a riding app on a PC does, so the far side of CoreBluetooth can
        // be checked on demand instead of only by riding.
        .executableTarget(
            name: "RideSim",
            dependencies: ["VirtualGearsCore", "ToolSupport"],
            path: "Tools/RideSim",
            exclude: ["Info.plist", "run.sh"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Tools/RideSim/Info.plist",
                ])
            ]
        ),
    ]
)
