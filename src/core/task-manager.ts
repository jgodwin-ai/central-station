import { EventEmitter } from "node:events";
import type { ProjectConfig, TaskState } from "../types.js";
import { createTask, updateTaskStatus } from "./task.js";
import { HookServer, type HookEvent } from "./hook-server.js";
import {
  ensureGitRepo,
  createWorktree,
  removeWorktree,
} from "./worktree-manager.js";
import { launchTerminal } from "../terminal/launcher.js";
import { focusTerminalWindow } from "../terminal/applescript.js";
import { notify } from "../notifications/notifier.js";

export class TaskManager extends EventEmitter {
  private tasks: Map<string, TaskState> = new Map();
  private sessionToTask: Map<string, string> = new Map();
  private hookServer: HookServer;
  private config: ProjectConfig;

  constructor(config: ProjectConfig) {
    super();
    this.config = config;
    this.hookServer = new HookServer();
    this.hookServer.on("stop", (event: HookEvent) => this.handleStop(event));
  }

  getTasks(): TaskState[] {
    return Array.from(this.tasks.values());
  }

  getTask(taskId: string): TaskState | undefined {
    return this.tasks.get(taskId);
  }

  async start(): Promise<void> {
    const port = await this.hookServer.start();

    await ensureGitRepo(this.config.project);

    for (const taskConfig of this.config.tasks) {
      const worktreePath = await createWorktree(
        this.config.project,
        taskConfig.id
      );
      const task = createTask(taskConfig, worktreePath);
      this.tasks.set(task.id, task);
      this.sessionToTask.set(task.sessionId, task.id);
    }

    this.emitUpdate();

    // Launch terminals sequentially to avoid AppleScript race conditions
    for (const task of this.tasks.values()) {
      this.updateTask(task.id, "starting");
      try {
        const windowId = await launchTerminal(task, port);
        const updated = this.tasks.get(task.id)!;
        updated.terminalWindowId = windowId;
        updated.startedAt = new Date();
        this.updateTask(task.id, "working");
      } catch (err) {
        this.updateTask(
          task.id,
          "error",
          `Failed to launch: ${err instanceof Error ? err.message : String(err)}`
        );
      }
    }
  }

  async stop(): Promise<void> {
    await this.hookServer.stop();
  }

  async cleanup(): Promise<void> {
    for (const task of this.tasks.values()) {
      try {
        await removeWorktree(this.config.project, task.id);
      } catch {
        // Best effort cleanup
      }
    }
  }

  async focusTask(taskId: string): Promise<void> {
    const task = this.tasks.get(taskId);
    if (task?.terminalWindowId) {
      await focusTerminalWindow(task.terminalWindowId);
    }
  }

  private handleStop(event: HookEvent): void {
    const taskId = this.sessionToTask.get(event.sessionId);
    if (!taskId) return;

    this.updateTask(taskId, "waiting_for_input", event.lastMessage);

    const task = this.tasks.get(taskId);
    if (task) {
      notify(task.id, task.description);
    }
  }

  private updateTask(
    taskId: string,
    status: TaskState["status"],
    message?: string
  ): void {
    const task = this.tasks.get(taskId);
    if (!task) return;
    const updated = updateTaskStatus(task, status, message);
    this.tasks.set(taskId, updated);
    this.emitUpdate();
  }

  private emitUpdate(): void {
    this.emit("update");
  }
}
