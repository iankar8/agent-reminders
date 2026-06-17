// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentRemindersWeb",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Reuse the store + models from the sibling native app. No logic duplication.
        .package(name: "AgentReminders", path: "../macos")
    ],
    targets: [
        .executableTarget(
            name: "AgentRemindersWeb",
            dependencies: [
                .product(name: "AgentRemindersCore", package: "AgentReminders")
            ],
            resources: [.copy("Resources/panel.html")]   // bundled, loaded via loadFileURL
        ),
        .testTarget(
            name: "AgentRemindersWebTests",
            dependencies: ["AgentRemindersWeb"]
        )
    ]
)
