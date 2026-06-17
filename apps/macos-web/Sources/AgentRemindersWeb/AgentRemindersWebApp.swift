import SwiftUI

/// SwiftUI shell so the `@NSApplicationDelegateAdaptor` machinery is available.
/// No normal windows are created — the panel is AppKit-owned (see AppDelegate).
@main
struct AgentRemindersWebApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
