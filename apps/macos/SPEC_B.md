# SPEC B — Prototype B: Native shell + WKWebView panel

**Goal:** A NEW SwiftPM app at `apps/macos-web` that opens a resizable, borderless `NSPanel` under an `NSStatusItem`, hosting a `WKWebView` that loads the polished HTML/CSS/JS panel in `Resources/panel.html`. Transparent web background over an `NSVisualEffectView` for real vibrancy. Drag-to-resize + remembered size. A `WKScriptMessageHandler` bridge so JS reads/writes the same `~/.agent-reminders/reminders.json` store via `AgentRemindersCore`. Acceptance gate: `MOTION_RUBRIC.md` ≥ 9 per dimension.

**Why a separate app:** This is a parallel prototype to compare against Prototype A (SPEC_A). It must not disturb `apps/macos`. It *reuses* `AgentRemindersCore` as a local SwiftPM path dependency — zero duplication of store/model logic.

---

## 1. New directory layout

```
apps/macos-web/
  Package.swift
  Sources/
    AgentRemindersWeb/
      AgentRemindersWebApp.swift      # @main App shell + NSApplicationDelegateAdaptor
      AppDelegate.swift               # lifecycle, builds panel + status bar + bridge
      PanelWindow.swift               # NSPanel subclass (borderless, resizable, vibrancy)
      StatusBarController.swift       # NSStatusItem, anchor math, toggle, click-outside
      WebPanelController.swift        # WKWebView config, bootstrap inject, load, Swift→JS send
      Bridge.swift                    # WKScriptMessageHandler: routes JS actions → Core store
      WeakMessageHandler.swift        # retain-cycle breaker for userContentController.add
      PanelFrameStore.swift           # UserDefaults frame save/restore (same as SPEC_A §7)
      Resources/
        panel.html                    # self-contained web UI for the panel
  Tests/
    AgentRemindersWebTests/
      BridgeTests.swift               # action routing → store, JSON shape round-trip
```

---

## 2. `Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentRemindersWeb",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AgentRemindersWeb",
            dependencies: [
                .product(name: "AgentRemindersCore", package: "AgentReminders")
            ],
            resources: [.copy("Resources/panel.html")]   // bundled, loaded via loadFileURL
        ),
        .testTarget(
            name: "AgentRemindersWebTests",
            dependencies: ["AgentRemindersWeb"]
        )
    ]
)
```

Add the path dependency to reuse Core (sibling package):

```swift
// in Package(...) above `targets:`
dependencies: [
    .package(name: "AgentReminders", path: "../macos")
],
```

> `AgentRemindersCore` is already a public `.target` in `../macos/Package.swift` with public models + `ReminderStore`. No change needed there. If SwiftPM complains about the product not being exposed, add `products: [.library(name: "AgentRemindersCore", targets: ["AgentRemindersCore"])]` to `apps/macos/Package.swift` (additive, harmless to SPEC_A).

**Resource note:** `WKWebView.loadFileURL` needs the HTML on disk in the bundle. `.copy("Resources/panel.html")` makes it available at `Bundle.module.url(forResource:"panel", withExtension:"html")`. (Alternative: inline the whole HTML as a Swift string and `loadHTMLString` — avoids file-access entitlement fuss but loses devtools/hot-reload. Prefer `loadFileURL` for the prototype, fall back to `loadHTMLString` if sandbox file access bites.)

---

## 3. `PanelWindow` (NSPanel)

Identical windowing to SPEC_A §4 but `contentView` is the vibrancy view containing the `WKWebView` instead of an `NSHostingView`.

```swift
final class PanelWindow: NSPanel {
    static let defaultSize = NSSize(width: 392, height: 560)   // matches mockup --w:392px
    static let minSize     = NSSize(width: 320, height: 300)
    static let maxSize     = NSSize(width: 560, height: 820)
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
            [weak self] _ in guard let self else { return }; self.frameStore.save(self.frame)
        }
    }

    override var canBecomeKey: Bool { true }    // REQUIRED — text inputs in WKWebView stay dead otherwise
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
```

**Key APIs:** `NSPanel(styleMask:[.nonactivatingPanel,.borderless,.resizable,.fullSizeContentView])`, `canBecomeKey`/`canBecomeMain`/`acceptsFirstResponder` overrides (per web research — without all three, HTML `<input>` won't accept keystrokes), `NSVisualEffectView(.popover/.behindWindow)`, `NSWindow.didEndLiveResizeNotification`.

The `PanelFrameStore` is byte-for-byte the SPEC_A §7 version (copy it). Origin recomputed per-open from the status-item anchor (SPEC_A §6 `frame(for:under:)`). Spring open/close at the window level = SPEC_A §5 (`presentSpring`/`dismissSpring`) — copy verbatim; the WKWebView fades with the window. Resize is native (`.resizable` bottom edge) + optional CSS resize handle in the page that calls a `resize` bridge action (see §6).

---

## 4. `WebPanelController` (WKWebView setup)

```swift
final class WebPanelController: NSObject, WKNavigationDelegate {
    let webView: WKWebView

    init(bridge: Bridge) {
        let config = WKWebViewConfiguration()

        // Bootstrap the JS side of the bridge before page JS runs.
        let bootstrap = """
        window.__native = {
          _h: {},
          on(ev, fn){ this._h[ev] = fn; },
          dispatch(ev, json){ const f=this._h[ev]; if(f) f(JSON.parse(json)); },
          call(action, payload){ window.webkit.messageHandlers.bridge.postMessage({action, payload: payload||{}}); }
        };
        """
        config.userContentController.addUserScript(
            WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        config.userContentController.add(WeakMessageHandler(delegate: bridge), name: "bridge")

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self

        // Transparency — required so NSVisualEffectView shows through
        webView.setValue(false, forKey: "drawsBackground")   // private but stable since 10.12
        if #available(macOS 13.0, *) { webView.underPageBackgroundColor = .clear }

        load()
    }

    private func load() {
        guard let url = Bundle.module.url(forResource: "panel", withExtension: "html") else { return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    /// Swift → JS event push (used for live store updates / poll reconciliation).
    @MainActor func send(event: String, json: String) {
        let js = "window.__native.dispatch('\(event)', \(jsStringLiteral(json)));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
```

`WeakMessageHandler` is the standard retain-cycle breaker (web research §2) — `userContentController` strongly holds its handlers, so pass a weak wrapper, never the controller directly.

**Key APIs:** `WKWebViewConfiguration`, `WKUserContentController.addUserScript` + `add(_:name:)`, `WKUserScript(injectionTime:.atDocumentStart)`, `webView.setValue(false, forKey:"drawsBackground")`, `underPageBackgroundColor` (macOS 13+), `loadFileURL(_:allowingReadAccessTo:)`, `evaluateJavaScript`, `Bundle.module`.

---

## 5. `Bridge` — JS ⇆ Core store

The bridge is the *only* place that touches `AgentRemindersCore.ReminderStore`. It maps a small action vocabulary to the existing store API and emits a `reminders` event back to JS with the full list. This is the read/write stub the prompt asks for — concrete and complete enough to run.

```swift
import WebKit
import AgentRemindersCore

final class Bridge: NSObject, WKScriptMessageHandler {
    private let store: ReminderStore
    weak var web: WebPanelController?            // set after init for Swift→JS push
    private var timer: Timer?

    init(store: ReminderStore = ReminderStore(fileURL: ReminderStore.defaultFileURL())) {
        self.store = store
        super.init()
        startPolling()                           // mirror the native 30s tick
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        let p = body["payload"] as? [String: Any] ?? [:]
        do {
            switch action {
            case "list":
                break                                   // just pushes current state below
            case "addTodo":
                _ = try store.add(.init(kind: .todo,
                    target: .init(kind: .newAgent), text: (p["text"] as? String) ?? ""))
            case "addReminder":
                _ = try store.add(.init(kind: .reminder, target: .init(kind: .newAgent),
                    text: (p["text"] as? String) ?? "", fireAt: (p["fireAt"] as? String) ?? "1h"))
            case "done":      if let id = p["id"] as? String { _ = try store.done(id) }
            case "cancel":    if let id = p["id"] as? String { _ = try store.cancel(id) }
            case "delete":    if let id = p["id"] as? String { try store.remove(id) }
            case "snooze":
                if let id = p["id"] as? String, let when = p["fireAt"] as? String {
                    _ = try store.snooze(id, fireAt: when)
                }
            case "update":
                if let id = p["id"] as? String {
                    _ = try store.update(id, .init(text: p["text"] as? String,
                        kind: (p["kind"] as? String).flatMap(ReminderKind.init(rawValue:)),
                        fireAt: p["fireAt"] as? String))
                }
            case "revealStore":
                NSWorkspace.shared.activateFileViewerSelecting([ReminderStore.defaultFileURL()])
            case "quit":
                NSApp.terminate(nil)
            default:
                break
            }
            pushState()                                  // optimistic refresh after any mutation
        } catch {
            web?.send(event: "error", json: #"{"message":"\#(error)"}"#)
        }
    }

    /// Serialize the full list to the SAME JSON the store uses (camelCase keys) and push to JS.
    @MainActor func pushState() {
        guard let items = try? store.list() else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? enc.encode(items), let json = String(data: data, encoding: .utf8) {
            web?.send(event: "reminders", json: json)
        }
    }

    private func startPolling() {
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                _ = try? self?.store.fireDue()           // fire due items (same semantics as native)
                self?.pushState()
            }
        }
        RunLoop.main.add(t, forMode: .common); timer = t
    }
}
```

**JS → Swift** (in `panel.html`): `window.__native.call('addReminder', {text:'…', fireAt:'10m'})`, `window.__native.call('done', {id})`, etc.
**Swift → JS:** `window.__native.on('reminders', items => renderFromStore(items))` and `window.__native.on('error', e => …)`. On page load, call `window.__native.call('list')` once to hydrate.

The pushed `items` array is the exact `AgentReminder` shape (`id, kind, target, text, status, fireAt, firedAt, doneAt, createdAt, …`) — see `AgentRemindersCore/Models.swift`. The HTML adapter maps that to its row model (status `open/fired/done/cancelled/expired`, kind `todo/reminder`).

**Key APIs:** `WKScriptMessageHandler.userContentController(_:didReceive:)`, `message.body as? [String:Any]`, `ReminderStore` (`add/done/cancel/remove/snooze/update/list/fireDue`), `JSONEncoder`, `Timer.scheduledTimer`, `evaluateJavaScript` via `WebPanelController.send`.

---

## 6. `panel.html` — adapting the mockup

Start from a self-contained HTML mockup (SF Pro, glass material, light/dark tokens, segmented tabs, animated rows with `pop`/`enter`/`leave`/`sheen` keyframes, settings sheet, context menus). Adaptations:

1. **Strip the demo chrome.** Remove the `.scene` / `.wallpaper` / `.menubar` simulation wrappers (lines ~395–417) — those exist only to fake the desktop behind the popover. Keep `.popover > .panel` as the root and make `body{background:transparent;}` (the real `NSVisualEffectView` is the backdrop now). Remove the `.pointer` beak or keep it — the native panel has its own shadow; a CSS beak is optional.
2. **Transparent root.** `html,body{background:transparent;}`; the `.panel` keeps its `--glass-tint` + `backdrop-filter` so it reads as glass over the vibrancy.
3. **Replace the seeded `tasks` array** (lines ~534–549) with an empty `let tasks=[]` and a `renderFromStore(items)` that maps `AgentReminder` → the row view-model the existing render code expects. Mapping:
   - `status: 'open'+kind 'todo'` → pending todo; `status:'open'+kind 'reminder'` with future `fireAt` → upcoming; `fireAt` in the past & open → overdue; `status:'fired'` → fired/needs-attention; `status:'done'` → done; (snooze is just an `open` reminder with a future `fireAt`).
   - `due`/`dueState`/`wake` strings → compute from `fireAt` in JS (same logic as `MenuPanelView.dueLabel`: ≤0 ⇒ "due", `<60m` ⇒ "in Nm", `<24h` ⇒ "in Nh", else "in Nd").
   - `agent`/`priority` aren't in the store schema → default agent to a neutral icon, drop priority chips (or derive a faux priority from due-ness). Keep the row layout; just feed real fields.
4. **Wire events to the bridge.** Replace the demo click handlers (`data-act="done"/"snooze"/"more"`, composer submit) so they call `window.__native.call(...)`:
   - Complete circle / done button → `call('done',{id})`
   - Snooze menu → `call('snooze',{id, fireAt:'10m'|'1h'|'tomorrow'})`
   - Delete (in "more") → `call('delete',{id})`
   - Restore → `call('snooze',{id, fireAt:'now'})` or `call('update',{id, ...})`
   - Add a composer (the mockup has search/tabs but seed it with an add field, or reuse the searchbar shell) → `call('addTodo',{text})` / `call('addReminder',{text, fireAt})`
   - Gear/quit → `call('revealStore')` / `call('quit')`
5. **Hydrate + subscribe.** At the end of `<script>`: `window.__native.on('reminders', renderFromStore); window.__native.on('error', console.warn); window.__native.call('list');`
6. **Reduce-motion.** Add `@media (prefers-reduced-motion: reduce){ * { animation:none !important; transition:none !important; } }` and let the existing `pop`/`enter`/`leave`/`sheen` keyframes carry the Arc-grade motion otherwise (they already match the rubric tokens — `pop` is `panelOpen`, `enter`/`leave` are `listChange`, `sheen` is the hover specular).
7. **Theme sync.** The mockup already reads `prefers-color-scheme` for `auto`. Keep it; the `NSVisualEffectView` follows the system appearance, so light/dark stay consistent.
8. **Resize handle (optional, Arc-grade).** Add a bottom drag strip with `cursor: ns-resize` whose `mousedown`+`mousemove` computes a delta and calls `window.__native.call('resize',{dh})`; add a `resize` case to the `Bridge` that mutates `panel.frame` (drop origin.y by `dh`, grow height, clamp). The native bottom edge already works without this; the handle is for parity with SPEC_A §8.

The HTML stays a single file with inline `<style>`/`<script>` (no build step), bundled via `.copy`. Loading via `loadFileURL` (not `loadHTMLString`) keeps relative asset access and Web Inspector working for the polish loop.

---

## 7. `StatusBarController` + `AppDelegate`

Same as SPEC_A §3/§6 (status item with badge, anchor math, click-outside global monitor, spring present/dismiss), with the badge count read from the store instead of a `ReminderViewModel`:

```swift
// AppDelegate.applicationDidFinishLaunching
NSApp.setActivationPolicy(.accessory)
bridge = Bridge()                                  // owns the store + poll
webCtl = WebPanelController(bridge: bridge)
bridge.web = webCtl
panel  = PanelWindow(webView: webCtl.webView)
status = StatusBarController(panel: panel, badge: { (try? bridge.dueCount()) ?? 0 })
```

Add a tiny `dueCount()` to `Bridge` (`store.list().filter { $0.status == .open && isDue($0.fireAt) }.count`) and have the status controller refresh it on the same 30s cadence (or on each `pushState`). Badge icon: `checklist.unchecked` when due>0 else `checklist`, with the count as the button title.

**Entry point:** same adaptor pattern as SPEC_A §3 (`@main App { Settings{} }` + `@NSApplicationDelegateAdaptor(AppDelegate.self)`), `LSUIElement`/`.accessory` for menu-bar-only.

---

## 8. Pitfalls (from the web research) — bake these in

- **Dead text inputs:** must override `canBecomeKey` **and** `canBecomeMain` **and** `acceptsFirstResponder` on the panel, *and* call `makeKeyAndOrderFront` on open. Missing any → HTML `<input>` ignores keystrokes.
- **Retain cycle:** `userContentController.add(self, name:)` leaks the handler forever — use `WeakMessageHandler`.
- **Transparent bg is two steps:** `webView.setValue(false, forKey:"drawsBackground")` **and** `body{background:transparent}`. Either alone = opaque white flash.
- **Restore off-screen:** validate the saved frame intersects a live `NSScreen.visibleFrame`; else fall back to default under the icon.
- **No animation on frame restore:** `setFrame(_:display:animate:false)` to avoid a launch flash.
- **First-paint flash:** load the HTML and set `drawsBackground=false` *before* the panel is shown; present the panel only after `didFinish` navigation (or accept a 1-frame transparent gap — fine over vibrancy).

---

## 9. Acceptance tests (gate before review — leaf work)

1. **Anchor + open/close:** click icon → panel drops centered under it with the window spring; click outside → fades + `orderOut`. Switch Spaces → panel follows (`collectionBehavior`).
2. **Bridge round-trip:** in the page, add a reminder → `~/.agent-reminders/reminders.json` gains the item (verify on disk); reopen the native SPEC_A app or `cat` the file → same item. Mark done in the web panel → file `status:"done"`.
3. **Live push:** externally edit `reminders.json` (or let the 30s poll fire a due item) → the web list updates within 30s without reopening.
4. **Text input:** type in the composer (proves the three key overrides) → submit inserts a row.
5. **Resize + persistence:** drag bottom edge → live; quit + relaunch → same size; disconnect that display → reopens default under icon.
6. **Transparency:** the panel shows the desktop vibrancy through the glass (no white box).
7. **`BridgeTests`:** unit-test action routing → store mutations and the `pushState` JSON matches `AgentReminder` keys (camelCase, `fireAt`, `firedAt`, etc.).

**Build:** `swift build` from `apps/macos-web` (resolves Core via `../macos` path dep); run the executable. `swift test` for `BridgeTests`.

---

## 10. A-vs-B comparison criteria (why this prototype exists)

After both run, score each on `MOTION_RUBRIC.md` and note: vibrancy fidelity (native VFX is identical for both — it's the same `NSVisualEffectView`), motion authenticity (native springs are interrupt-safe; CSS `pop`/`enter` restart from 0 — rubric dim 1/2 favors A), iteration speed (web hot-reload + Web Inspector favors B), and store-bridge complexity (A is direct via `ReminderViewModel`; B adds the `WKScriptMessageHandler` hop). The decision artifact goes in `POLISH_LOG.md`.
