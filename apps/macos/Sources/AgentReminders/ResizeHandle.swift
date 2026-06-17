import SwiftUI
import AppKit

/// A bottom drag handle that resizes the host `NSPanel` live and persists the
/// final frame. The panel itself is `.resizable`, so the native window edges
/// also work — this is the in-content Arc-grade affordance.
struct ResizeHandle: View {
    /// Weak ref to the host panel for live frame mutation. Provided by AppDelegate.
    weak var panel: NSWindow?
    @State private var startHeight: CGFloat = 0
    @State private var active = false

    var body: some View {
        ResizeCursorView()                       // keeps `.resizeUpDown` during the drag
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .overlay(grip)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard let panel else { return }
                        if startHeight == 0 {
                            startHeight = panel.frame.height
                            active = true
                        }
                        // Dragging DOWN grows the panel. NSPanel origin is
                        // bottom-left, so growing height drops the origin to keep
                        // the top edge (under the status item) pinned.
                        let newHeight = (startHeight + value.translation.height)
                            .clamped(PanelFrameStore.minSize.height ... PanelFrameStore.maxSize.height)
                        var frame = panel.frame
                        let delta = newHeight - frame.height
                        frame.origin.y -= delta
                        frame.size.height = newHeight
                        panel.setFrame(frame, display: true)        // live, no animation
                    }
                    .onEnded { _ in
                        startHeight = 0
                        active = false
                        if let frame = panel?.frame { PanelFrameStore().save(frame) }
                    }
            )
    }

    private var grip: some View {
        Capsule()
            .fill(.secondary.opacity(active ? 0.55 : 0.30))
            .frame(width: 30, height: 4)
            .animation(Motion.hover, value: active)
    }
}

/// An invisible `NSView` whose only job is to pin the resize cursor.
/// SwiftUI's `DragGesture` resets `NSCursor` mid-drag, so a tracking-area /
/// `resetCursorRects()` shim is required for a reliable resize cursor.
struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> Tracking { Tracking() }
    func updateNSView(_ view: Tracking, context: Context) {}

    final class Tracking: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
                    owner: self
                )
            )
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.resizeUpDown.set()
        }
    }
}
