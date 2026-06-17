import AppKit
import WebKit

/// Borderless, resizable, non-activating panel that hosts a WKWebView inside an
/// NSVisualEffectView for real vibrancy. The three key-window overrides are
/// REQUIRED — without all of them, HTML <input> elements ignore keystrokes.
final class PanelWindow: NSPanel {
    static let defaultSize = PanelFrameStore.defaultSize
    static let minSize     = PanelFrameStore.minSize
    static let maxSize     = PanelFrameStore.maxSize
    private let frameStore = PanelFrameStore()

    init(webView: WKWebView) {
        let size = frameStore.restoredSize()
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        minSize = Self.minSize
        maxSize = Self.maxSize

        let vfx = NSVisualEffectView()
        vfx.material = .popover                 // vibrancy shows through transparent web bg
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 14
        vfx.layer?.masksToBounds = true

        webView.frame = vfx.bounds
        webView.autoresizingMask = [.width, .height]
        vfx.addSubview(webView)
        contentView = vfx

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: self, queue: .main) {
            [weak self] _ in guard let self else { return }
            self.frameStore.save(self.frame)
        }
    }

    // REQUIRED — all three or text inputs in the WKWebView stay dead.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - Placement

    /// Centered under the status-item anchor, 6pt gap, clamped to visibleFrame.
    static func frame(for panel: NSPanel, under anchor: NSRect) -> NSRect {
        let w = panel.frame.width, h = panel.frame.height
        var x = anchor.midX - w / 2
        let y = anchor.minY - h - 6
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            x = max(v.minX + 8, min(x, v.maxX - w - 8))
        }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Spring open / close (window level) — copied from SPEC_A §5

    func presentSpring(at anchor: NSRect) {
        let target = Self.frame(for: self, under: anchor)
        alphaValue = 0
        setFrame(target, display: false)          // SNAP position — never animate origin
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            ctx.allowsImplicitAnimation = true
            animator().alphaValue = 1
        }
    }

    func dismissSpring() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1                   // reset for next open
        }
    }

    /// Grow/shrink height live from a CSS resize-handle drag (origin drops as it grows).
    func resize(byHeight dh: CGFloat) {
        var f = frame
        let newH = min(max(f.height + dh, Self.minSize.height), Self.maxSize.height)
        let applied = newH - f.height
        f.origin.y -= applied
        f.size.height = newH
        setFrame(f, display: true)                 // LIVE, no animation
        frameStore.save(f)
    }
}
