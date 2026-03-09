import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import type { TaskState } from "../types.js";
import { openTerminalWindow } from "./applescript.js";

function shellEscape(str: string): string {
  return "'" + str.replace(/'/g, "'\\''") + "'";
}

export function writeHookConfig(worktreePath: string, hookServerPort: number): void {
  const claudeDir = join(worktreePath, ".claude");
  if (!existsSync(claudeDir)) {
    mkdirSync(claudeDir, { recursive: true });
  }

  const config = {
    hooks: {
      Stop: [
        {
          hooks: [
            {
              type: "command",
              command: `curl -s -X POST http://127.0.0.1:${hookServerPort}/hook/stop -H 'Content-Type: application/json' -d "$(cat)"`,
            },
          ],
        },
      ],
    },
  };

  writeFileSync(
    join(claudeDir, "settings.local.json"),
    JSON.stringify(config, null, 2)
  );
}

export function buildClaudeCommand(task: TaskState): string {
  const parts: string[] = [
    `cd ${shellEscape(task.worktreePath)}`,
    "&&",
    "claude",
    "--session-id",
    task.sessionId,
  ];

  if (task.permissionMode) {
    parts.push("--permission-mode", task.permissionMode);
  }

  parts.push(shellEscape(task.prompt));

  return parts.join(" ");
}

export async function launchTerminal(
  task: TaskState,
  hookServerPort: number
): Promise<number> {
  writeHookConfig(task.worktreePath, hookServerPort);
  const command = buildClaudeCommand(task);
  const windowId = await openTerminalWindow({
    command,
    title: `CS: ${task.id} - ${task.description}`,
  });
  return windowId;
}
