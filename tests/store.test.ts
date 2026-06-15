import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { fireAndDispatchDue } from "../src/dispatcher.js";
import { ReminderStore } from "../src/store.js";

let dir: string;
let now: Date;
let store: ReminderStore;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "agent-reminders-"));
  now = new Date("2026-06-15T12:00:00.000Z");
  store = new ReminderStore(join(dir, "store.json"), () => now);
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("ReminderStore", () => {
  it("adds agent todos and lists active items", async () => {
    const item = await store.add({
      kind: "todo",
      text: "Check the deploy",
      target: { kind: "agent", id: "builder" }
    });

    const items = await store.list({ status: "active", targetId: "builder" });

    expect(item.kind).toBe("todo");
    expect(item.status).toBe("open");
    expect(items).toHaveLength(1);
    expect(items[0]?.text).toBe("Check the deploy");
  });

  it("fires due reminders and marks one-shot reminders fired", async () => {
    const item = await store.add({
      kind: "reminder",
      text: "Check tests",
      fireAt: "5m"
    });

    now = new Date("2026-06-15T12:04:00.000Z");
    expect(await store.fireDue()).toHaveLength(0);

    now = new Date("2026-06-15T12:05:00.000Z");
    const fired = await store.fireDue();
    const listed = await store.list();

    expect(fired).toHaveLength(1);
    expect(fired[0]?.id).toBe(item.id);
    expect(fired[0]?.prompt).toContain("Reminder id:");
    expect(listed[0]?.status).toBe("fired");
  });

  it("keeps due todos open until they are marked done", async () => {
    const item = await store.add({
      kind: "todo",
      text: "Review the PR",
      fireAt: "1m"
    });

    now = new Date("2026-06-15T12:01:00.000Z");
    const fired = await store.fireDue();
    const repeated = await store.fireDue();
    const active = await store.list({ status: "active" });

    expect(fired).toHaveLength(1);
    expect(repeated).toHaveLength(0);
    expect(active).toHaveLength(1);

    await store.done(item.id, "Reviewed");
    expect(await store.list({ status: "active" })).toHaveLength(0);
  });

  it("snoozes fired reminders back to open", async () => {
    const item = await store.add({
      kind: "reminder",
      text: "Look again",
      fireAt: "1m"
    });

    now = new Date("2026-06-15T12:01:00.000Z");
    await store.fireDue();
    const snoozed = await store.snooze(item.id, "10m", "Waiting");

    expect(snoozed.status).toBe("open");
    expect(snoozed.note).toBe("Waiting");
    expect(snoozed.fireAt).toBe("2026-06-15T12:11:00.000Z");
  });

  it("expires forgotten open items and prunes closed items", async () => {
    await store.add({
      kind: "todo",
      text: "Temporary thought",
      expiresAt: "1m"
    });

    now = new Date("2026-06-15T12:02:00.000Z");
    const expired = await store.list({ status: "expired" });
    const pruned = await store.prune();

    expect(expired).toHaveLength(1);
    expect(pruned.removed).toBe(1);
    expect(await store.list()).toHaveLength(0);
  });

  it("dispatches due reminder prompts through a host adapter", async () => {
    await store.add({
      kind: "reminder",
      text: "Ping the thread",
      fireAt: "1m",
      target: { kind: "thread", id: "thread-1" }
    });

    now = new Date("2026-06-15T12:01:00.000Z");
    const delivered: string[] = [];
    const fired = await fireAndDispatchDue(store, (reminder) => {
      delivered.push(`${reminder.target.kind}:${reminder.target.id}:${reminder.prompt}`);
    });

    expect(fired).toHaveLength(1);
    expect(delivered[0]).toContain("thread:thread-1:Reminder:");
  });

  it("snoozes a reminder for retry when host dispatch fails", async () => {
    const item = await store.add({
      kind: "reminder",
      text: "Retry me",
      fireAt: "1m"
    });

    now = new Date("2026-06-15T12:01:00.000Z");

    await expect(
      fireAndDispatchDue(store, () => {
        throw new Error("host unavailable");
      })
    ).rejects.toThrow("host unavailable");

    const active = await store.list({ status: "active" });

    expect(active).toHaveLength(1);
    expect(active[0]?.id).toBe(item.id);
    expect(active[0]?.note).toContain("Dispatch failed");
    expect(active[0]?.fireAt).toBe("2026-06-15T12:02:00.000Z");
  });
});
