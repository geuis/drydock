// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EVNPilotEditor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "EVNPilotEditor",
            path: "Sources/EVNPilotEditor",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "EVNPilotEditorTests",
            dependencies: ["EVNPilotEditor"],
            path: "Tests/EVNPilotEditorTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
