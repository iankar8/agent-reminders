import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { ReminderStore } from "./store.js";

const targetSchema = z.object({
  kind: z.enum(["thread", "agent", "new_agent"]).default("thread"),
  id: z.string().optional()
});

export function createServer(store: ReminderStore): McpServer {
  const server = new McpServer({
    name: "agent-reminders",
    version: "0.1.0"
  });

  server.tool(
    "todo_add",
    "Add a lightweight ephemeral to-do for an agent or thread.",
    {
      text: z.string().min(1),
      target: targetSchema.optional(),
      dueAt: z.string().optional(),
      expiresAt: z.string().optional(),
      triggerPrompt: z.string().optional()
    },
    async ({ text, target, dueAt, expiresAt, triggerPrompt }) => {
      const item = await store.add({
        kind: "todo",
        text,
        target,
        fireAt: dueAt,
        expiresAt,
        triggerPrompt
      });
      return jsonResult(item);
    }
  );

  server.tool(
    "reminder_set",
    "Set a one-shot ephemeral reminder that fires a trigger prompt later.",
    {
      text: z.string().min(1),
      fireAt: z.string().min(1),
      target: targetSchema.optional(),
      expiresAt: z.string().optional(),
      triggerPrompt: z.string().optional()
    },
    async ({ text, fireAt, target, expiresAt, triggerPrompt }) => {
      const item = await store.add({
        kind: "reminder",
        text,
        target,
        fireAt,
        expiresAt,
        triggerPrompt
      });
      return jsonResult(item);
    }
  );

  server.tool(
    "items_list",
    "List pending or historical agent to-dos and reminders.",
    {
      kind: z.enum(["todo", "reminder"]).optional(),
      status: z.enum(["open", "fired", "done", "cancelled", "expired", "active"]).optional(),
      targetKind: z.enum(["thread", "agent", "new_agent"]).optional(),
      targetId: z.string().optional()
    },
    async (filter) => jsonResult(await store.list(filter))
  );

  server.tool(
    "todo_done",
    "Mark an agent to-do as done.",
    {
      id: z.string().min(1),
      note: z.string().optional()
    },
    async ({ id, note }) => jsonResult(await store.done(id, note))
  );

  server.tool(
    "item_cancel",
    "Cancel a to-do or reminder.",
    {
      id: z.string().min(1),
      note: z.string().optional()
    },
    async ({ id, note }) => jsonResult(await store.cancel(id, note))
  );

  server.tool(
    "item_snooze",
    "Reschedule an open to-do or reminder.",
    {
      id: z.string().min(1),
      fireAt: z.string().min(1),
      note: z.string().optional()
    },
    async ({ id, fireAt, note }) => jsonResult(await store.snooze(id, fireAt, note))
  );

  server.tool(
    "reminders_fire_due",
    "Return all due reminder trigger prompts and mark one-shot reminders fired.",
    {},
    async () => jsonResult(await store.fireDue())
  );

  server.tool(
    "items_prune",
    "Remove non-open items from the ephemeral store.",
    {},
    async () => jsonResult(await store.prune())
  );

  return server;
}

function jsonResult(value: unknown) {
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(value, null, 2)
      }
    ]
  };
}
