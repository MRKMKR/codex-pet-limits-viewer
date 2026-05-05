// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "codex-pet-limits-viewer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "codex-pet-limits-viewer", targets: ["CodexPetLimitsViewer"])
    ],
    targets: [
        .target(
            name: "CodexPetLimitsViewerCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "CodexPetLimitsViewer",
            dependencies: ["CodexPetLimitsViewerCore"]
        ),
        .testTarget(
            name: "CodexPetLimitsViewerCoreTests",
            dependencies: ["CodexPetLimitsViewerCore"]
        )
    ]
)
