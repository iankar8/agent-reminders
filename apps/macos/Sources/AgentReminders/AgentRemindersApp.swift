import SwiftUI

/// SwiftUI shell only — all windowing lives in `AppDelegate`. The panel is an
/// AppKit-owned `NSPanel`, so we expose no normal scene.
@main
struct AgentRemindersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
