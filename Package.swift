// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tetra",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../mac-app-kit"),
    ],
    targets: [
        .executableTarget(
            name: "Tetra",
            dependencies: [.product(name: "MacAppKit", package: "mac-app-kit")],
            path: "Sources",
            resources: [.process("Resources")]
        )
    ]
)
