import AppKit

/// UserDefaults-backed frame persistence. Same contract as SPEC_A §7:
/// only the SIZE is restored at init; the ORIGIN is always recomputed from the
/// live status-item anchor on each open, so the panel never strands off-screen.
struct PanelFrameStore {
    static let defaultSize = NSSize(width: 392, height: 560)   // matches mockup --w:392px
    static let minSize     = NSSize(width: 320, height: 300)
    static let maxSize     = NSSize(width: 560, height: 820)
    private let key = "WebPanelFrame"
    private let d = UserDefaults.standard

    func save(_ frame: NSRect) { d.set(NSStringFromRect(frame), forKey: key) }

    func restoredSize() -> NSSize {
        guard let s = d.string(forKey: key) else { return Self.defaultSize }
        let r = NSRectFromString(s)
        return r.size == .zero ? Self.defaultSize : r.size
    }

    /// Full saved frame if it still lands on a connected screen, else nil
    /// (caller re-anchors under the icon).
    func restoredFrameIfOnScreen() -> NSRect? {
        guard let s = d.string(forKey: key) else { return nil }
        let r = NSRectFromString(s)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(r) } ? r : nil
    }
}
