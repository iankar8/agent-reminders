import AppKit
import SwiftUI

/// Borderless, non-activating, resizable `NSPanel` that hosts the SwiftUI
/// `MenuPanelView` inside an `NSVisualEffectView`. We own open/close motion
/// (alpha spring) and frame persistence.
final class MenuBarPanel: NSPanel {
    private let frameStore = PanelFrameStore()
    private let model: ReminderViewModel
    private var hosting: NSHostingView<AnyView>!

    init(model: ReminderViewModel) {
        self.model = model
        let size = frameStore.restoredSize()                  // saved size, or default
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar                                    // above windows, below menu bar
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false                   // we own resize; don't drag-move
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none                             // we drive alpha ourselves
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        minSize = PanelFrameStore.minSize
        maxSize = PanelFrameStore.maxSize

        // Vibrancy behind the SwiftUI content.
        let vfx = NSVisualEffectView()
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 14
        vfx.layer?.masksToBounds = true

        // The ResizeHandle needs a weak ref to this panel; capture it after super.init.
        let panelRef = WeakPanelBox()
        let root = AnyView(
            MenuPanelView(panelBox: panelRef)
                .environmentObject(model)
                .frame(minWidth: PanelFrameStore.minSize.width)
        )
        hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: vfx.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
        ])
        contentView = vfx
        panelRef.panel = self                                 // now safe to reference self

        observeFramePersistence()
    }

    // Borderless windows can't become key by default; the composer TextField needs it.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Frame persistence

    private func observeFramePersistence() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: self, queue: .main) {
            [weak self] _ in
            guard let self else { return }
            self.frameStore.save(self.frame)
        }
        nc.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) {
            [weak self] _ in
            guard let self else { return }
            self.frameStore.save(self.frame)
        }
    }

    // MARK: - Spring open / close (window level)

    /// Present under the status-item anchor: snap the frame (never animate origin),
    /// then spring the alpha up. SwiftUI content runs its own staggered entrance.
    func presentSpring(at anchor: NSRect) {
        let target = Self.frame(for: self, under: anchor)
        alphaValue = 0
        setFrame(target, display: false)                      // SNAP position
        model.isPanelVisible = false                          // reset so rows re-stagger
        makeKeyAndOrderFront(nil)
        model.isPanelVisible = true

        if Motion.reduceMotion {
            alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            ctx.allowsImplicitAnimation = true
            animator().alphaValue = 1
        }
    }

    /// Fade out, then order out and reset alpha for the next open.
    func dismissSpring() {
        model.isPanelVisible = false
        if Motion.reduceMotion {
            orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        }
    }

    // MARK: - Placement

    /// Centered under the status-item anchor with a 6pt gap, clamped to the
    /// owning screen's visibleFrame so it never runs off the edge.
    static func frame(for panel: NSPanel, under anchor: NSRect) -> NSRect {
        let w = panel.frame.width
        let h = panel.frame.height
        var x = anchor.midX - w / 2
        let y = anchor.minY - h - 6
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            x = x.clamped((v.minX + 8) ... (v.maxX - w - 8))
        }
        return NSRect(x: x, y: y, width: w, height: h)
    }
}

/// Lets the SwiftUI tree hold a weak reference to the AppKit panel without a
/// retain cycle, since the panel owns the hosting view that owns this box.
final class WeakPanelBox {
    weak var panel: NSWindow?
}
