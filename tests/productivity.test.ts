import { describe, expect, it } from "vitest";
import { parseProductivityCapture, productivityPrompt } from "../src/productivity.js";

describe("productivity capture", () => {
  it("parses todo phrasing into todo items", () => {
    const parsed = parseProductivityCapture({
      utterance: "add review the PR to todo",
      defaultTarget: { kind: "agent", id: "builder" }
    });

    expect(parsed.item.kind).toBe("todo");
    expect(parsed.item.text).toBe("review the PR");
    expect(parsed.item.target).toEqual({ kind: "agent", id: "builder" });
  });

  it("uses explicit text when the user says add this to todo", () => {
    const parsed = parseProductivityCapture({
      utterance: "add this to todo",
      text: "Check the deploy logs"
    });

    expect(parsed.item.kind).toBe("todo");
    expect(parsed.item.text).toBe("Check the deploy logs");
  });

  it("parses reminder phrasing and inline relative time", () => {
    const parsed = parseProductivityCapture({
      utterance: "remind me in 10m to check the deploy"
    });

    expect(parsed.item.kind).toBe("reminder");
    expect(parsed.item.text).toBe("check the deploy");
    expect(parsed.item.fireAt).toBe("10m");
  });

  it("parses reminders list phrasing with inline time", () => {
    const parsed = parseProductivityCapture({
      utterance: "add this to reminders: check the build later"
    });

    expect(parsed.item.kind).toBe("reminder");
    expect(parsed.item.text).toBe("check the build");
    expect(parsed.item.fireAt).toBe("1h");
  });

  it("throws when no productivity intent is present", () => {
    expect(() =>
      parseProductivityCapture({
        utterance: "what should we build next"
      })
    ).toThrow("No productivity capture intent detected");
  });

  it("ships explicit proactive agent instructions", () => {
    expect(productivityPrompt()).toContain("call `productivity_capture` immediately");
  });
});
