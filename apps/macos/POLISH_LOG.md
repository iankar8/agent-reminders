# Agent Reminders — UI Polish Loop Log

**North star:** Arc browser + Perplexity Comet — expressive, spatial, premium-playful motion.
**Hard requirement:** drag-to-resize panel with size remembered across launches.
**Branch:** feat/macos-menubar-app · **App:** apps/macos · **Run:** ./script/build_and_run.sh

Backend (shared store, poller, notifications, MCP) and tests must stay green throughout.

---

## Phase status
- [in progress] **PHASE 0** — research Arc/Comet motion vocabulary → `MOTION_RUBRIC.md` (design-deep-dive dispatched 2026-06-17)
- [in progress] **PHASE 1** — build two prototypes, then CHECKPOINT for Ian's pick:
  - Prototype A — pure native SwiftUI/AppKit in a custom resizable `NSPanel`
  - Prototype B — native shell + `WKWebView` rendering the polished web UI
- [ ] **PHASE 2** — autonomous polish of the chosen prototype (loop until rubric ≥9 sustained 2 rounds)

## Rubric (score each /10 per round; target ≥9, sustained 2 rounds)
1. Panel open/close motion — springs from the menu-bar icon; spatial origin
2. List micro-interactions — item enter/exit, reorder, hover, selection
3. Gesture feedback — complete / snooze / delete feel tactile and satisfying
4. Composer & input states — focus, add animation, segmented control
5. Resize feel — live reflow, momentum, handle affordance, remembered size
6. Typography & rhythm — SF Pro discipline, hierarchy, spacing
7. Color / material / depth — vibrancy, separated shadows, light+dark
8. Perceived performance — no jank; instant feedback; 60/120fps
9. Delight & cohesion — signature moments; one consistent personality

---

## Rounds

### Round 0 — kickoff (2026-06-17)
- Dispatched Arc/Comet motion research (design-deep-dive, background).
- Scaffolding the shared AppKit shell (NSStatusItem + custom resizable NSPanel) for both prototypes.

### Round 1 — dual-prototype workflow + CHECKPOINT (2026-06-17)
- Ran ultracode workflow (11 agents, ~1.2M tokens): research → synth → build×2 → review×4.
- MOTION_RUBRIC.md + SPEC_A.md + SPEC_B.md written.
- **Prototype A (native)** built in apps/macos: MenuBarExtra → AppDelegate + NSStatusItem + borderless resizable NSPanel (NSVisualEffectView .popover) hosting MenuPanelView; drag-resize via bottom ResizeHandle + UserDefaults persistence; spring open/close; Motion tokens; staggered rows. `swift build` + 8 tests green.
- **Prototype B (web)** built in apps/macos-web: AppDelegate + NSStatusItem + resizable NSPanel hosting WKWebView (panel.html adapted from the liquid-glass mockup) over NSVisualEffectView; WKScriptMessageHandler bridge to the same store via AgentRemindersCore path-dep; drag-resize + persistence. `swift build` + 11 BridgeTests green.
- Both LIVE in the menu bar (AgentReminders + AgentRemindersWeb).
- **AWAITING:** Ian's pick (A native vs B web) → unblocks PHASE 2 autonomous polish.
- Note: parallel build agents on a shared tree left transient SourceKit noise; verified clean via real `swift build`/`swift test` on both packages.
