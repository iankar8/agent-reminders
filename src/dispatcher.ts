import type { ReminderStore } from "./store.js";
import type { FiredReminder } from "./types.js";

export type ReminderDispatcher = (reminder: FiredReminder) => Promise<void> | void;

export interface SchedulerOptions {
  intervalMs?: number;
  unref?: boolean;
  signal?: AbortSignal;
  onError?: (error: unknown) => void;
}

export async function fireAndDispatchDue(
  store: ReminderStore,
  dispatch: ReminderDispatcher
): Promise<FiredReminder[]> {
  const fired = await store.fireDue();
  for (const reminder of fired) {
    try {
      await dispatch(reminder);
    } catch (error) {
      await store.snooze(
        reminder.id,
        "1m",
        `Dispatch failed: ${error instanceof Error ? error.message : String(error)}`
      );
      throw error;
    }
  }
  return fired;
}

export function startReminderScheduler(
  store: ReminderStore,
  dispatch: ReminderDispatcher,
  options: SchedulerOptions = {}
): NodeJS.Timeout {
  const intervalMs = options.intervalMs ?? 60_000;
  const tick = async () => {
    try {
      await fireAndDispatchDue(store, dispatch);
    } catch (error) {
      options.onError?.(error);
    }
  };

  const timer = setInterval(tick, intervalMs);
  if (options.unref) {
    timer.unref?.();
  }
  options.signal?.addEventListener("abort", () => clearInterval(timer), { once: true });
  void tick();
  return timer;
}

export async function dispatchToWebhook(url: string, reminder: FiredReminder): Promise<void> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(reminder)
  });

  if (!response.ok) {
    throw new Error(`Reminder webhook failed: ${response.status} ${response.statusText}`);
  }
}
