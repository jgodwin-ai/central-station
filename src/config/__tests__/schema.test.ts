import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { TaskConfigSchema, ProjectConfigSchema } from "../schema.js";

describe("TaskConfigSchema", () => {
  it("accepts valid task config", () => {
    const result = TaskConfigSchema.safeParse({
      id: "auth-refactor",
      description: "Refactor auth module",
      prompt: "Refactor the auth module to use JWT",
    });
    assert.ok(result.success);
    assert.equal(result.data.id, "auth-refactor");
    assert.equal(result.data.worktree, true); // default
  });

  it("rejects invalid task ID", () => {
    const result = TaskConfigSchema.safeParse({
      id: "Auth Refactor!", // uppercase + space + special char
      description: "test",
      prompt: "test",
    });
    assert.ok(!result.success);
  });

  it("rejects missing description", () => {
    const result = TaskConfigSchema.safeParse({
      id: "test",
      prompt: "test",
    });
    assert.ok(!result.success);
  });

  it("accepts optional permission_mode", () => {
    const result = TaskConfigSchema.safeParse({
      id: "test",
      description: "test",
      prompt: "test",
      permission_mode: "auto",
    });
    assert.ok(result.success);
    assert.equal(result.data.permission_mode, "auto");
  });

  it("rejects invalid permission_mode", () => {
    const result = TaskConfigSchema.safeParse({
      id: "test",
      description: "test",
      prompt: "test",
      permission_mode: "invalid",
    });
    assert.ok(!result.success);
  });
});

describe("ProjectConfigSchema", () => {
  it("accepts valid project config", () => {
    const result = ProjectConfigSchema.safeParse({
      project: "/path/to/project",
      tasks: [
        { id: "task-1", description: "Do something", prompt: "Do it" },
      ],
    });
    assert.ok(result.success);
  });

  it("rejects empty tasks array", () => {
    const result = ProjectConfigSchema.safeParse({
      project: "/path/to/project",
      tasks: [],
    });
    assert.ok(!result.success);
  });

  it("rejects missing project", () => {
    const result = ProjectConfigSchema.safeParse({
      tasks: [
        { id: "task-1", description: "Do something", prompt: "Do it" },
      ],
    });
    assert.ok(!result.success);
  });
});
