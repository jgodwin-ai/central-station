import Foundation

enum TerminalLauncher {
    private static var userSettingsPath: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/settings.json")
    }

    static func hooksInstalled() -> Bool {
        guard let data = FileManager.default.contents(atPath: userSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }
        // Check that all required hooks are present and point at our port
        for key in ["Stop", "UserPromptSubmit", "Notification", "PermissionRequest", "SubagentStop"] {
            guard let arr = hooks[key] as? [[String: Any]],
                  let first = arr.first,
                  let innerHooks = first["hooks"] as? [[String: Any]],
                  let command = innerHooks.first?["command"] as? String,
                  command.contains(":\(HookServer.defaultPort)/") else {
                return false
            }
        }
        return true
    }

    static func installHooks(secret: String) throws {
        let port = HookServer.defaultPort
        let claudeDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        let fm = FileManager.default
        if !fm.fileExists(atPath: claudeDir) {
            try fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
        }

        // Read existing settings so we don't clobber other config
        var existing: [String: Any] = [:]
        if let data = fm.contents(atPath: userSettingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existing = json
        }

        let authHeader = "-H 'Authorization: Bearer \(secret)'"
        let hooks: [String: Any] = [
            "UserPromptSubmit": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/prompt -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                ]]
            ]],
            "Stop": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/stop -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                ]]
            ]],
            "Notification": [
                [
                    "hooks": [[
                        "type": "command",
                        "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/notification -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                    ]],
                    "matcher": "permission_prompt"
                ],
                [
                    "hooks": [[
                        "type": "command",
                        "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/notification -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                    ]],
                    "matcher": "idle_prompt"
                ],
                [
                    "hooks": [[
                        "type": "command",
                        "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/notification -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                    ]],
                    "matcher": "elicitation_dialog"
                ]
            ],
            "PermissionRequest": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/permission -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                ]]
            ]],
            "SubagentStop": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/stop -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                ]]
            ]]
        ]

        if var existingHooks = existing["hooks"] as? [String: Any] {
            existingHooks["UserPromptSubmit"] = hooks["UserPromptSubmit"]
            existingHooks["Stop"] = hooks["Stop"]
            existingHooks["Notification"] = hooks["Notification"]
            existingHooks["PermissionRequest"] = hooks["PermissionRequest"]
            existingHooks["SubagentStop"] = hooks["SubagentStop"]
            existing["hooks"] = existingHooks
        } else {
            existing["hooks"] = hooks
        }

        let data = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: userSettingsPath))
    }

    static func installHooksOnRemote(host: String, secret: String) async throws {
        let port = HookServer.defaultPort

        _ = try await RemoteShell.run(host: host, command: "mkdir -p $HOME/.claude")

        let pythonScript = """
        import json, os

        settings_path = os.path.expanduser('~/.claude/settings.json')

        try:
            with open(settings_path) as f:
                settings = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            settings = {}

        curl_base = 'curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)'
        curl_opts = " -H 'Content-Type: application/json' -H 'Authorization: Bearer \(secret)' -d \\"$(cat)\\" || true"

        hooks = {
            'UserPromptSubmit': [{'hooks': [{'type': 'command', 'command': curl_base + '/hook/prompt' + curl_opts}]}],
            'Stop': [{'hooks': [{'type': 'command', 'command': curl_base + '/hook/stop' + curl_opts}]}],
            'Notification': [
                {'hooks': [{'type': 'command', 'command': curl_base + '/hook/notification' + curl_opts}], 'matcher': 'permission_prompt'},
                {'hooks': [{'type': 'command', 'command': curl_base + '/hook/notification' + curl_opts}], 'matcher': 'idle_prompt'},
                {'hooks': [{'type': 'command', 'command': curl_base + '/hook/notification' + curl_opts}], 'matcher': 'elicitation_dialog'}
            ],
            'PermissionRequest': [{'hooks': [{'type': 'command', 'command': curl_base + '/hook/permission' + curl_opts}]}],
            'SubagentStop': [{'hooks': [{'type': 'command', 'command': curl_base + '/hook/stop' + curl_opts}]}]
        }

        settings.setdefault('hooks', {}).update(hooks)

        with open(settings_path, 'w') as f:
            json.dump(settings, f, indent=2)

        print('Hooks installed successfully')
        """

        // Base64 encode the script to avoid shell escaping nightmares
        guard let scriptData = pythonScript.data(using: .utf8) else { return }
        let base64Script = scriptData.base64EncodedString()

        _ = try await RemoteShell.run(host: host, command: "echo \(base64Script) | base64 -d | python3")
    }

    static func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func buildClaudeCommand(task: AppTask) -> String {
        var parts = [
            "cd \(shellEscape(task.worktreePath))",
            "&&",
            "claude",
            "--session-id", task.sessionId
        ]

        if let mode = task.permissionMode {
            parts += ["--permission-mode", mode]
        }

        parts.append(shellEscape(task.prompt))
        return parts.joined(separator: " ")
    }
}
