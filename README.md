# agent-reminders

Lightweight, ephemeral to-dos and reminders for AI agents.

This is intentionally not a task manager. It is a tiny queue agents can use to leave short-lived breadcrumbs for themselves:

- "check this build in 10 minutes"
- "remember to mark this PR review done"
- "wake this thread later with a trigger prompt"

Items live in a local JSON file, expire by default, and can be pruned after they are done, cancelled, fired, or expired.

## Install

```sh
npm install
npm run build
```

Run as an MCP server over stdio:

```sh
npx agent-reminders mcp
```

For local development:

```sh
npm run dev
```

By default, data is written to `~/.agent-reminders/reminders.json`. Override it with:

```sh
AGENT_REMINDERS_STORE=/tmp/agent-reminders.json npx agent-reminders
```

## Delivery Model

The package does not assume it knows how to message your host app. It returns trigger prompts with a tiny target envelope, and your host adapter decides how to deliver them to a thread, named agent, or fresh agent.

There are three ways to consume due reminders:

1. Call the MCP tool `reminders_fire_due`.
2. Run a one-shot CLI check:

```sh
agent-reminders fire-due
```

3. Run a tiny webhook daemon:

```sh
agent-reminders daemon --webhook http://127.0.0.1:4242/agent-reminders --interval-ms 60000
```

The webhook receives the same JSON shape as `reminders_fire_due`.

You can also embed the store and scheduler directly:

```ts
import { ReminderStore, fireAndDispatchDue } from "agent-reminders";

const store = new ReminderStore("/tmp/agent-reminders.json");

await fireAndDispatchDue(store, async (reminder) => {
  await sendPromptToThread(reminder.target.id, reminder.prompt);
});
```

## Tools

### `todo_add`

Add a lightweight open item.

```json
{
  "text": "Check whether the deploy finished",
  "target": { "kind": "thread", "id": "current" },
  "dueAt": "10m"
}
```

### `reminder_set`

Set a one-shot reminder.

```json
{
  "text": "Review test output",
  "fireAt": "2026-06-15T22:00:00-05:00",
  "target": { "kind": "agent", "id": "builder" }
}
```

### `reminders_fire_due`

Returns all due trigger prompts. One-shot reminders become `fired`; to-dos remain `open` until marked done.

```json
[
  {
    "id": "...",
    "target": { "kind": "thread", "id": "current" },
    "prompt": "Reminder: this agent to-do is due..."
  }
]
```

### Other tools

- `items_list`
- `todo_done`
- `item_snooze`
- `item_cancel`
- `items_prune`

## Time Values

`fireAt`, `dueAt`, and `expiresAt` accept either ISO-style date strings or simple relative values:

- `30s`
- `10m`
- `2h`
- `1d`

Open items expire after `24h` unless you provide a different `expiresAt`.

## Target Model

Targets are intentionally small:

```json
{ "kind": "thread", "id": "current" }
{ "kind": "agent", "id": "builder" }
{ "kind": "new_agent" }
```

The host decides what to do with a fired prompt. This package only stores the item and returns the trigger prompt when it is due.

## Development

```sh
npm test
npm run typecheck
npm run build
```

## License

MIT
