import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const exec = promisify(execFile);

export async function ensureGitRepo(projectPath: string): Promise<void> {
  try {
    await exec("git", ["-C", projectPath, "rev-parse", "--git-dir"]);
  } catch {
    await exec("git", ["-C", projectPath, "init"]);
    // Create an initial commit so worktrees can branch from something
    await exec("git", ["-C", projectPath, "commit", "--allow-empty", "-m", "initial commit"]);
  }
}

export async function createWorktree(
  projectPath: string,
  taskId: string
): Promise<string> {
  const worktreesDir = join(projectPath, ".worktrees");
  if (!existsSync(worktreesDir)) {
    mkdirSync(worktreesDir, { recursive: true });
  }

  const worktreePath = join(worktreesDir, taskId);
  const branchName = `cs/${taskId}`;

  if (existsSync(worktreePath)) {
    // Already exists, just return the path
    return worktreePath;
  }

  await exec("git", [
    "-C",
    projectPath,
    "worktree",
    "add",
    "-b",
    branchName,
    worktreePath,
  ]);

  return worktreePath;
}

export async function removeWorktree(
  projectPath: string,
  taskId: string
): Promise<void> {
  const worktreePath = join(projectPath, ".worktrees", taskId);
  try {
    await exec("git", ["-C", projectPath, "worktree", "remove", worktreePath, "--force"]);
  } catch {
    // Worktree may already be removed
  }
}

export async function getWorktreeDiff(worktreePath: string): Promise<string> {
  try {
    const { stdout: stat } = await exec("git", [
      "-C", worktreePath, "diff", "HEAD", "--stat",
    ]);
    const { stdout: diff } = await exec("git", [
      "-C", worktreePath, "diff", "HEAD",
    ]);

    if (!stat.trim() && !diff.trim()) {
      // Also check for untracked files
      const { stdout: untracked } = await exec("git", [
        "-C", worktreePath, "status", "--short",
      ]);
      if (untracked.trim()) {
        return `Untracked/new files:\n${untracked}`;
      }
      return "No changes yet.";
    }

    return stat + "\n" + diff;
  } catch {
    return "Unable to get diff.";
  }
}
