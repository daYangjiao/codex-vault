// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexVault",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexVaultCore", targets: ["CodexVaultCore"]),
        .executable(name: "CodexVault", targets: ["CodexVaultApp"]),
        .executable(name: "CodexVaultSmokeTests", targets: ["CodexVaultSmokeTests"])
    ],
    targets: [
        .target(
            name: "CodexVaultCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "CodexVaultApp",
            dependencies: ["CodexVaultCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "CodexVaultSmokeTests",
            dependencies: ["CodexVaultCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
