import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { createTask, updateTaskStatus, formatElapsed } from "../task.js";
import type { TaskConfig } from "../../types.js";

const sampleConfig: TaskConfig = {
  id: "test-task",
  description: "A test task",
  prompt: "Do something",
};

describe("createTask", () => {
  it("creates a task with pending status", () => {
    const task = createTask(sampleConfig, "/tmp/worktree");
    assert.equal(task.id, "test-task");
    assert.equal(task.status, "pending");
    assert.equal(task.worktreePath, "/tmp/worktree");
    assert.ok(task.sessionId.length > 0);
  });

  it("generates unique session IDs", () => {
    const task1 = createTask(sampleConfig, "/tmp/wt1");
    const task2 = createTask(sampleConfig, "/tmp/wt2");
    assert.notEqual(task1.sessionId, task2.sessionId);
  });
});

describe("updateTaskStatus", () => {
  it("updates status and sets lastActivityAt", () => {
    const task = createTask(sampleConfig, "/tmp/worktree");
    const updated = updateTaskStatus(task, "working");
    assert.equal(updated.status, "working");
    assert.ok(updated.lastActivityAt instanceof Date);
  });

  it("updates message when provided", () => {
    const task = createTask(sampleConfig, "/tmp/worktree");
    const updated = updateTaskStatus(task, "waiting_for_input", "Need help");
    assert.equal(updated.lastMessage, "Need help");
  });

  it("preserves existing message when not provided", () => {
    const task = createTask(sampleConfig, "/tmp/worktree");
    const withMsg = updateTaskStatus(task, "working", "Doing stuff");
    const updated = updateTaskStatus(withMsg, "waiting_for_input");
    assert.equal(updated.lastMessage, "Doing stuff");
  });
});

describe("formatElapsed", () => {
  it("returns -- for tasks without startedAt", () => {
    const task = createTask(sampleConfig, "/tmp/worktree");
    assert.equal(formatElapsed(task), "--");
  });

  it("formats elapsed time correctly", () => {
    const task = createTask(sampleConfig, "/tmp/worktree");
    task.startedAt = new Date(Date.now() - 125_000); // 2m 5s ago
    const result = formatElapsed(task);
    assert.equal(result, "2m 05s");
  });
});
