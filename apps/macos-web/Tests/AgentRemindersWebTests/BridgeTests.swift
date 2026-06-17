import XCTest
import AgentRemindersCore
@testable import AgentRemindersWeb

/// Acceptance test #7: action routing → store mutations, and the pushState JSON
/// shape matches the `AgentReminder` keys (camelCase: fireAt, firedAt, etc.).
final class BridgeTests: XCTestCase {
    private var tempURL: URL!
    private var store: ReminderStore!
    private var bridge: Bridge!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-reminders-web-tests-\(UUID().uuidString)")
            .appendingPathComponent("reminders.json")
        store = ReminderStore(fileURL: tempURL)
        bridge = Bridge(store: store)
    }

    override func tearDownWithError() throws {
        bridge = nil
        store = nil
        if let dir = tempURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Routing → store mutations

    func testAddTodoRoutesToStore() throws {
        bridge.handle(action: "addTodo", payload: ["text": "Ship the prototype"])
        let items = try store.list()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.text, "Ship the prototype")
        XCTAssertEqual(items.first?.kind, .todo)
        XCTAssertEqual(items.first?.status, .open)
        XCTAssertNil(items.first?.fireAt)
    }

    func testAddReminderRoutesWithFireAt() throws {
        bridge.handle(action: "addReminder", payload: ["text": "Call Ken", "fireAt": "1h"])
        let items = try store.list()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, .reminder)
        XCTAssertNotNil(items.first?.fireAt, "addReminder must set a fireAt")
    }

    func testDoneRoutesToStore() throws {
        let created = try store.add(AgentReminderInput(kind: .todo, text: "A"))
        bridge.handle(action: "done", payload: ["id": created.id])
        let item = try XCTUnwrap(try store.list().first { $0.id == created.id })
        XCTAssertEqual(item.status, .done)
        XCTAssertNotNil(item.doneAt)
    }

    func testCancelRoutesToStore() throws {
        let created = try store.add(AgentReminderInput(kind: .todo, text: "B"))
        bridge.handle(action: "cancel", payload: ["id": created.id])
        let item = try XCTUnwrap(try store.list().first { $0.id == created.id })
        XCTAssertEqual(item.status, .cancelled)
    }

    func testDeleteRemovesItem() throws {
        let created = try store.add(AgentReminderInput(kind: .todo, text: "C"))
        bridge.handle(action: "delete", payload: ["id": created.id])
        XCTAssertTrue(try store.list().isEmpty)
    }

    func testSnoozeSetsFutureFireAt() throws {
        let created = try store.add(AgentReminderInput(kind: .reminder, text: "D", fireAt: "1m"))
        bridge.handle(action: "snooze", payload: ["id": created.id, "fireAt": "2h"])
        let item = try XCTUnwrap(try store.list().first { $0.id == created.id })
        XCTAssertEqual(item.status, .open)
        let fireDate = try XCTUnwrap(item.fireAt.flatMap(ReminderTime.parseStored))
        XCTAssertGreaterThan(fireDate.timeIntervalSinceNow, 3000, "2h snooze should be well in the future")
    }

    func testUpdateChangesText() throws {
        let created = try store.add(AgentReminderInput(kind: .todo, text: "old"))
        bridge.handle(action: "update", payload: ["id": created.id, "text": "new"])
        let item = try XCTUnwrap(try store.list().first { $0.id == created.id })
        XCTAssertEqual(item.text, "new")
    }

    func testUnknownActionIsNoOp() throws {
        bridge.handle(action: "nonsense", payload: [:])
        XCTAssertTrue(try store.list().isEmpty)
    }

    // MARK: - pushState JSON round-trip + shape

    func testEncodeStateRoundTrips() throws {
        bridge.handle(action: "addReminder", payload: ["text": "Round trip", "fireAt": "30m"])
        let json = try XCTUnwrap(bridge.encodeState())
        let data = Data(json.utf8)

        // Re-decode as the same model the store uses — proves the JSON shape.
        let decoded = try JSONDecoder().decode([AgentReminder].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.text, "Round trip")

        // CamelCase keys present (fireAt, createdAt, updatedAt).
        XCTAssertTrue(json.contains("\"fireAt\""), "pushState JSON must use camelCase fireAt")
        XCTAssertTrue(json.contains("\"createdAt\""))
        XCTAssertTrue(json.contains("\"updatedAt\""))
        XCTAssertFalse(json.contains("\"fire_at\""), "must not snake_case")
    }

    func testBridgeRoundTripToDiskFile() throws {
        // Acceptance #2: add via bridge → the JSON file on disk gains the item.
        bridge.handle(action: "addTodo", payload: ["text": "On disk"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        let onDisk = try JSONDecoder().decode(
            ReminderSnapshot.self, from: Data(contentsOf: tempURL))
        XCTAssertEqual(onDisk.items.count, 1)
        XCTAssertEqual(onDisk.items.first?.text, "On disk")

        // A fresh store reading the same file sees it (cross-process equivalence).
        let reopened = ReminderStore(fileURL: tempURL)
        XCTAssertEqual(try reopened.list().count, 1)

        // Mark done via bridge → file reflects status:"done".
        let id = try XCTUnwrap(onDisk.items.first?.id)
        bridge.handle(action: "done", payload: ["id": id])
        let after = try JSONDecoder().decode(
            ReminderSnapshot.self, from: Data(contentsOf: tempURL))
        XCTAssertEqual(after.items.first?.status, .done)
    }

    func testDueCountReflectsOverdueOpenItems() throws {
        // Past fireAt, still open → counts as due.
        _ = try store.add(AgentReminderInput(kind: .reminder, text: "past", fireAt: "1s"))
        // Allow the 1s to elapse so it is in the past.
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(bridge.dueCount(), 1)

        // Future fireAt → not due.
        _ = try store.add(AgentReminderInput(kind: .reminder, text: "future", fireAt: "2h"))
        XCTAssertEqual(bridge.dueCount(), 1)
    }
}
