#!/bin/bash
# Central Station Hook Installer
# Installs Claude Code hooks to your global settings (~/.claude/settings.json).
# These hooks report to the Central Station dashboard on localhost:19280.
#
# Usage:
#   ./install-hooks.sh

set -euo pipefail

PORT=19280
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# If file exists, we need to merge. If not, write fresh.
if [ -f "$SETTINGS_FILE" ]; then
    # Back up existing settings
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"
    echo "Backed up existing settings to $SETTINGS_FILE.bak"
fi

# Write the hooks config (overwrites hooks section, preserves nothing else for simplicity)
cat > "$SETTINGS_FILE" << 'HOOKEOF'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:19280/hook/stop -H 'Content-Type: application/json' -d \"$(cat)\" || true"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:19280/hook/notification -H 'Content-Type: application/json' -d \"$(cat)\" || true"
          }
        ]
      },
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:19280/hook/notification -H 'Content-Type: application/json' -d \"$(cat)\" || true"
          }
        ]
      },
      {
        "matcher": "elicitation_dialog",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:19280/hook/notification -H 'Content-Type: application/json' -d \"$(cat)\" || true"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:19280/hook/permission -H 'Content-Type: application/json' -d \"$(cat)\" || true"
          }
        ]
      }
    ]
  }
}
HOOKEOF

chmod 600 "$SETTINGS_FILE"
echo "Hooks installed to $SETTINGS_FILE (port $PORT)"
echo "Start Central Station and all Claude Code sessions will report to the dashboard."
