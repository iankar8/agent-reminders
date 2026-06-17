export type ReminderKind = "todo" | "reminder";

export type ReminderStatus = "open" | "fired" | "done" | "cancelled" | "expired";

export type ReminderTargetKind = "thread" | "agent" | "new_agent";

export interface ReminderTarget {
  kind: ReminderTargetKind;
  id?: string;
}

export interface AgentReminder {
  id: string;
  kind: ReminderKind;
  target: ReminderTarget;
  text: string;
  triggerPrompt: string;
  status: ReminderStatus;
  fireAt?: string;
  expiresAt?: string;
  createdAt: string;
  updatedAt: string;
  firedAt?: string;
  doneAt?: string;
  cancelledAt?: string;
  note?: string;
}

export interface AgentReminderInput {
  kind?: ReminderKind;
  target?: ReminderTarget;
  text: string;
  triggerPrompt?: string;
  fireAt?: string;
  expiresAt?: string;
}

export interface AgentReminderUpdate {
  text?: string;
  kind?: ReminderKind;
  target?: ReminderTarget;
  triggerPrompt?: string;
  fireAt?: string;
  expiresAt?: string;
  note?: string;
}

export interface ReminderListFilter {
  targetId?: string;
  targetKind?: ReminderTargetKind;
  status?: ReminderStatus | "active";
  kind?: ReminderKind;
}

export interface FiredReminder {
  id: string;
  target: ReminderTarget;
  prompt: string;
  item: AgentReminder;
}

export interface ReminderSnapshot {
  version: 1;
  items: AgentReminder[];
}
