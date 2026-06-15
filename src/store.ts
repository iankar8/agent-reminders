import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { randomUUID } from "node:crypto";
import type {
  AgentReminder,
  AgentReminderInput,
  FiredReminder,
  ReminderListFilter,
  ReminderSnapshot
} from "./types.js";
import { isDue, parseTime, type Clock } from "./time.js";

const DEFAULT_TTL = "24h";

export class ReminderStore {
  private readonly filePath: string;
  private readonly clock: Clock;

  constructor(filePath: string, clock: Clock = () => new Date()) {
    this.filePath = filePath;
    this.clock = clock;
  }

  async add(input: AgentReminderInput): Promise<AgentReminder> {
    const snapshot = await this.read();
    const now = this.clock();
    const nowIso = now.toISOString();
    const kind = input.kind ?? (input.fireAt ? "reminder" : "todo");
    const fireAt = parseTime(input.fireAt, now);
    const expiresAt = parseTime(input.expiresAt ?? DEFAULT_TTL, now);
    const item: AgentReminder = {
      id: randomUUID(),
      kind,
      target: input.target ?? { kind: "thread", id: "current" },
      text: input.text,
      triggerPrompt: input.triggerPrompt ?? defaultTriggerPrompt(kind, input.text),
      status: "open",
      fireAt,
      expiresAt,
      createdAt: nowIso,
      updatedAt: nowIso
    };

    snapshot.items.push(item);
    await this.write(snapshot);
    return item;
  }

  async list(filter: ReminderListFilter = {}): Promise<AgentReminder[]> {
    const snapshot = await this.read();
    const now = this.clock();
    const items = snapshot.items.map((item) => normalizeExpired(item, now));
    return items.filter((item) => matchesFilter(item, filter));
  }

  async done(id: string, note?: string): Promise<AgentReminder> {
    return this.updateStatus(id, "done", { note, doneAt: this.clock().toISOString() });
  }

  async cancel(id: string, note?: string): Promise<AgentReminder> {
    return this.updateStatus(id, "cancelled", { note, cancelledAt: this.clock().toISOString() });
  }

  async snooze(id: string, fireAt: string, note?: string): Promise<AgentReminder> {
    const snapshot = await this.read();
    const now = this.clock();
    const item = findItem(snapshot, id);
    item.status = "open";
    item.fireAt = parseTime(fireAt, now);
    item.updatedAt = now.toISOString();
    item.note = note ?? item.note;
    delete item.firedAt;
    await this.write(snapshot);
    return item;
  }

  async fireDue(): Promise<FiredReminder[]> {
    const snapshot = await this.read();
    const now = this.clock();
    const fired: FiredReminder[] = [];

    for (const item of snapshot.items) {
      const normalized = normalizeExpired(item, now);
      Object.assign(item, normalized);

      if (item.status !== "open" || !isDue(item.fireAt, now) || alreadyFiredForDueTime(item)) {
        continue;
      }

      const prompt = buildTriggerPrompt(item);
      item.firedAt = now.toISOString();
      item.updatedAt = now.toISOString();
      item.status = item.kind === "reminder" ? "fired" : "open";
      fired.push({ id: item.id, target: item.target, prompt, item: { ...item } });
    }

    await this.write(snapshot);
    return fired;
  }

  async prune(): Promise<{ removed: number }> {
    const snapshot = await this.read();
    const before = snapshot.items.length;
    const now = this.clock();
    snapshot.items = snapshot.items
      .map((item) => normalizeExpired(item, now))
      .filter((item) => item.status === "open");
    await this.write(snapshot);
    return { removed: before - snapshot.items.length };
  }

  private async updateStatus(
    id: string,
    status: "done" | "cancelled",
    extra: Partial<AgentReminder>
  ): Promise<AgentReminder> {
    const snapshot = await this.read();
    const item = findItem(snapshot, id);
    item.status = status;
    item.updatedAt = this.clock().toISOString();
    Object.assign(item, extra);
    await this.write(snapshot);
    return item;
  }

  private async read(): Promise<ReminderSnapshot> {
    try {
      const raw = await readFile(this.filePath, "utf8");
      const parsed = JSON.parse(raw) as ReminderSnapshot;
      if (parsed.version !== 1 || !Array.isArray(parsed.items)) {
        throw new Error("Invalid reminder snapshot");
      }
      return parsed;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        return { version: 1, items: [] };
      }
      throw error;
    }
  }

  private async write(snapshot: ReminderSnapshot): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    const tempPath = `${this.filePath}.${process.pid}.tmp`;
    await writeFile(tempPath, `${JSON.stringify(snapshot, null, 2)}\n`, "utf8");
    await rename(tempPath, this.filePath);
  }
}

function findItem(snapshot: ReminderSnapshot, id: string): AgentReminder {
  const item = snapshot.items.find((candidate) => candidate.id === id);
  if (!item) {
    throw new Error(`Reminder not found: ${id}`);
  }
  return item;
}

function matchesFilter(item: AgentReminder, filter: ReminderListFilter): boolean {
  if (filter.kind && item.kind !== filter.kind) {
    return false;
  }
  if (filter.targetKind && item.target.kind !== filter.targetKind) {
    return false;
  }
  if (filter.targetId && item.target.id !== filter.targetId) {
    return false;
  }
  if (filter.status === "active") {
    return item.status === "open";
  }
  if (filter.status && item.status !== filter.status) {
    return false;
  }
  return true;
}

function normalizeExpired(item: AgentReminder, now: Date): AgentReminder {
  if (item.status === "open" && isDue(item.expiresAt, now)) {
    return { ...item, status: "expired", updatedAt: now.toISOString() };
  }
  return item;
}

function alreadyFiredForDueTime(item: AgentReminder): boolean {
  if (!item.firedAt || !item.fireAt) {
    return false;
  }
  return new Date(item.firedAt).getTime() >= new Date(item.fireAt).getTime();
}

function defaultTriggerPrompt(kind: string, text: string): string {
  if (kind === "todo") {
    return `Reminder: this agent to-do is due.\n\nTo-do: ${text}\n\nAct on it if possible. Mark it done if complete, or snooze it with a short reason.`;
  }
  return `Reminder: ${text}`;
}

function buildTriggerPrompt(item: AgentReminder): string {
  const lines = [
    item.triggerPrompt,
    "",
    `Reminder id: ${item.id}`,
    `Kind: ${item.kind}`,
    `Target: ${item.target.kind}${item.target.id ? `:${item.target.id}` : ""}`
  ];

  return lines.join("\n");
}
