import Foundation

public enum StoreError: Error, CustomStringConvertible {
    case notFound(String)
    case invalidSnapshot

    public var description: String {
        switch self {
        case .notFound(let id): return "Reminder not found: \(id)"
        case .invalidSnapshot: return "Invalid reminder snapshot"
        }
    }
}

/// Synchronous, file-backed store. Mirrors src/store.ts: atomic writes, a missing
/// or empty file is an empty queue, due todos fire once but stay open, due reminders
/// fire once and become `fired`.
public final class ReminderStore {
    public static let defaultTTL = "24h"

    private let fileURL: URL
    private let clock: () -> Date

    public init(fileURL: URL, clock: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.clock = clock
    }

    /// Resolve the store path the same way the Node package does:
    /// AGENT_REMINDERS_STORE env var, else ~/.agent-reminders/reminders.json.
    public static func defaultFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["AGENT_REMINDERS_STORE"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-reminders")
            .appendingPathComponent("reminders.json")
    }

    // MARK: - Reads / writes

    public func read() throws -> ReminderSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ReminderSnapshot()
        }
        let data = try Data(contentsOf: fileURL)
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ReminderSnapshot()
        }
        let snapshot = try JSONDecoder().decode(ReminderSnapshot.self, from: data)
        guard snapshot.version == 1 else { throw StoreError.invalidSnapshot }
        return snapshot
    }

    public func write(_ snapshot: ReminderSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        var data = try encoder.encode(snapshot)
        data.append(0x0A) // trailing newline, matching the Node writer
        try data.write(to: fileURL, options: [.atomic]) // temp-file + rename
    }

    // MARK: - Mutations

    @discardableResult
    public func add(_ input: AgentReminderInput) throws -> AgentReminder {
        var snapshot = try read()
        let now = clock()
        let nowIso = ReminderTime.iso(from: now)
        let kind = input.kind ?? (input.fireAt != nil ? .reminder : .todo)
        let item = AgentReminder(
            id: UUID().uuidString.lowercased(),
            kind: kind,
            target: input.target ?? ReminderTarget(kind: .thread, id: "current"),
            text: input.text,
            triggerPrompt: input.triggerPrompt ?? Self.defaultTriggerPrompt(kind: kind, text: input.text),
            status: .open,
            fireAt: try ReminderTime.parse(input.fireAt, now: now),
            expiresAt: try ReminderTime.parse(input.expiresAt ?? Self.defaultTTL, now: now),
            createdAt: nowIso,
            updatedAt: nowIso
        )
        snapshot.items.append(item)
        try write(snapshot)
        return item
    }

    @discardableResult
    public func update(_ id: String, _ changes: AgentReminderUpdate) throws -> AgentReminder {
        var snapshot = try read()
        let now = clock()
        let index = try indexOf(id, in: snapshot)
        var item = snapshot.items[index]

        if let text = changes.text { item.text = text }
        if let kind = changes.kind { item.kind = kind }
        if let target = changes.target { item.target = target }
        if let triggerPrompt = changes.triggerPrompt { item.triggerPrompt = triggerPrompt }
        if let note = changes.note { item.note = note }
        if let expiresAt = changes.expiresAt {
            item.expiresAt = try ReminderTime.parse(expiresAt, now: now)
        }
        if let fireAt = changes.fireAt {
            item.fireAt = fireAt.isEmpty ? nil : try ReminderTime.parse(fireAt, now: now)
            // A changed fire time should be allowed to notify/fire again.
            item.firedAt = nil
            if item.status == .fired { item.status = .open }
        }

        item.updatedAt = ReminderTime.iso(from: now)
        snapshot.items[index] = item
        try write(snapshot)
        return item
    }

    @discardableResult
    public func done(_ id: String, note: String? = nil) throws -> AgentReminder {
        try mutate(id) { item, now in
            item.status = .done
            item.doneAt = ReminderTime.iso(from: now)
            if let note { item.note = note }
        }
    }

    @discardableResult
    public func cancel(_ id: String, note: String? = nil) throws -> AgentReminder {
        try mutate(id) { item, now in
            item.status = .cancelled
            item.cancelledAt = ReminderTime.iso(from: now)
            if let note { item.note = note }
        }
    }

    @discardableResult
    public func snooze(_ id: String, fireAt: String, note: String? = nil) throws -> AgentReminder {
        var snapshot = try read()
        let now = clock()
        let index = try indexOf(id, in: snapshot)
        var item = snapshot.items[index]
        item.status = .open
        item.fireAt = try ReminderTime.parse(fireAt, now: now)
        item.updatedAt = ReminderTime.iso(from: now)
        if let note { item.note = note }
        item.firedAt = nil
        snapshot.items[index] = item
        try write(snapshot)
        return item
    }

    public func remove(_ id: String) throws {
        var snapshot = try read()
        snapshot.items.removeAll { $0.id == id }
        try write(snapshot)
    }

    // MARK: - Queries

    /// All items, with forgotten open items normalized to `expired`.
    public func list() throws -> [AgentReminder] {
        let snapshot = try read()
        let now = clock()
        return snapshot.items.map { normalizeExpired($0, now) }
    }

    /// Mark newly-due items: reminders become `fired`, todos stay `open`. Each item
    /// fires at most once. Returns the items that fired on this call (for notifying).
    @discardableResult
    public func fireDue() throws -> [AgentReminder] {
        var snapshot = try read()
        let now = clock()
        var fired: [AgentReminder] = []

        for index in snapshot.items.indices {
            var item = normalizeExpired(snapshot.items[index], now)

            if item.status != .open || !ReminderTime.isDue(item.fireAt, now: now) || alreadyFiredForDueTime(item) {
                snapshot.items[index] = item
                continue
            }

            let nowIso = ReminderTime.iso(from: now)
            item.firedAt = nowIso
            item.updatedAt = nowIso
            item.status = item.kind == .reminder ? .fired : .open
            snapshot.items[index] = item
            fired.append(item)
        }

        try write(snapshot)
        return fired
    }

    // MARK: - Helpers

    @discardableResult
    private func mutate(_ id: String, _ body: (inout AgentReminder, Date) -> Void) throws -> AgentReminder {
        var snapshot = try read()
        let now = clock()
        let index = try indexOf(id, in: snapshot)
        var item = snapshot.items[index]
        item.updatedAt = ReminderTime.iso(from: now)
        body(&item, now)
        snapshot.items[index] = item
        try write(snapshot)
        return item
    }

    private func indexOf(_ id: String, in snapshot: ReminderSnapshot) throws -> Int {
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else {
            throw StoreError.notFound(id)
        }
        return index
    }

    private func normalizeExpired(_ item: AgentReminder, _ now: Date) -> AgentReminder {
        guard item.status == .open, ReminderTime.isDue(item.expiresAt, now: now) else {
            return item
        }
        var copy = item
        copy.status = .expired
        copy.updatedAt = ReminderTime.iso(from: now)
        return copy
    }

    private func alreadyFiredForDueTime(_ item: AgentReminder) -> Bool {
        guard let firedAt = item.firedAt, let fireAt = item.fireAt,
              let firedDate = ReminderTime.parseStored(firedAt),
              let fireDate = ReminderTime.parseStored(fireAt) else {
            return false
        }
        return firedDate >= fireDate
    }

    private static func defaultTriggerPrompt(kind: ReminderKind, text: String) -> String {
        switch kind {
        case .todo:
            return "Reminder: this agent to-do is due.\n\nTo-do: \(text)\n\nAct on it if possible. Mark it done if complete, or snooze it with a short reason."
        case .reminder:
            return "Reminder: \(text)"
        }
    }
}
