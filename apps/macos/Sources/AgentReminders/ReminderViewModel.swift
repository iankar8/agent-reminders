import Foundation
import SwiftUI
import AppKit
import OSLog
import AgentRemindersCore

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.iankar.agentreminders",
    category: "Reminders"
)

@MainActor
final class ReminderViewModel: ObservableObject {
    @Published private(set) var items: [AgentReminder] = []
    @Published private(set) var notificationsAuthorized = true

    /// Driven by the panel's open/close so SwiftUI content can run its
    /// staggered entrance. Not persisted.
    @Published var isPanelVisible = false

    private let store: ReminderStore
    private let storeURL: URL
    private var timer: Timer?

    init() {
        storeURL = ReminderStore.defaultFileURL()
        store = ReminderStore(fileURL: storeURL)
        reload()
        NotificationManager.shared.bootstrap { [weak self] granted in
            self?.notificationsAuthorized = granted
        }
        tick() // fire anything already due at launch
        startPolling()
    }

    private func startPolling() {
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Polls the JSON store: fire newly-due items (one notification each), then reload.
    func tick() {
        do {
            let fired = try store.fireDue()
            for item in fired { NotificationManager.shared.notify(item) }
            if !fired.isEmpty {
                logger.info("fired \(fired.count, privacy: .public) due item(s)")
            }
        } catch {
            logger.error("fireDue failed: \(error.localizedDescription, privacy: .public)")
        }
        reload()
        NotificationManager.shared.refreshAuthorization { [weak self] ok in
            self?.notificationsAuthorized = ok
        }
    }

    func reload() {
        let next: [AgentReminder]
        do {
            next = try store.list()
        } catch {
            logger.error("list failed: \(error.localizedDescription, privacy: .public)")
            next = []
        }
        // Animate SwiftUI's diff so inserts/removes/reorders spring rather than pop.
        // No-op visually at launch since there's nothing on screen yet.
        withAnimation(Motion.listChange) { items = next }
    }

    // MARK: - Grouping

    private var now: Date { Date() }

    var dueItems: [AgentReminder] {
        items.filter { $0.status == .open && ReminderTime.isDue($0.fireAt, now: now) }
    }
    var openTodos: [AgentReminder] {
        items.filter { $0.kind == .todo && $0.status == .open && !ReminderTime.isDue($0.fireAt, now: now) }
    }
    var upcomingReminders: [AgentReminder] {
        items.filter {
            $0.kind == .reminder && $0.status == .open && $0.fireAt != nil
                && !ReminderTime.isDue($0.fireAt, now: now)
        }
    }
    var history: [AgentReminder] {
        items.filter { [.done, .fired, .cancelled, .expired].contains($0.status) }
    }

    var openCount: Int { items.filter { $0.status == .open }.count }
    var dueCount: Int { dueItems.count }
    var todoCount: Int { items.filter { $0.kind == .todo && $0.status == .open }.count }
    var reminderCount: Int { items.filter { $0.kind == .reminder && $0.status == .open }.count }

    // MARK: - Actions

    func addTodo(_ text: String) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        mutate { _ = try store.add(AgentReminderInput(kind: .todo, target: ReminderTarget(kind: .newAgent), text: trimmed)) }
    }

    func addReminder(_ text: String, at time: String) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        let when = time.trimmed.isEmpty ? "1h" : time.trimmed
        mutate { _ = try store.add(AgentReminderInput(kind: .reminder, target: ReminderTarget(kind: .newAgent), text: trimmed, fireAt: when)) }
    }

    func complete(_ item: AgentReminder) { mutate { _ = try store.done(item.id) } }
    func cancel(_ item: AgentReminder) { mutate { _ = try store.cancel(item.id) } }
    func delete(_ item: AgentReminder) { mutate { try store.remove(item.id) } }
    func snooze(_ item: AgentReminder, by time: String) { mutate { _ = try store.snooze(item.id, fireAt: time) } }

    func update(_ item: AgentReminder, text: String, kind: ReminderKind, fireAt: String?) {
        mutate {
            _ = try store.update(item.id, AgentReminderUpdate(text: text, kind: kind, fireAt: fireAt))
        }
    }

    func openStore() {
        NSWorkspace.shared.activateFileViewerSelecting([storeURL])
    }

    private func mutate(_ body: () throws -> Void, action: String = #function) {
        do {
            try body()
            logger.info("action \(action, privacy: .public)")
            reload()
        } catch {
            logger.error("action \(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
