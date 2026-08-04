// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CodexOrb",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexOrbCore", targets: ["CodexOrbCore"]),
        .executable(name: "CodexOrb", targets: ["CodexOrb"])
    ],
    targets: [
        .target(name: "CodexOrbCore"),
        .executableTarget(
            name: "CodexOrb",
            dependencies: ["CodexOrbCore"]
        ),
        .testTarget(
            name: "CodexOrbCoreTests",
            dependencies: ["CodexOrbCore"]
        ),
        .testTarget(
            name: "CodexOrbTests",
            dependencies: ["CodexOrb", "CodexOrbCore"]
        )
    ]
)
