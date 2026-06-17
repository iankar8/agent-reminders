import AppKit
import SwiftUI

/// Lifecycle owner. Builds the bridge (owns the store + 30s poll), the WKWebView
/// controller, the panel that hosts it, and the status-bar controller. Init order
/// matters: bridge → webCtl → wire bridge.web → panel → status bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bridge: Bridge!
    private var webCtl: WebPanelController!
    private var panel: PanelWindow!
    private var status: StatusBarController!

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)            // menu-bar-only, no Dock icon

        bridge = Bridge()                                 // owns the store + poll
        webCtl = WebPanelController(bridge: bridge)
        bridge.web = webCtl
        panel = PanelWindow(webView: webCtl.webView)
        bridge.panel = panel                              // for the CSS resize handle
        status = StatusBarController(panel: panel, badge: { [weak bridge] in bridge?.dueCount() ?? 0 })

        // Refresh the menu-bar badge on every store push (and the 30s poll already
        // calls pushState, so the badge stays live without reopening the panel).
        bridge.onStateChange = { [weak status] in status?.refreshBadge() }
    }
}
