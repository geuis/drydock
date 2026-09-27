// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Drydock",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Drydock",
            path: "Sources/Drydock",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DrydockTests",
            dependencies: ["Drydock"],
            path: "Tests/DrydockTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
