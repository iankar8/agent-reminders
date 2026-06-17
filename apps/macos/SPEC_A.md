# SPEC A — Prototype A: Pure native SwiftUI / AppKit menu-bar panel

**Goal:** Replace the `MenuBarExtra(.window)` scene with an `AppDelegate` + `NSStatusItem` + a custom **borderless, resizable, non-activating `NSPanel`** that hosts `NSHostingView(MenuPanelView)`. Add drag-to-resize with size persisted in `UserDefaults`, spring open/close at the window level, and Arc/Comet-grade list/hover/gesture motion inside SwiftUI. Acceptance gate: `MOTION_RUBRIC.md`, every dimension ≥ 9.

**Scope:** All changes live in `apps/macos`. `AgentRemindersCore` (store/models) is **unchanged** — it already exposes everything the UI needs (`ReminderStore`, `AgentReminder`, mutations). `ReminderViewModel`, `NotificationManager`, and the bulk of `MenuPanelView` are reused. This is a *windowing rewrite*, not a logic rewrite.

---

## 0. Why the change

`MenuBarExtra(.window)` gives a fixed-width, non-resizable popover with no control over open/close motion, no vibrancy behind it, and no resize handle. To hit the rubric we need a real `NSPanel` we own. SwiftUI content stays; only the host changes.

---

## 1. Files to ADD

All under `apps/macos/Sources/AgentReminders/`:

| File | Responsibility |
|---|---|
| `AppDelegate.swift` | `NSApplicationDelegate`. Owns lifecycle, builds the `ReminderViewModel`, `MenuBarPanel`, `StatusBarController`, `PanelFrameStore`. Sets `NSApp.setActivationPolicy(.accessory)`. |
| `MenuBarPanel.swift` | `NSPanel` subclass: borderless, `.nonactivatingPanel`, floating, vibrancy content, hosts `NSHostingView`. Spring open/close. Frame persistence observers. |
| `StatusBarController.swift` | `NSStatusItem` + button (icon + due-count badge), toggle/open/close, anchor math, global click-outside monitor, observes `model.dueCount` to update the badge. |
| `PanelFrameStore.swift` | Tiny `UserDefaults` wrapper: save/restore `NSRect` (via `NSStringFromRect`), on-screen validation, default size, min/max. |
| `ResizeHandle.swift` | SwiftUI bottom/corner drag handle + `ResizeCursorView` (`NSViewRepresentable` cursor-rect shim) + `.cursor()` modifier. Mutates a bound height; persists on end. |
| `Motion.swift` | Central animation tokens (the §0 table in `MOTION_RUBRIC.md`) as `Animation` statics, plus `StaggeredAppear` view modifier and a `reduceMotion` helper. |

## 2. Files to CHANGE

| File | Change |
|---|---|
| `AgentRemindersApp.swift` | Replace the `App`/`MenuBarExtra` scene with `@main` `NSApplicationMain`-style `AppDelegate` bridging, **or** keep an `App` shell whose `body` is `Settings {}` and attach `@NSApplicationDelegateAdaptor(AppDelegate.self)`. (See §3 — adaptor route is less disruptive.) Remove `.menuBarExtraStyle(.window)` and the `MenuBarExtra` label/badge logic (moves to `StatusBarController`). |
| `MenuPanelView.swift` | (a) Wrap the list section changes in `Motion` springs; (b) convert the manual `.onHover` row background to use `Motion.hover` + lift + sheen; (c) add optimistic insert/remove `.transition` on `ReminderRow`; (d) accept a `@Binding var panelHeight` (or read an `ObservableObject` size model) and add `ResizeHandle` at the bottom; (e) replace `.frame(maxHeight: 360)` on the list with a height derived from panel size so the list grows on resize; (f) add `.contentTransition(.numericText())` to metric/section counts. |
| `ReminderViewModel.swift` | Add `@Published var size: CGSize` (or expose nothing and let the panel own size). Optional: ensure mutations animate by wrapping `reload()`'s `items` assignment in `withAnimation(Motion.listChange)` **only on the main actor** so SwiftUI diffs animate. |
| `Package.swift` | No new dependencies required for pure-native. (Optional: add `MacPaw/CocoaSprings` SPM only if you want spring-physics window *position* follow — not needed for v1.) |
| `Info.plist` / SwiftPM resources | Set `LSUIElement = YES` (menu-bar-only, no Dock icon). Since this is a SwiftPM executable, set activation policy in code (`NSApp.setActivationPolicy(.accessory)`) rather than relying on a generated plist. |

---

## 3. App entry point

Keep the SwiftUI `App` shell so SwiftUI's environment/`@StateObject` machinery stays available, but hand windowing to an `AppDelegate` via the adaptor. This avoids a full `NSApplicationMain` rewrite.

```swift
// AgentRemindersApp.swift
import SwiftUI

@main
struct AgentRemindersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }   // no normal windows; panel is AppKit-owned
    }
}
```

```swift
// AppDelegate.swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = ReminderViewModel()
    private var panel: MenuBarPanel!
    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)            // menu-bar-only
        panel = MenuBarPanel(model: model)
        statusBar = StatusBarController(panel: panel, model: model)
    }
}
```

**Key APIs:** `@NSApplicationDelegateAdaptor`, `NSApp.setActivationPolicy(.accessory)`.

---

## 4. `MenuBarPanel` (the NSPanel)

```swift
final class MenuBarPanel: NSPanel {
    private let frameStore = PanelFrameStore()
    private var hosting: NSHostingView<AnyView>!

    init(model: ReminderViewModel) {
        let size = frameStore.restoredSize()           // default 392x560 or saved
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView, .resizable],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .statusBar                              // above windows, below menu bar
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false             // we own resize; don't drag-move
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none                       // we drive alpha ourselves
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        minSize = PanelFrameStore.minSize
        maxSize = PanelFrameStore.maxSize

        // Vibrancy behind SwiftUI
        let vfx = NSVisualEffectView()
        vfx.material = .popover                          // or .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 14
        vfx.layer?.masksToBounds = true

        let root = AnyView(
            MenuPanelView()
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

        observeFramePersistence()
    }

    override var canBecomeKey: Bool { true }            // composer text field needs key
    override var canBecomeMain: Bool { false }

    private func observeFramePersistence() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: self, queue: .main) {
            [weak self] _ in guard let self else { return }
            self.frameStore.save(self.frame)
        }
        nc.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) {
            [weak self] _ in guard let self else { return }
            self.frameStore.save(self.frame)
        }
    }
}
```

**Key APIs:** `NSPanel(styleMask:[.nonactivatingPanel,.borderless,.resizable,.fullSizeContentView])`, `isFloatingPanel`, `level = .statusBar`, `becomesKeyOnlyIfNeeded`, `collectionBehavior`, `NSVisualEffectView(.popover/.behindWindow)`, `NSHostingView`, `minSize`/`maxSize`, `NSWindow.didEndLiveResizeNotification`, `canBecomeKey` override (required or the composer `TextField` is dead).

---

## 5. Spring open / close (window level)

```swift
extension MenuBarPanel {
    func presentSpring(at anchor: NSRect) {            // anchor = status-item screen rect
        let target = Self.frame(for: self, under: anchor) // see StatusBarController.anchorRect
        alphaValue = 0
        setFrame(target, display: false)               // SNAP position — never animate origin
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            ctx.allowsImplicitAnimation = true
            animator().alphaValue = 1
        }
        // SwiftUI content runs its own entrance via Motion.panelOpen + StaggeredAppear.
    }

    func dismissSpring() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1                        // reset for next open
        }
    }
}
```

The SwiftUI content entrance is driven by a `@State isVisible` toggled `true` in `presentSpring` (pass it into the hosting view via the model or an `@Published` flag) so rows animate in with `StaggeredAppear`.

**Key APIs:** `NSAnimationContext.runAnimationGroup`, `CAMediaTimingFunction(controlPoints:)`, `animator().alphaValue`, `allowsImplicitAnimation`.

---

## 6. `StatusBarController` (icon, badge, anchor, click-outside)

```swift
final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: MenuBarPanel
    private let model: ReminderViewModel
    private var monitor: Any?
    private var cancellable: AnyCancellable?

    init(panel: MenuBarPanel, model: ReminderViewModel) {
        self.panel = panel; self.model = model
        if let b = item.button {
            b.target = self; b.action = #selector(toggle)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshBadge()
        cancellable = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refreshBadge() }   // due-count badge
        }
    }

    private func refreshBadge() {
        guard let b = item.button else { return }
        b.image = NSImage(systemSymbolName: model.dueCount > 0 ? "checklist.unchecked" : "checklist",
                          accessibilityDescription: "Agent Reminders")
        b.title = model.dueCount > 0 ? " \(model.dueCount)" : ""
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
```

Panel placement math (centered under the icon, 6pt gap, clamped to `visibleFrame`):

```swift
extension MenuBarPanel {
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
}
```

**Key APIs:** `NSStatusBar.system.statusItem`, `button.sendAction(on:)`, `NSImage(systemSymbolName:)`, `NSEvent.addGlobalMonitorForEvents`, `window.convertToScreen`, `NSScreen.visibleFrame`, Combine `objectWillChange.sink` for the live badge. (Add `import Combine`.)

---

## 7. Frame persistence — `PanelFrameStore`

```swift
struct PanelFrameStore {
    static let defaultSize = NSSize(width: 392, height: 560)   // matches mockup --w
    static let minSize     = NSSize(width: 320, height: 300)
    static let maxSize     = NSSize(width: 560, height: 820)
    private let key = "MenuBarPanelFrame"
    private let d = UserDefaults.standard

    func save(_ frame: NSRect) { d.set(NSStringFromRect(frame), forKey: key) }

    func restoredSize() -> NSSize {
        guard let s = d.string(forKey: key) else { return Self.defaultSize }
        let r = NSRectFromString(s)
        return r.size == .zero ? Self.defaultSize : r.size
    }

    /// Full saved frame if it still lands on a connected screen, else nil (caller re-anchors).
    func restoredFrameIfOnScreen() -> NSRect? {
        guard let s = d.string(forKey: key) else { return nil }
        let r = NSRectFromString(s)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(r) } ? r : nil
    }
}
```

Only the **size** is restored at init; the **origin** is always recomputed from the live status-item anchor on each open (so the panel never strands off-screen and always points at the icon). `restoredFrameIfOnScreen()` is available if you later want sticky position too.

**Key APIs:** `NSStringFromRect` / `NSRectFromString`, `NSScreen.screens`/`visibleFrame`, `UserDefaults`.

---

## 8. Drag-to-resize — SwiftUI handle + cursor shim

The panel is `.resizable`, so the user can drag the macOS-native bottom edge — that already fires `didEndLiveResize` and persists. For an Arc-grade *explicit* handle inside the content (and to grow the SwiftUI list height live), add `ResizeHandle`:

```swift
struct ResizeHandle: View {
    let panel: NSWindow?                     // weak ref to MenuBarPanel for live frame mutation
    @State private var startH: CGFloat = 0

    var body: some View {
        ResizeCursorView()                   // NSViewRepresentable — keeps .resizeUpDown during drag
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        guard let panel else { return }
                        if startH == 0 { startH = panel.frame.height }
                        // Drag DOWN grows the panel. NSPanel origin is bottom-left,
                        // so growing height must also drop the origin.
                        let newH = (startH + v.translation.height)
                            .clamped(PanelFrameStore.minSize.height ... PanelFrameStore.maxSize.height)
                        var f = panel.frame
                        let dy = newH - f.height
                        f.origin.y -= dy
                        f.size.height = newH
                        panel.setFrame(f, display: true)   // LIVE, no animation
                    }
                    .onEnded { _ in
                        startH = 0
                        if let f = panel?.frame { PanelFrameStore().save(f) }
                    }
            )
    }
}

struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> Tracking { Tracking() }
    func updateNSView(_ v: Tracking, context: Context) {}
    final class Tracking: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
                owner: self))
        }
    }
}

extension Comparable { func clamped(_ r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) } }
```

Because SwiftUI's `DragGesture` resets `NSCursor` mid-drag, the `resetCursorRects()` tracking area is required for a reliable resize cursor (per research). The SwiftUI list height should be `nil`/flexible (drop `.frame(maxHeight: 360)`, let it fill remaining space) so it grows as the window grows; on release, internal reflow animates with `Motion.resizeReflow`.

**Key APIs:** `DragGesture(minimumDistance:)`, `NSView.resetCursorRects()` + `addCursorRect(_:cursor:)`, `NSTrackingArea`, `panel.setFrame(_:display:)` (display:true, animate:false for live).

---

## 9. SwiftUI motion inside `MenuPanelView`

`Motion.swift` exposes the tokens and a stagger modifier:

```swift
enum Motion {
    static let panelOpen   = Animation.spring(duration: 0.38, bounce: 0.22)
    static let panelClose  = Animation.spring(duration: 0.20, bounce: 0.0)
    static let listChange  = Animation.spring(duration: 0.28, bounce: 0.0)
    static let hover       = Animation.spring(duration: 0.18, bounce: 0.12)
    static let press       = Animation.spring(duration: 0.12, bounce: 0.0)
    static let resizeReflow = Animation.spring(duration: 0.35, bounce: -0.1)
    static let segThumb    = Animation.spring(duration: 0.34, bounce: 0.0)

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 12)
            .onAppear {
                if Motion.reduceMotion { on = true; return }
                let t = Double(index) / 8.0
                let delay = t * t * (3 - 2 * t) * 0.45      // smoothstep, cap 0.45s
                withAnimation(Motion.panelOpen.delay(delay)) { on = true }
            }
    }
}
extension View { func staggered(_ i: Int) -> some View { modifier(StaggeredAppear(index: i)) } }
```

Edits to `MenuPanelView.swift`:
- `content` list: keep `ScrollView + LazyVStack` (already correct — **do not** switch to `List`). Add to each `ReminderRow`:
  ```swift
  .transition(.asymmetric(
      insertion: .opacity.combined(with: .offset(y: 8)),
      removal:   .opacity.combined(with: .scale(scale: 0.94))))
  ```
  and wrap the `ForEach`/section container in `.animation(Motion.listChange, value: model.items)`.
- Apply `.staggered(i)` to top-level sections on first appear (drive via an index enumerated over visible rows).
- `ReminderRow` hover: replace the current `.background(... hovering ...)` with `Motion.hover` animation and add a 1px lift (`.offset(y: hovering ? -1 : 0)`) + foreground `.secondary→.primary`; add a press `scaleEffect(0.996)` via `DragGesture(minimumDistance:0)` under `Motion.press` (mirroring the mockup `.act`/`.row:active`).
- Composer segmented `Picker` thumb already animates natively; if you build a custom segmented control, slide the thumb under `Motion.segThumb`.
- Metric/section counts: `.contentTransition(.numericText())` + `.monospacedDigit()`.
- Add `ResizeHandle(panel: <weak panel>)` as the last element of the root `VStack` (or a corner overlay). Pass the panel reference down via an `@EnvironmentObject` wrapper or an injected closure — simplest is a `weak var` on the model set by `AppDelegate`.

---

## 10. Wiring summary (init order)

`AgentRemindersApp` → adaptor → `AppDelegate.applicationDidFinishLaunching`:
1. `model = ReminderViewModel()` (loads store, starts 30s poll, requests notifications — unchanged).
2. `panel = MenuBarPanel(model:)` (builds vibrancy + `NSHostingView`, restores size, installs frame observers).
3. `statusBar = StatusBarController(panel:, model:)` (status item, badge, anchor, click-outside, badge subscription).
4. `NSApp.setActivationPolicy(.accessory)`.

Open path: click → `toggle()` → `open()` → `anchorRect()` → `panel.presentSpring(at:)` → snap frame + alpha spring + SwiftUI stagger; install global click monitor. Close path: click-outside or icon → `dismissSpring()` → alpha 0 → `orderOut` → remove monitor.

---

## 11. Acceptance tests (gate before review — leaf work)

1. **Open/close motion:** click icon → panel fades+scales in under the icon (origin never lerps), rows stagger; click outside → fades out in 150ms. (Screen-record; check rubric dims 1, 2.)
2. **Resize + persistence:** drag bottom edge / handle → live, jitter-free, cursor stays `resizeUpDown`; quit + relaunch → panel reopens at the saved size. Disconnect the display it was sized on → reopens at default under the icon, not off-screen.
3. **Composer:** type in the field (proves `canBecomeKey`), ⏎ → row springs in optimistically, field clears same frame.
4. **Badge:** add a reminder due now → menu-bar badge count updates live without reopening.
5. **Reduce-motion:** enable System Settings → Reduce Motion → open is an instant crossfade, no stagger/sheen.
6. **Existing unit tests:** `ReminderStoreTests` still green (Core untouched).

**Build:** `swift build` from `apps/macos`; run the executable. No new SPM deps. `swift test` for Core.
