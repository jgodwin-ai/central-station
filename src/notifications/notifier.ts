import { execFile } from "node:child_process";
import { promisify } from "node:util";

const exec = promisify(execFile);

const cooldowns = new Map<string, number>();
const COOLDOWN_MS = 30_000;

export async function notify(taskId: string, description: string): Promise<void> {
  const lastNotified = cooldowns.get(taskId) ?? 0;
  if (Date.now() - lastNotified < COOLDOWN_MS) {
    return;
  }
  cooldowns.set(taskId, Date.now());

  const title = `Central Station: ${taskId}`;
  const message = `${description} — needs your input`;

  try {
    await exec("osascript", [
      "-e",
      `display notification "${message.replace(/"/g, '\\"')}" with title "${title.replace(/"/g, '\\"')}" sound name "Glass"`,
    ]);
  } catch {
    // Notifications may fail silently
  }
}
