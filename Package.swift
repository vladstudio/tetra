// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tetra",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Tetra",
            path: "Sources",
            resources: [.process("Resources")]
        )
    ]
)
