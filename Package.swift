// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Kick",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KickCore", targets: ["KickCore"]),
        .library(name: "KickSystem", targets: ["KickSystem"]),
        .executable(name: "Kick", targets: ["Kick"])
    ],
    targets: [
        .target(
            name: "KickCore",
            path: "Sources/KickCore"
        ),
        .target(
            name: "KickSystem",
            dependencies: ["KickCore"],
            path: "Sources/KickSystem",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("DiskArbitration"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "Kick",
            dependencies: ["KickCore", "KickSystem"],
            path: "Sources/Kick"
        ),
        .testTarget(
            name: "KickCoreTests",
            dependencies: ["KickCore"],
            path: "Tests/KickCoreTests"
        ),
        .testTarget(
            name: "KickSystemTests",
            dependencies: ["KickCore", "KickSystem"],
            path: "Tests/KickSystemTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
