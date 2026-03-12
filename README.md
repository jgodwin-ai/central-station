# Central Station

A multi-agent, multi-repo command center for Claude Code. Run multiple Claude Code instances across repos and machines, each in its own git worktree, and monitor them all from a single native macOS dashboard.

Unlike wrapper tools that simulate agents, Central Station uses **native Claude Code installations**. Every agent gets the full Claude Code harness — tool use, file editing, MCP servers, permissions — with a dashboard that shows you what's happening across all of them. A lightweight localhost hook server lets Claude Code notify the dashboard when it needs input, so you never miss a prompt.

Remote agent development (SSH) is supported, and dev container support is in progress.

## Install

Requires macOS 14+ and Swift 6.0+ (Xcode or Command Line Tools).

**One-liner:**

```sh
curl -fsSL https://raw.githubusercontent.com/jgodwin-ai/claude-central-station/main/install.sh | sh
```

This clones the repo, builds a release binary, installs `Claude Central Station.app` to `/Applications`, and adds a `central-station` CLI command.

**From source:**

```sh
git clone https://github.com/jgodwin-ai/claude-central-station.git
cd claude-central-station
scripts/build-dmg.sh 1.0.0   # produces build/Claude Central Station-1.0.0.dmg
```

**Usage:**

```sh
# Launch from anywhere
central-station

# Or with a task config
central-station tasks.yaml
```

## Architecture

Central Station is a native SwiftUI macOS app. Here's how the pieces fit together:

```
┌─────────────────────────────────────────────────┐
│  Dashboard (SwiftUI)                            │
│  ┌───────────┐ ┌─────────────────────────────┐  │
│  │ Task List │ │ Detail: Claude | Diff |      │  │
│  │           │ │         Terminal | Files     │  │
│  └───────────┘ └─────────────────────────────┘  │
└──────────────────────┬──────────────────────────┘
                       │
              ┌────────┴────────┐
              │  Hook Server    │  (localhost HTTP)
              │  :19280         │
              └────────┬────────┘
                       │ POST /hook/stop
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
  ┌──────────┐   ┌──────────┐   ┌──────────┐
  │ Claude   │   │ Claude   │   │ Claude   │
  │ Code #1  │   │ Code #2  │   │ Code #3  │
  │ worktree │   │ worktree │   │ worktree │
  └──────────┘   └──────────┘   └──────────┘
```

**Git worktrees** — Each task gets its own worktree (`<project>/.worktrees/<task-id>`) on a dedicated branch. Agents work in isolation; merge back to main when done.

**Hook server** — A local HTTP server receives Claude Code `Stop` hook events. When an agent finishes a turn and is waiting for input, the hook fires a POST to the dashboard, updating task status in real time. No polling.

**Embedded terminals** — Each task has a terminal tab running the actual Claude Code session. You can also pop it out or open the worktree in VS Code.

**Remote tasks (SSH)** — Tasks can target remote machines. Central Station SSHs into the host, creates a worktree there, and launches Claude Code over the connection. A reverse SSH tunnel (`-R 19280:localhost:19280`) routes hook events back to the local dashboard, so monitoring works transparently.

**Task config** — Define tasks in YAML or add them interactively:

```yaml
project: /path/to/repo
tasks:
  - id: auth-refactor
    description: "Refactor auth to JWT"
    prompt: "Refactor src/auth/ to use JWT tokens..."  # optional
  - id: add-tests
    description: "Add payment tests"
```

## Disclaimer

This is an independent, community project. It is **not** an official Anthropic product and is not affiliated with or endorsed by Anthropic in any way. This software is provided as-is with no warranty of any kind — use at your own risk. See [LICENSE](LICENSE) for details.

## License

[MIT](LICENSE)
