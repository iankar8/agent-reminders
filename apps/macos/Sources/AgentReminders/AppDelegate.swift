import AppKit
import SwiftUI

/// Owns app lifecycle and windowing. SwiftUI keeps the `App` shell (for
/// environment/`@StateObject` machinery) but hands all windowing to us.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = ReminderViewModel()
    private var panel: MenuBarPanel!
    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)                 // menu-bar-only, no Dock icon
        panel = MenuBarPanel(model: model)
        statusBar = StatusBarController(panel: panel, model: model)
    }
}
