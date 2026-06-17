import AppKit

/// NSStatusItem with a due-count badge, anchor math, toggle, and a global
/// click-outside monitor. The badge count comes from a closure (the Bridge's
/// `dueCount()`), so this controller stays decoupled from the store.
final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: PanelWindow
    private let badge: () -> Int
    private var monitor: Any?

    init(panel: PanelWindow, badge: @escaping () -> Int) {
        self.panel = panel
        self.badge = badge
        if let b = item.button {
            b.target = self
            b.action = #selector(toggle)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshBadge()
    }

    func refreshBadge() {
        guard let b = item.button else { return }
        let count = badge()
        b.image = NSImage(
            systemSymbolName: count > 0 ? "checklist.unchecked" : "checklist",
            accessibilityDescription: "Agent Reminders")
        b.title = count > 0 ? " \(count)" : ""
        b.imagePosition = .imageLeading
    }

    @objc private func toggle() {
        panel.isVisible ? close() : open()
    }

    private func open() {
        guard let rect = anchorRect() else { return }
        panel.presentSpring(at: rect)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.close()
        }
    }

    private func close() {
        panel.dismissSpring()
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    /// Screen-space rect of the status button.
    private func anchorRect() -> NSRect? {
        guard let b = item.button, let w = b.window else { return nil }
        return w.convertToScreen(b.convert(b.bounds, to: nil))
    }
}
