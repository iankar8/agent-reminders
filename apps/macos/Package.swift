// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentReminders",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Exported so the sibling apps/macos-web package can depend on Core
        // via a local path dependency. Additive — does not affect the app target.
        .library(name: "AgentRemindersCore", targets: ["AgentRemindersCore"])
    ],
    targets: [
        // Pure model + store logic. No UI — fully unit-testable.
        .target(
            name: "AgentRemindersCore"
        ),
        // The SwiftUI MenuBarExtra app.
        .executableTarget(
            name: "AgentReminders",
            dependencies: ["AgentRemindersCore"]
        ),
        .testTarget(
            name: "AgentRemindersCoreTests",
            dependencies: ["AgentRemindersCore"]
        )
    ]
)
