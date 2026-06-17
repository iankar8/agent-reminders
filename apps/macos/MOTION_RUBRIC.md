# Motion Rubric — Arc / Comet-grade polish for the Agent Reminders menu-bar panel

_Tuned to The Browser Company's Arc and Perplexity's Comet. This is the acceptance gate for both prototypes (native SwiftUI in `apps/macos`, WKWebView shell in `apps/macos-web`). A dimension is "shipped" only when it hits the 9–10/10 target. Every number here is implementable — durations in ms, springs as SwiftUI `spring(duration:bounce:)` or CSS `linear()`/`cubic-bezier()`._

---

## 0. Motion vocabulary (the shared dictionary)

Use these named tokens everywhere. Do not invent one-off curves.

| Token | SwiftUI | CSS equivalent | Use for |
|---|---|---|---|
| `panelOpen` | `.spring(duration: 0.38, bounce: 0.22)` | `cubic-bezier(.2,.9,.25,1.05)` 260ms (matches mockup `@keyframes pop`) | Panel content entrance, window content scale |
| `panelClose` | `.spring(duration: 0.20, bounce: 0.0)` | `cubic-bezier(.4,0,1,1)` 150ms | Reverse content, window alpha→0 |
| `listChange` | `.spring(duration: 0.28, bounce: 0.0)` | `cubic-bezier(.4,0,.6,1)` 300ms (mockup `leave`/`enter`) | Insert / remove / reorder rows |
| `hover` | `.spring(duration: 0.18, bounce: 0.12)` | `.16s cubic-bezier(.2,.7,.3,1)` (mockup `.row`) | Background fill, lift, color shift |
| `press` | `.spring(duration: 0.12, bounce: 0.0)` | `transform .14s ease` (mockup `.act`) | scaleEffect 0.97 / 0.996 |
| `resizeReflow` | `.spring(duration: 0.35, bounce: -0.1)` | n/a (live resize uses no animation) | Content reflow AFTER drag release only |
| `segThumb` | `.spring(duration: 0.34, bounce: 0.0)` | `transform .34s cubic-bezier(.32,.72,0,1)` (mockup `#thumb`) | Segmented-control / tab thumb slide |
| `disclosure` | `.spring(duration: 0.26, bounce: 0.08)` | `max-height .24s ease` (mockup searchbar) | History expand, search reveal, settings sheet |

**Window-level (AppKit, both prototypes):** open = `NSAnimationContext` alpha 0→1, duration `0.22`, `CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)`. Close = alpha 1→0, duration `0.15`, `.easeIn`. **Never animate window position** — snap the frame to the status-item anchor before `orderFront`, only opacity + content scale animate. (Avoids the "flying panel" anti-pattern.)

**Cardinal rules**
1. One spring per property change; interrupt-safe (re-target from current velocity, never restart from 0).
2. Live drag-resize is *direct frame mutation, zero animation* — jitter-free. Springs only on release reflow.
3. Stagger caps at **0.45s** total. First row delay 0s; row `i` delay = `smoothstep(i/8) * 0.45` where `smoothstep(t)=t*t*(3-2t)`.
4. 120fps on ProMotion comes free in SwiftUI; in WKWebView keep transforms on `transform`/`opacity` only (compositor-only, no layout thrash).
5. Reduce-motion: honor `NSWorkspace.accessibilityDisplayShouldReduceMotion` / `prefers-reduced-motion` — collapse all springs to a 120ms opacity crossfade, kill stagger and sheen.

---

## Dimension 1 — Panel open / close motion

**Arc reference:** the command bar (Cmd-T) doesn't slide in — it materializes in place with a fast scale-from-0.985 + opacity, shadow blooming from tight to soft (Arc search bar phase 2: shadow radius 10→70 over 380ms). **Comet reference:** assistant sidebar expands with a single overdamped spring, content fading in a beat behind the container.

**9–10/10 looks like:** Click the menu-bar icon → window alpha 0→1 in 220ms while content scales 0.985→1.0 and translates y:-8→0 (`panelOpen`). Shadow blooms from `shadow-card` to `shadow-panel` over the same window. Rows arrive in a capped smoothstep stagger so the eye reads top-to-bottom. Close runs the mirror in 150ms (`panelClose`, no stagger) then `orderOut` and reset alpha for the next open. Pointer/beak (the little triangle under the icon) is anchored to status-item center-x and never animates independently. Nothing ever animates the window's *origin*.

**Fails if:** position lerps in (flying panel); content and container share one fade with no scale; close is instant (feels like a crash) or longer than open (feels sluggish).

---

## Dimension 2 — List micro-interactions

**Arc reference:** tab/list reordering uses physical springs; items get out of each other's way rather than snapping. **Comet reference:** answer cards stream in with a soft upward settle, never a hard cut.

**9–10/10 looks like:** Insert = opacity + `offset(y:8)` settling under `listChange`. Remove = opacity + `scale(0.94)` (mockup: slide x:+14 + collapse max-height) so neighbors close the gap with the same spring, no jump-cut. Completing a todo: the checkmark scales 0.5→1.0 in 200ms, the row strikes through, then leaves after a 1-beat hold so the user sees the result before it goes. Group headers ("Due", "Open to-dos", "Upcoming") stay pinned; counts tween with `.contentTransition(.numericText())`. Use `ScrollView + LazyVStack`, **never SwiftUI `List`** (List breaks insert/remove transitions on macOS 15). A one-time scroll-into-view on a newly added row.

**Fails if:** rows pop in/out with no transition; neighbors teleport instead of springing; numbers hard-swap.

---

## Dimension 3 — Gesture & pointer feedback

**Arc reference:** every interactive surface acknowledges the cursor within a frame — hover lifts, press depresses, release springs back. **Comet:** subtle, fast, never bouncy on press.

**9–10/10 looks like:** `.onHover` drives background fill (`hover-fill`) + a 1px lift (`translateY(-1px)`) + foreground `.secondary→.primary`, all under `hover`. A one-shot specular `sheen` sweeps across the row on hover-enter (mockup `@keyframes sheen`, 600ms, fires once). Press = `scaleEffect(0.97)` for buttons / `0.996` for full rows under `press`, via `DragGesture(minimumDistance:0)` (not `.buttonStyle(.borderless)`, which kills feedback in panels). Row trailing area cross-fades from the default chip (priority/due tag) to the action cluster (done / snooze / more) on hover in 150ms. The selected row carries a persistent inset ring. Cursor is correct over every affordance (text I-beam in composer, resize cursor over the handle).

**Fails if:** hover has no lift; press doesn't depress; actions appear with no cross-fade; cursor wrong on the resize edge.

---

## Dimension 4 — Composer / input states

**Arc reference:** the command bar field is the hero — focus ring blooms, placeholder is conversational, submit is instant with optimistic insert. **Comet:** the ask field grows to fit, glows on focus.

**9–10/10 looks like:** Focus blooms a 2px accent ring over 180ms (no abrupt outline). Segmented Todo/Reminder thumb slides under `segThumb`. Placeholder swaps copy with the segment ("Add a to-do…" ↔ "Remind me to…"). Submit is **optimistic**: the row springs into the list immediately (`listChange`) and the field clears in the same frame — no spinner, no wait on disk. Empty field disables the + button with a 120ms opacity fade, never a hard gray flip. The time field (`10m`, `tomorrow`) only appears for Reminder, sliding in with `disclosure`. ⏎ submits; Esc clears focus.

**Fails if:** focus ring snaps; submit waits on the store write; the + button hard-toggles; placeholder is generic.

---

## Dimension 5 — Resize feel

**Arc/Comet reference:** surfaces resize with the cursor locked to the edge, content reflowing live with zero lag, and the chosen size is *remembered* across launches.

**9–10/10 looks like:** A bottom (and/or corner) drag handle shows `.resizeUpDown`/`.resizeUpLeftDownRight` reliably — implemented via an `NSView` `resetCursorRects()` tracking area, because SwiftUI `DragGesture` resets the cursor mid-drag. During drag: **direct frame mutation, no animation**, tracking the cursor sub-frame with no rubber-banding. Clamp to min 320×300 / max ~560×820. On release: a single `resizeReflow` spring settles internal content (not the window frame). Size persists to `UserDefaults` (`NSStringFromRect`) on `didEndLiveResizeNotification`; restored on next launch only if the frame still intersects a live `NSScreen` (guards against a panel stranded on a disconnected display). Re-anchors x to the status item after restore.

**Fails if:** resize lags or jitters; cursor flickers to arrow mid-drag; size resets on relaunch; panel restores off-screen.

---

## Dimension 6 — Typography & rhythm

**Arc reference:** SF Pro, tight optical hierarchy, generous-but-disciplined whitespace, tabular numerals for counts. **Comet:** quiet, readable, no decorative type.

**9–10/10 looks like:** SF Pro Text throughout. Title 12.5–13px regular/medium; meta 10.5px `.secondary`; section labels 10.5px 640-weight uppercase, letter-spacing 0.05em. All counts/times `font-variant-numeric: tabular-nums` / `.monospacedDigit()` so they don't reflow as digits change. Vertical rhythm on an 8px grid (row padding 7–8px). Two-line clamp on titles with ellipsis. Line-height ~1.3. Numeric transitions tween, never jump.

**Fails if:** counts wobble on update (non-tabular); inconsistent label weights; titles overflow or clip mid-word.

---

## Dimension 7 — Material / color / depth

**Arc reference:** real vibrancy, accent restraint (one accent at a time), shadows that *separate the object from its shadow* (offset soft shadow, not a uniform halo). **Comet:** clean, low-chroma, content-first.

**9–10/10 looks like:** Window background is true vibrancy — `NSVisualEffectView .behindWindow` (`.popover`/`.hudWindow` material) in native; in WKWebView the web bg is transparent and the same `NSVisualEffectView` shows through. Two-layer shadow: a tight 1px contact shadow + a soft 28–60px drop (`shadow-panel`), so the panel reads as floating glass. Rows are subtle glass cards with a top specular line and a bottom edge line. Accent is the macOS system blue, used once per context (focus ring, primary action) — priority chips and due states are the only other color (orange = overdue/due). Full light/dark token sets (already in the mockup `:root` / `[data-theme="dark"]`); follow the system appearance live.

**Fails if:** flat opaque background (no vibrancy); halo shadow with no contact line; more than one accent competing; dark mode is an afterthought.

---

## Dimension 8 — Perceived performance

**Arc/Comet reference:** nothing ever feels like it's "loading." Optimistic UI, instant first paint, work hidden behind motion.

**9–10/10 looks like:** Panel paints fully on the first frame after click — no progressive layout. All mutations are optimistic against the in-memory model; the JSON store write happens after the UI updates (the store API is synchronous and fast, but the UI never blocks on it). The 30s poll/`tick()` reconciles silently; a row that fires gets a gentle state change, never a full re-render flash. Running tasks show a live micro-log + indeterminate bar so latency reads as activity, not as a hang. Reduce-motion path stays instant. Target: open→interactive < 1 frame of visible jank at 120fps.

**Fails if:** visible reflow on open; UI waits on disk; poll causes a flash; spinner where an optimistic insert belongs.

---

## Dimension 9 — Delight & cohesion

**Arc reference:** the product has a *voice* — celebratory empty states, the sheen, micro-rewards on completion — but it's coherent, never gratuitous. **Comet:** restraint is the delight.

**9–10/10 looks like:** Every motion uses a token from §0 — the whole panel feels authored by one hand. Empty state is a warm moment (sealed-checkmark, "All clear", human copy) not a void. Completing the last due item triggers a single understated flourish (checkmark bloom + the row settling out). The sheen, the segmented thumb, the focus bloom, the stagger all share the same spring family so transitions rhyme. No animation exists "because we could" — each one clarifies state, intent, latency, or transformation. Light/dark, hover/press, open/close all feel like the same object behaving consistently.

**Fails if:** mixed easing families (some springs, some linear, no system); dead empty state; a flourish that fires too often and becomes noise; motion that decorates instead of informs.

---

## Scoring

Score each dimension 1–10 against its target. **Ship gate: every dimension ≥ 9.** Log scores + the specific failing detail in `POLISH_LOG.md` each pass; fix the lowest dimension first. Capture before/after screen recordings for dimensions 1, 2, 5 (the motion-heavy ones) since stills can't prove spring quality.
