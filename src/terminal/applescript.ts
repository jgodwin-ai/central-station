import { execFile } from "node:child_process";
import { promisify } from "node:util";

const exec = promisify(execFile);

function escapeForAppleScript(str: string): string {
  return str.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

export async function openTerminalWindow(params: {
  command: string;
  title: string;
}): Promise<number> {
  const escapedCmd = escapeForAppleScript(params.command);
  const escapedTitle = escapeForAppleScript(params.title);

  const script = `
    tell application "Terminal"
      activate
      do script "${escapedCmd}"
      set custom title of tab 1 of front window to "${escapedTitle}"
      set winId to id of front window
      return winId
    end tell
  `;

  const { stdout } = await exec("osascript", ["-e", script]);
  return parseInt(stdout.trim(), 10);
}

export async function focusTerminalWindow(windowId: number): Promise<void> {
  const script = `
    tell application "Terminal"
      activate
      set index of window id ${windowId} to 1
    end tell
  `;
  try {
    await exec("osascript", ["-e", script]);
  } catch {
    // Window may have been closed
  }
}

export async function isTerminalWindowOpen(windowId: number): Promise<boolean> {
  const script = `
    tell application "Terminal"
      try
        set w to window id ${windowId}
        return true
      on error
        return false
      end try
    end tell
  `;
  try {
    const { stdout } = await exec("osascript", ["-e", script]);
    return stdout.trim() === "true";
  } catch {
    return false;
  }
}
