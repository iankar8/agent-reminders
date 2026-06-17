import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { getDefaultEnvironment, StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { afterEach, describe, expect, it } from "vitest";

let dir: string | undefined;

afterEach(async () => {
  if (dir) {
    await rm(dir, { recursive: true, force: true });
    dir = undefined;
  }
});

describe("MCP stdio server", () => {
  it("adds todos and fires due reminders through MCP tools", async () => {
    dir = await mkdtemp(join(tmpdir(), "agent-reminders-mcp-"));
    const client = new Client({ name: "agent-reminders-test", version: "0.1.0" });
    const transport = new StdioClientTransport({
      command: process.execPath,
      args: ["--import", "tsx", "src/index.ts", "mcp"],
      cwd: process.cwd(),
      env: {
        ...getDefaultEnvironment(),
        AGENT_REMINDERS_STORE: join(dir, "store.json")
      },
      stderr: "pipe"
    });

    try {
      await client.connect(transport);

      const prompts = await client.listPrompts();
      expect(prompts.prompts.map((prompt) => prompt.name)).toContain("productivity_mode");

      const productivityPrompt = await client.getPrompt({ name: "productivity_mode" });
      expect(productivityPrompt.messages[0]?.content).toMatchObject({
        type: "text",
        text: expect.stringContaining("productivity_capture")
      });

      const todoResult = await client.callTool({
        name: "todo_add",
        arguments: {
          text: "Verify MCP path",
          target: { kind: "thread", id: "clean-thread" }
        }
      });
      const todo = parseTextResult(todoResult);

      expect(todo.kind).toBe("todo");
      expect(todo.target.id).toBe("clean-thread");

      const updatedResult = await client.callTool({
        name: "item_update",
        arguments: { id: todo.id, text: "Verify MCP path (edited)" }
      });
      const updatedTodo = parseTextResult(updatedResult);

      expect(updatedTodo.text).toBe("Verify MCP path (edited)");
      expect(updatedTodo.status).toBe("open");
      expect(updatedTodo.target.id).toBe("clean-thread");

      await client.callTool({
        name: "reminder_set",
        arguments: {
          text: "Wake clean thread",
          fireAt: new Date(Date.now() - 1000).toISOString(),
          target: { kind: "thread", id: "clean-thread" }
        }
      });

      const firedResult = await client.callTool({
        name: "reminders_fire_due",
        arguments: {}
      });
      const fired = parseTextResult(firedResult);

      expect(fired).toHaveLength(1);
      expect(fired[0].target.id).toBe("clean-thread");
      expect(fired[0].prompt).toContain("Wake clean thread");

      const captureResult = await client.callTool({
        name: "productivity_capture",
        arguments: {
          utterance: "add this to todo",
          text: "Review proactive capture",
          defaultTarget: { kind: "thread", id: "clean-thread" }
        }
      });
      const captured = parseTextResult(captureResult);

      expect(captured.intent).toBe("todo");
      expect(captured.item.text).toBe("Review proactive capture");
      expect(captured.item.target.id).toBe("clean-thread");
    } finally {
      await client.close();
    }
  });
});

function parseTextResult(result: { content?: Array<{ type: string; text?: string }> }): any {
  const text = result.content?.find((item) => item.type === "text")?.text;
  if (!text) {
    throw new Error("Expected text MCP result");
  }
  return JSON.parse(text);
}
