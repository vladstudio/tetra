// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tetra",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../app-kit"),
    ],
    targets: [
        .executableTarget(
            name: "Tetra",
            dependencies: [.product(name: "MacAppKit", package: "app-kit")],
            path: "Sources",
            resources: [.process("Resources")]
        )
    ]
)
