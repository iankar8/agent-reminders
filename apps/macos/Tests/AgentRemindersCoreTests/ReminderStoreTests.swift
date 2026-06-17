import XCTest
@testable import AgentRemindersCore

/// A reference-typed clock so tests can advance "now" between calls.
private final class MutableClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

final class ReminderStoreTests: XCTestCase {
    private var dir: URL!
    private var fileURL: URL!
    private var clock: MutableClock!
    private var store: ReminderStore!

    private let base = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-reminders-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("store.json")
        clock = MutableClock(base)
        let clockRef = clock!
        store = ReminderStore(fileURL: fileURL, clock: { clockRef.now })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testDecodesExistingStore() throws {
        let json = """
        {
          "version": 1,
          "items": [
            {
              "id": "abc",
              "kind": "todo",
              "target": { "kind": "thread" },
              "text": "Existing todo",
              "triggerPrompt": "...",
              "status": "open",
              "expiresAt": "2026-06-17T15:29:09.517Z",
              "createdAt": "2026-06-16T15:29:09.517Z",
              "updatedAt": "2026-06-16T15:29:09.517Z"
            },
            {
              "id": "def",
              "kind": "reminder",
              "target": { "kind": "new_agent", "id": "builder" },
              "text": "Existing reminder",
              "triggerPrompt": "...",
              "status": "fired",
              "fireAt": "2026-06-16T15:00:00.000Z",
              "firedAt": "2026-06-16T15:00:00.000Z",
              "createdAt": "2026-06-16T14:00:00.000Z",
              "updatedAt": "2026-06-16T15:00:00.000Z"
            }
          ]
        }
        """
        try json.data(using: .utf8)!.write(to: fileURL)

        let snapshot = try store.read()
        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0].kind, .todo)
        XCTAssertEqual(snapshot.items[1].target.kind, .newAgent)
        XCTAssertEqual(snapshot.items[1].target.id, "builder")
        XCTAssertEqual(snapshot.items[1].status, .fired)
    }

    func testCreatesTodoAndReminder() throws {
        let todo = try store.add(AgentReminderInput(text: "Plain todo"))
        XCTAssertEqual(todo.kind, .todo)
        XCTAssertEqual(todo.status, .open)
        XCTAssertNil(todo.fireAt)
        XCTAssertEqual(todo.target.kind, .thread)

        let reminder = try store.add(AgentReminderInput(text: "Ping later", fireAt: "5m"))
        XCTAssertEqual(reminder.kind, .reminder)
        XCTAssertEqual(reminder.fireAt, "2026-06-15T12:05:00.000Z")

        XCTAssertEqual(try store.list().count, 2)
    }

    func testUpdatePreservesStatusAndTarget() throws {
        let todo = try store.add(
            AgentReminderInput(target: ReminderTarget(kind: .agent, id: "writer"), text: "Draft note")
        )

        clock.now = base.addingTimeInterval(120)
        let updated = try store.update(todo.id, AgentReminderUpdate(text: "Draft the note"))

        XCTAssertEqual(updated.text, "Draft the note")
        XCTAssertEqual(updated.status, .open)
        XCTAssertEqual(updated.target, ReminderTarget(kind: .agent, id: "writer"))
        XCTAssertEqual(updated.updatedAt, "2026-06-15T12:02:00.000Z")
    }

    func testUpdatingFireAtReopensFiredReminder() throws {
        let reminder = try store.add(AgentReminderInput(text: "Ring", fireAt: "1m"))

        clock.now = base.addingTimeInterval(60)
        _ = try store.fireDue()
        XCTAssertEqual(try store.list().first?.status, .fired)

        let updated = try store.update(reminder.id, AgentReminderUpdate(fireAt: "10m"))
        XCTAssertEqual(updated.status, .open)
        XCTAssertNil(updated.firedAt)
        XCTAssertEqual(updated.fireAt, "2026-06-15T12:11:00.000Z")
    }

    func testDueDetectionFiresOnce() throws {
        let reminder = try store.add(AgentReminderInput(text: "Ring", fireAt: "1m"))
        let todo = try store.add(AgentReminderInput(kind: .todo, text: "Do it", fireAt: "1m"))

        clock.now = base.addingTimeInterval(60)
        let firstFire = try store.fireDue()
        XCTAssertEqual(Set(firstFire.map(\.id)), Set([reminder.id, todo.id]))

        let secondFire = try store.fireDue()
        XCTAssertTrue(secondFire.isEmpty, "items should fire at most once")

        let items = try store.list()
        XCTAssertEqual(items.first { $0.id == reminder.id }?.status, .fired)
        XCTAssertEqual(items.first { $0.id == todo.id }?.status, .open)
    }

    func testMissingFileIsEmptyQueue() throws {
        let missing = ReminderStore(fileURL: dir.appendingPathComponent("nope.json"))
        XCTAssertEqual(try missing.list().count, 0)
    }

    func testEmptyFileIsEmptyQueue() throws {
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.list().count, 0)
    }

    func testThrowsOnMissingId() throws {
        XCTAssertThrowsError(try store.update("nope", AgentReminderUpdate(text: "x"))) { error in
            XCTAssertEqual("\(error)", "Reminder not found: nope")
        }
    }
}
