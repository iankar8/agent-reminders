import AppKit

/// Persists the panel frame in `UserDefaults` as a string (`NSStringFromRect`).
/// Only the *size* is restored at launch — the origin is always recomputed from
/// the live status-item anchor so the panel never strands off-screen.
struct PanelFrameStore {
    static let defaultSize = NSSize(width: 392, height: 560)
    static let minSize     = NSSize(width: 320, height: 300)
    static let maxSize     = NSSize(width: 560, height: 820)

    private let key = "MenuBarPanelFrame"
    private let defaults = UserDefaults.standard

    func save(_ frame: NSRect) {
        defaults.set(NSStringFromRect(frame), forKey: key)
    }

    /// Saved size clamped to the allowed range, or the default if none/invalid.
    func restoredSize() -> NSSize {
        guard let string = defaults.string(forKey: key) else { return Self.defaultSize }
        let rect = NSRectFromString(string)
        guard rect.width > 0, rect.height > 0 else { return Self.defaultSize }
        return NSSize(
            width: rect.width.clamped(Self.minSize.width ... Self.maxSize.width),
            height: rect.height.clamped(Self.minSize.height ... Self.maxSize.height)
        )
    }

    /// Full saved frame, but only if it still lands on a connected screen.
    /// Returns nil when the sizing display is gone so the caller re-anchors.
    func restoredFrameIfOnScreen() -> NSRect? {
        guard let string = defaults.string(forKey: key) else { return nil }
        let rect = NSRectFromString(string)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return NSScreen.screens.contains { $0.visibleFrame.intersects(rect) } ? rect : nil
    }
}
