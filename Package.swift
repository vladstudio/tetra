// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tetra",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "tetra",
            path: "Sources",
            resources: [.process("Resources")]
        )
    ]
)
