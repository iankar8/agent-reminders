import AppKit
import WebKit
import AgentRemindersCore

/// The ONLY place that touches `AgentRemindersCore.ReminderStore`. Maps a small
/// JS action vocabulary onto the existing store API and pushes a `reminders`
/// event back to JS with the full list (the store's own camelCase JSON).
final class Bridge: NSObject, WKScriptMessageHandler {
    private let store: ReminderStore
    weak var web: WebPanelController?            // set after init for Swift→JS push
    weak var panel: PanelWindow?                 // for the optional CSS resize handle
    var onStateChange: (() -> Void)?             // fired after every pushState (badge refresh)
    private var timer: Timer?

    init(store: ReminderStore = ReminderStore(fileURL: ReminderStore.defaultFileURL())) {
        self.store = store
        super.init()
        startPolling()                           // mirror the native 30s tick
    }

    deinit { timer?.invalidate() }

    // MARK: - JS → Swift

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        let p = body["payload"] as? [String: Any] ?? [:]
        handle(action: action, payload: p)
    }

    /// Route a single action against the store. Extracted from the message
    /// handler so it is unit-testable without a real `WKScriptMessage`.
    func handle(action: String, payload p: [String: Any]) {
        do {
            switch action {
            case "list":
                break                            // just pushes current state below
            case "addTodo":
                _ = try store.add(AgentReminderInput(
                    kind: .todo,
                    target: ReminderTarget(kind: .newAgent),
                    text: (p["text"] as? String) ?? ""))
            case "addReminder":
                _ = try store.add(AgentReminderInput(
                    kind: .reminder,
                    target: ReminderTarget(kind: .newAgent),
                    text: (p["text"] as? String) ?? "",
                    fireAt: (p["fireAt"] as? String) ?? "1h"))
            case "done":
                if let id = p["id"] as? String { _ = try store.done(id) }
            case "cancel":
                if let id = p["id"] as? String { _ = try store.cancel(id) }
            case "delete":
                if let id = p["id"] as? String { try store.remove(id) }
            case "snooze":
                if let id = p["id"] as? String, let when = p["fireAt"] as? String {
                    _ = try store.snooze(id, fireAt: when)
                }
            case "update":
                if let id = p["id"] as? String {
                    _ = try store.update(id, AgentReminderUpdate(
                        text: p["text"] as? String,
                        kind: (p["kind"] as? String).flatMap(ReminderKind.init(rawValue:)),
                        fireAt: p["fireAt"] as? String))
                }
            case "revealStore":
                NSWorkspace.shared.activateFileViewerSelecting([ReminderStore.defaultFileURL()])
            case "resize":
                if let dh = (p["dh"] as? NSNumber)?.doubleValue { panel?.resize(byHeight: CGFloat(dh)) }
            case "quit":
                NSApp.terminate(nil)
            default:
                break
            }
            pushState()                          // optimistic refresh after any mutation
        } catch {
            let payload = ["message": "\(error)"]
            let json = (try? JSONSerialization.data(withJSONObject: payload))
                .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"message":"error"}"#
            sendToWeb(event: "error", json: json)
        }
    }

    /// Hop to the main actor for a Swift→JS send (handle runs on the main thread,
    /// but `WebPanelController.send` is `@MainActor` so we route through it safely).
    private func sendToWeb(event: String, json: String) {
        let send = { [weak self] in self?.web?.send(event: event, json: json) }
        if Thread.isMainThread { MainActor.assumeIsolated(send) }
        else { DispatchQueue.main.async { MainActor.assumeIsolated(send) } }
    }

    // MARK: - Swift → JS

    /// Serialize the full list to the SAME JSON the store uses (camelCase keys)
    /// and push to JS. Runs on the main thread (message handler + timer both do).
    func pushState() {
        let json = encodeState()
        let push = { [weak self] in
            guard let self else { return }
            if let json { self.web?.send(event: "reminders", json: json) }
            self.onStateChange?()
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(push)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(push) }
        }
    }

    /// The exact JSON pushed to JS — `AgentReminder` array with camelCase keys.
    /// Public for tests (round-trip + shape assertions).
    func encodeState() -> String? {
        guard let items = try? store.list() else { return nil }
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? enc.encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Count of open items whose fireAt is in the past (due now). Drives the badge.
    func dueCount() -> Int {
        guard let items = try? store.list() else { return 0 }
        let now = Date()
        return items.filter { $0.status == .open && ReminderTime.isDue($0.fireAt, now: now) }.count
    }

    // MARK: - Poll

    private func startPolling() {
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                _ = try? self?.store.fireDue()    // fire due items (same semantics as native)
                self?.pushState()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
