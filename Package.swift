// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LGTVCompanion",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LGTVCompanion", targets: ["LGTVCompanionApp"]),
        .executable(name: "LGTVCompanionDaemon", targets: ["LGTVCompanionDaemon"]),
        .library(name: "LGTVCompanionShared", targets: ["LGTVCompanionShared"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LGTVCompanionShared",
            dependencies: [],
            path: "Shared"
        ),
        .executableTarget(
            name: "LGTVCompanionApp",
            dependencies: ["LGTVCompanionShared"],
            path: "App",
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIcon.png")
            ]
        ),
        .executableTarget(
            name: "LGTVCompanionDaemon",
            dependencies: ["LGTVCompanionShared"],
            path: "Daemon",
            exclude: ["com.lgtvcompanion.daemon.plist"]
        )
    ]
)
