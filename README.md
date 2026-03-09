# Central Station

A terminal multiplexer for running multiple [Claude Code](https://docs.anthropic.com/en/docs/claude-code) instances in parallel. Define tasks in a YAML file, and Central Station launches each one in its own Terminal.app window with an isolated git worktree — then monitors everything from a single dashboard.

## Features

- **Parallel execution** — Run multiple Claude Code tasks simultaneously
- **Git isolation** — Each task gets its own worktree, so changes never collide
- **Live dashboard** — See task status, navigate between tasks, and view diffs from your terminal
- **Hook integration** — Automatically notified when a task stops and needs input
- **macOS notifications** — Get alerted when tasks need attention

## Install

```bash
npm install
npm run build
npm install -g .
```

## Usage

Create a `tasks.yaml` config file:

```yaml
project: /path/to/your/repo

tasks:
  - id: auth-refactor
    description: "Refactor auth module to use JWT"
    prompt: "Refactor the auth module in src/auth/ to use JWT tokens instead of sessions."

  - id: add-tests
    description: "Add unit tests for payment service"
    prompt: "Write comprehensive unit tests for src/services/payment.ts."
    permission_mode: auto  # optional: default, acceptEdits, plan, auto
```

Run it:

```bash
central-station tasks.yaml
```

## Dashboard keys

| Key | Action |
|-----|--------|
| `↑` / `k` | Navigate up |
| `↓` / `j` | Navigate down |
| `d` | Toggle diff viewer |
| `f` | Focus task's terminal window |
| `r` | Refresh diff |
| `q` | Quit |

## How it works

1. Reads your YAML config and creates a git worktree per task (branch `cs/{taskId}`)
2. Opens a Terminal.app window for each task running `claude` with the given prompt
3. Configures a hook server so each Claude Code instance reports status back
4. Displays a live dashboard showing all task statuses
5. When a task needs input, you get a notification and can press `f` to jump to its terminal

## Requirements

- macOS (uses Terminal.app and AppleScript)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- Node.js 18+
