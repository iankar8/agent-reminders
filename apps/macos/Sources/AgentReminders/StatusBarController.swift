import AppKit
import Combine

/// Owns the `NSStatusItem`: icon + live due-count badge, toggle open/close,
/// anchor math, and the global click-outside monitor.
@MainActor
final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: MenuBarPanel
    private let model: ReminderViewModel
    private var monitor: Any?
    private var cancellable: AnyCancellable?

    init(panel: MenuBarPanel, model: ReminderViewModel) {
        self.panel = panel
        self.model = model

        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshBadge()

        // Live badge: any model change recomputes the due count.
        cancellable = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refreshBadge() }
        }
    }

    private func refreshBadge() {
        guard let button = item.button else { return }
        let due = model.dueCount
        button.image = NSImage(
            systemSymbolName: due > 0 ? "checklist.unchecked" : "checklist",
            accessibilityDescription: "Agent Reminders"
        )
        button.title = due > 0 ? " \(due)" : ""
        button.imagePosition = .imageLeading
    }

    @objc private func toggle() {
        panel.isVisible ? close() : open()
    }

    private func open() {
        guard let rect = anchorRect() else { return }
        panel.presentSpring(at: rect)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            DispatchQueue.main.async { self?.close() }
        }
    }

    private func close() {
        panel.dismissSpring()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }

    /// Screen-space rect of the status-item button.
    private func anchorRect() -> NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
