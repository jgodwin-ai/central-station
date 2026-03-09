import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { buildClaudeCommand, writeHookConfig } from "../launcher.js";
import type { TaskState } from "../../types.js";

function makeTask(overrides: Partial<TaskState> = {}): TaskState {
  return {
    id: "test-task",
    description: "A test",
    prompt: "Do the thing",
    sessionId: "aaaa-bbbb-cccc-dddd",
    worktreePath: "/tmp/worktrees/test-task",
    status: "pending",
    ...overrides,
  };
}

describe("buildClaudeCommand", () => {
  it("builds basic command", () => {
    const cmd = buildClaudeCommand(makeTask());
    assert.ok(cmd.includes("cd '/tmp/worktrees/test-task'"));
    assert.ok(cmd.includes("--session-id"));
    assert.ok(cmd.includes("aaaa-bbbb-cccc-dddd"));
    assert.ok(cmd.includes("'Do the thing'"));
  });

  it("includes permission mode when set", () => {
    const cmd = buildClaudeCommand(makeTask({ permissionMode: "auto" }));
    assert.ok(cmd.includes("--permission-mode auto"));
  });

  it("escapes single quotes in prompt", () => {
    const cmd = buildClaudeCommand(
      makeTask({ prompt: "Fix the user's auth bug" })
    );
    assert.ok(cmd.includes("'Fix the user'\\''s auth bug'"));
  });
});

describe("writeHookConfig", () => {
  it("writes settings.local.json with Stop hook", () => {
    const tmpDir = mkdtempSync(join(tmpdir(), "cs-test-"));
    try {
      writeHookConfig(tmpDir, 12345);
      const configPath = join(tmpDir, ".claude", "settings.local.json");
      const config = JSON.parse(readFileSync(configPath, "utf-8"));

      assert.ok(config.hooks);
      assert.ok(config.hooks.Stop);
      assert.ok(config.hooks.Stop[0].hooks[0].command.includes("12345"));
      assert.ok(config.hooks.Stop[0].hooks[0].type === "command");
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});
