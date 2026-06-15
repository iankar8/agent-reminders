import type {
  AgentReminder,
  AgentReminderInput,
  ReminderTarget,
  ReminderTargetKind
} from "./types.js";
import type { ReminderStore } from "./store.js";

export interface ProductivityCaptureInput {
  utterance: string;
  defaultTarget?: ReminderTarget;
  target?: ReminderTarget;
  text?: string;
  fireAt?: string;
  expiresAt?: string;
  triggerPrompt?: string;
}

export interface ProductivityCaptureResult {
  intent: "todo" | "reminder";
  item: AgentReminder;
  parsed: {
    text: string;
    fireAt?: string;
    target: ReminderTarget;
  };
}

const TODO_PATTERNS = [
  /^(?:please\s+)?(?:add|put|save|capture)\s+(?:this\s+)?(?:to|on|in)\s+(?:my\s+|the\s+)?(?:to-?do|todo|task list|tasks?)[:\s-]*(?<text>.*)$/i,
  /^(?:please\s+)?(?:add|put|save|capture)\s+(?<text>.+?)\s+(?:to|on|in)\s+(?:my\s+|the\s+)?(?:to-?do|todo|task list|tasks?)\.?$/i,
  /^(?:to-?do|todo|task)[:\s-]+(?<text>.+)$/i
];

const REMINDER_PATTERNS = [
  /^(?:please\s+)?(?:add|set|save|create)\s+(?:this\s+)?(?:to|as|in)\s+(?:my\s+|the\s+)?reminders?[:\s-]*(?<text>.*)$/i,
  /^(?:please\s+)?remind\s+(?:me|this\s+agent|the\s+agent)?\s*(?<time>later|tomorrow|tonight|today|in\s+\d+\s*(?:s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)|at\s+.+?|on\s+.+?)?\s*(?:to|that|about)?\s*(?<text>.*)$/i,
  /^(?:reminder|remind)[:\s-]+(?<text>.+)$/i
];

const INLINE_TIME_RE = /\b(?<time>in\s+\d+\s*(?:s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)|tomorrow|tonight|today|later)\b/i;

export async function captureProductivityItem(
  store: ReminderStore,
  input: ProductivityCaptureInput
): Promise<ProductivityCaptureResult> {
  const parsed = parseProductivityCapture(input);
  const item = await store.add(parsed.item);
  return {
    intent: parsed.item.kind === "reminder" ? "reminder" : "todo",
    item,
    parsed: {
      text: parsed.item.text,
      fireAt: parsed.item.fireAt,
      target: parsed.item.target ?? defaultTarget(input)
    }
  };
}

export function parseProductivityCapture(input: ProductivityCaptureInput): { item: AgentReminderInput } {
  const utterance = input.utterance.trim();
  if (!utterance) {
    throw new Error("Cannot capture an empty productivity item");
  }

  const reminder = matchIntent(utterance, REMINDER_PATTERNS);
  if (reminder) {
    const text = cleanText(input.text ?? reminder.text);
    const inlineTime = reminder.time ?? findInlineTime(text);
    const fireAt = input.fireAt ?? normalizeCaptureTime(inlineTime);
    return {
      item: {
        kind: "reminder",
        text: stripInlineTime(text),
        target: input.target ?? defaultTarget(input),
        fireAt,
        expiresAt: input.expiresAt,
        triggerPrompt: input.triggerPrompt
      }
    };
  }

  const todo = matchIntent(utterance, TODO_PATTERNS);
  if (todo) {
    const text = cleanText(input.text ?? todo.text);
    const inlineTime = findInlineTime(text);
    return {
      item: {
        kind: "todo",
        text: stripInlineTime(text),
        target: input.target ?? defaultTarget(input),
        fireAt: input.fireAt ?? normalizeCaptureTime(inlineTime),
        expiresAt: input.expiresAt,
        triggerPrompt: input.triggerPrompt
      }
    };
  }

  throw new Error("No productivity capture intent detected");
}

export function productivityPrompt(): string {
  return [
    "You have access to agent-reminders productivity tools.",
    "",
    "Be proactive:",
    "- If the user says \"add this to todo\", \"put that on my task list\", or similar, call `productivity_capture` immediately.",
    "- If the user says \"remind me\", \"add this to reminders\", or similar, call `productivity_capture` immediately.",
    "- Do not ask for confirmation unless the item text or reminder time is genuinely missing.",
    "- Prefer `productivity_capture` over manually parsing the phrase yourself.",
    "- Use target `{ kind: \"thread\", id: \"current\" }` unless the user names another agent/thread.",
    "",
    "After capture, respond with one short receipt: what was captured and, for reminders, when it will fire."
  ].join("\n");
}

function matchIntent(
  utterance: string,
  patterns: RegExp[]
): { text: string; time?: string } | undefined {
  for (const pattern of patterns) {
    const match = pattern.exec(utterance);
    const text = match?.groups?.text?.trim();
    if (match && text !== undefined) {
      return {
        text,
        time: match.groups?.time?.trim()
      };
    }
  }
  return undefined;
}

function defaultTarget(input: ProductivityCaptureInput): ReminderTarget {
  return input.defaultTarget ?? { kind: "thread", id: "current" };
}

function cleanText(text: string | undefined): string {
  const clean = text?.trim().replace(/^["']|["']$/g, "").replace(/[.?!]\s*$/g, "");
  if (!clean) {
    throw new Error("Captured productivity item is missing text");
  }
  return clean;
}

function findInlineTime(text: string): string | undefined {
  return INLINE_TIME_RE.exec(text)?.groups?.time;
}

function stripInlineTime(text: string): string {
  return text.replace(INLINE_TIME_RE, "").replace(/\s+/g, " ").trim();
}

function normalizeCaptureTime(value: string | undefined): string | undefined {
  if (!value) {
    return undefined;
  }

  const trimmed = value.trim().toLowerCase();
  if (trimmed === "later") {
    return "1h";
  }
  if (trimmed === "today") {
    return "4h";
  }
  if (trimmed === "tonight") {
    return "8h";
  }
  if (trimmed === "tomorrow") {
    return "1d";
  }
  if (trimmed.startsWith("in ")) {
    return trimmed.slice(3);
  }
  return value;
}

export function parseTargetShortcut(value: string | undefined): ReminderTarget | undefined {
  if (!value) {
    return undefined;
  }
  const [kind, id] = value.split(":", 2);
  if (!isTargetKind(kind)) {
    throw new Error(`Invalid target shortcut: ${value}`);
  }
  return { kind, id };
}

function isTargetKind(value: string): value is ReminderTargetKind {
  return value === "thread" || value === "agent" || value === "new_agent";
}
