import Foundation

/// Swift mirror of the `agent-reminders` JSON schema (see ../../../src/types.ts).
/// Field names match the TypeScript package exactly so the same
/// `~/.agent-reminders/reminders.json` is read and written by both.

public enum ReminderKind: String, Codable, Sendable, CaseIterable {
    case todo
    case reminder
}

public enum ReminderStatus: String, Codable, Sendable {
    case open
    case fired
    case done
    case cancelled
    case expired
}

public enum ReminderTargetKind: String, Codable, Sendable {
    case thread
    case agent
    case newAgent = "new_agent"
}

public struct ReminderTarget: Codable, Equatable, Sendable {
    public var kind: ReminderTargetKind
    public var id: String?

    public init(kind: ReminderTargetKind = .thread, id: String? = nil) {
        self.kind = kind
        self.id = id
    }
}

public struct AgentReminder: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: ReminderKind
    public var target: ReminderTarget
    public var text: String
    public var triggerPrompt: String
    public var status: ReminderStatus
    public var fireAt: String?
    public var expiresAt: String?
    public var createdAt: String
    public var updatedAt: String
    public var firedAt: String?
    public var doneAt: String?
    public var cancelledAt: String?
    public var note: String?

    public init(
        id: String,
        kind: ReminderKind,
        target: ReminderTarget,
        text: String,
        triggerPrompt: String,
        status: ReminderStatus,
        fireAt: String? = nil,
        expiresAt: String? = nil,
        createdAt: String,
        updatedAt: String,
        firedAt: String? = nil,
        doneAt: String? = nil,
        cancelledAt: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.target = target
        self.text = text
        self.triggerPrompt = triggerPrompt
        self.status = status
        self.fireAt = fireAt
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.firedAt = firedAt
        self.doneAt = doneAt
        self.cancelledAt = cancelledAt
        self.note = note
    }
}

public struct ReminderSnapshot: Codable, Sendable {
    public var version: Int
    public var items: [AgentReminder]

    public init(version: Int = 1, items: [AgentReminder] = []) {
        self.version = version
        self.items = items
    }
}

/// Input for creating a new item (mirrors AgentReminderInput).
public struct AgentReminderInput: Sendable {
    public var kind: ReminderKind?
    public var target: ReminderTarget?
    public var text: String
    public var triggerPrompt: String?
    public var fireAt: String?
    public var expiresAt: String?

    public init(
        kind: ReminderKind? = nil,
        target: ReminderTarget? = nil,
        text: String,
        triggerPrompt: String? = nil,
        fireAt: String? = nil,
        expiresAt: String? = nil
    ) {
        self.kind = kind
        self.target = target
        self.text = text
        self.triggerPrompt = triggerPrompt
        self.fireAt = fireAt
        self.expiresAt = expiresAt
    }
}

/// Edit for an existing item (mirrors AgentReminderUpdate).
/// A `nil` field means "leave unchanged". For `fireAt`, an empty string clears
/// the time; any non-empty value is parsed and set (and clears the fired marker).
public struct AgentReminderUpdate: Sendable {
    public var text: String?
    public var kind: ReminderKind?
    public var target: ReminderTarget?
    public var triggerPrompt: String?
    public var fireAt: String?
    public var expiresAt: String?
    public var note: String?

    public init(
        text: String? = nil,
        kind: ReminderKind? = nil,
        target: ReminderTarget? = nil,
        triggerPrompt: String? = nil,
        fireAt: String? = nil,
        expiresAt: String? = nil,
        note: String? = nil
    ) {
        self.text = text
        self.kind = kind
        self.target = target
        self.triggerPrompt = triggerPrompt
        self.fireAt = fireAt
        self.expiresAt = expiresAt
        self.note = note
    }
}
