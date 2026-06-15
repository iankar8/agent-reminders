#!/usr/bin/env node
import { homedir } from "node:os";
import { join } from "node:path";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { dispatchToWebhook, startReminderScheduler } from "./dispatcher.js";
import { ReminderStore } from "./store.js";
import { createServer } from "./server.js";

const storePath =
  process.env.AGENT_REMINDERS_STORE ??
  join(homedir(), ".agent-reminders", "reminders.json");

const store = new ReminderStore(storePath);
const command = process.argv[2] ?? "mcp";

if (command === "mcp") {
  const server = createServer(store);
  const transport = new StdioServerTransport();
  await server.connect(transport);
} else if (command === "fire-due") {
  const fired = await store.fireDue();
  process.stdout.write(`${JSON.stringify(fired, null, 2)}\n`);
} else if (command === "daemon") {
  const webhook = readFlag("--webhook");
  const intervalMs = Number(readFlag("--interval-ms") ?? "60000");

  if (!webhook) {
    throw new Error("daemon requires --webhook <url>");
  }

  startReminderScheduler(
    store,
    (reminder) => dispatchToWebhook(webhook, reminder),
    {
      intervalMs,
      onError: (error) => {
        process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
      }
    }
  );
} else {
  process.stdout.write(`agent-reminders

Usage:
  agent-reminders mcp
  agent-reminders fire-due
  agent-reminders daemon --webhook <url> [--interval-ms 60000]

Environment:
  AGENT_REMINDERS_STORE=/path/to/reminders.json
`);
}

function readFlag(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  if (index === -1) {
    return undefined;
  }
  return process.argv[index + 1];
}
