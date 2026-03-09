export type TaskStatus =
  | "pending"
  | "starting"
  | "working"
  | "waiting_for_input"
  | "completed"
  | "error";

export interface TaskState {
  id: string;
  description: string;
  prompt: string;
  sessionId: string;
  worktreePath: string;
  terminalWindowId?: number;
  status: TaskStatus;
  startedAt?: Date;
  lastActivityAt?: Date;
  lastMessage?: string;
  permissionMode?: string;
}

export interface StopHookPayload {
  session_id: string;
  transcript_path: string;
  cwd: string;
  permission_mode: string;
  hook_event_name: "Stop";
  stop_hook_active: boolean;
  last_assistant_message: string;
}

export interface TaskConfig {
  id: string;
  description: string;
  prompt: string;
  worktree?: boolean;
  permission_mode?: string;
}

export interface ProjectConfig {
  project: string;
  tasks: TaskConfig[];
}
