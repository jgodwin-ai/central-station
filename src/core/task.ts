import { v4 as uuidv4 } from "uuid";
import type { TaskConfig, TaskState, TaskStatus } from "../types.js";

export function createTask(config: TaskConfig, worktreePath: string): TaskState {
  return {
    id: config.id,
    description: config.description,
    prompt: config.prompt,
    sessionId: uuidv4(),
    worktreePath,
    status: "pending",
    permissionMode: config.permission_mode,
  };
}

export function updateTaskStatus(
  task: TaskState,
  status: TaskStatus,
  message?: string
): TaskState {
  return {
    ...task,
    status,
    lastActivityAt: new Date(),
    ...(message !== undefined ? { lastMessage: message } : {}),
  };
}

export function formatElapsed(task: TaskState): string {
  if (!task.startedAt) return "--";
  const elapsed = Math.floor((Date.now() - task.startedAt.getTime()) / 1000);
  const m = Math.floor(elapsed / 60);
  const s = elapsed % 60;
  return `${m}m ${s.toString().padStart(2, "0")}s`;
}
