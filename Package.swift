// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tetra",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "tetra",
            path: "Sources",
            resources: [.process("Resources")]
        )
    ]
)
