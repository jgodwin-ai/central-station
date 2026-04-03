# Repo-First Task Workflow

## Problem

The current "Add New Task" workflow requires filling out a modal form (AddTaskSheet) with 6+ fields: description, prompt, permission mode, worktree toggle, directory picker, and local/remote toggle. This creates unnecessary friction. Users should be able to start working immediately.

## Design

### Core Concept

Repos are first-class sidebar items. Users add repos they want to work in, then click "+" next to a repo to instantly create a task. Each task auto-creates a git worktree and launches a terminal. No modal, no form fields. The user just starts typing their prompt directly.

### Data Model

**New: `Repo` model**
- `id`: UUID
- `path`: String (absolute path to git repo root)
- `name`: String (derived from folder name, display only)
- Persisted to `~/.claude/central-station-repos.json` alongside a global task counter

**`AppTask` changes**
- Remove fields: `prompt`, `permissionMode`, `remoteAlias`, `sshHost`, `isResume`
- `id` format: `YYYY-MM-DD-task-N` where N is a globally incrementing counter (e.g. `2026-04-03-task-1`)
- `description`: starts empty, auto-populated after first prompt via LLM summarization
- `projectPath`: always inherited from parent Repo
- `worktreePath`: always `.worktrees/{id}` under the repo — no opt-out
- Branch name: `cs/{id}` (e.g. `cs/2026-04-03-task-1`)

**Remove entirely**
- `RemoteConfig` model and `RemoteStore` service
- `RemoteShell` service
- All remote worktree/SSH code paths
- `TaskConfig` model (config file loading from tasks.yaml/json)
- `AddTaskSheet` view

### Task ID Generation

A global counter persists across app restarts. Each new task gets the next counter value. The task ID combines today's date with the counter: `2026-04-03-task-1`, `2026-04-03-task-2`, then the next day `2026-04-04-task-3`. The counter never resets.

### UI Changes

**Sidebar (TaskListView)**
- Top-level items are repos (folder icon + repo name + "+" button)
- Tasks nested under their parent repo
- Task rows: status icon, task ID, description (if available)
- "Add Repo" button at top of sidebar opens native macOS folder picker (NSOpenPanel)
- Sidebar accepts drag-and-drop of folders to add repos
- Validate dropped/selected folders are git repos (contain `.git`); show an alert if not

**ContentView**
- Remove "New Task" button and Cmd+N shortcut from toolbar
- Replace with "Add Repo" button
- Clicking "+" on a repo: create task, select it, focus terminal — all instant
- Remove all remote task handling

**TaskDetailView**
- Remove remote shell tab/embedded shell view
- Terminal, diff, and file browser tabs remain

**AddTaskSheet** — deleted entirely.

### Task Creation Flow

1. User clicks "+" next to a repo in the sidebar
2. App generates next task ID (`2026-04-03-task-N`)
3. `WorktreeManager.createWorktree(projectPath, taskId)` creates `.worktrees/{id}` with branch `cs/{id}`
4. `AppTask` created with empty description, status `.working`
5. Terminal launches `claude --session-id {sessionId}` in the worktree directory
6. Task appears in sidebar, is auto-selected, terminal is focused
7. User starts typing their prompt directly

### Auto-Description via LLM

When the user sends their first prompt:

1. `UserPromptSubmit` hook fires, HookServer receives the prompt text
2. TaskCoordinator checks if the task's description is still empty
3. If empty, spawns a headless Claude CLI process: `claude -p "Summarize this task in 3-5 words as a short title: {prompt}"`
4. Captures stdout, sets it as the task description
5. Persists updated task

This avoids needing a separate API key — it reuses whatever Claude CLI auth the user already has. Only triggers once per task (first prompt).

### Terminal Launch

`TerminalStore` simplifies to always launch:
- `claude --session-id {sessionId}` (in the worktree directory)
- No `--permission-mode` flag (always uses default)
- No initial prompt argument
- No SSH/remote terminal support

### Repo Persistence

Repos persist to `~/.claude/central-station-repos.json`:

```json
{
  "nextTaskNumber": 4,
  "repos": [
    { "id": "uuid-1", "path": "/Users/me/projects/central-station" },
    { "id": "uuid-2", "path": "/Users/me/projects/my-app" }
  ]
}
```

### What Gets Removed

- `AddTaskSheet.swift` — deleted
- `RemoteConfig.swift` — deleted
- `RemoteStore` — deleted
- `RemoteShell.swift` — deleted
- Remote worktree methods in `WorktreeManager` (executable target)
- Remote task code paths in `TaskCoordinator` (addRemoteTask, remote hook installation)
- Config file loading (TaskConfig, tasks.yaml/json parsing)
- Local/remote toggle, permission mode picker, prompt field, worktree toggle from UI
- Cmd+N shortcut

### Testing

- `Repo` model: creation, persistence, name derivation from path
- Task ID generation: counter incrementing, date formatting, persistence across restarts
- Auto-description: hook triggers summarization only on first prompt, description updates correctly
- Worktree creation: always created for new tasks under correct repo path
- Sidebar grouping: tasks correctly nested under repos
