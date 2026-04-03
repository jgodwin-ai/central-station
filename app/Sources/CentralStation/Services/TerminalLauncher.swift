import Foundation

enum TerminalLauncher {
    private static var userSettingsPath: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/settings.json")
    }

    /// Extracts the Bearer secret from an already-installed hook command, if present.
    static func installedSecret() -> String? {
        guard let data = FileManager.default.contents(atPath: userSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any],
              let arr = hooks["Stop"] as? [[String: Any]],
              let first = arr.first,
              let innerHooks = first["hooks"] as? [[String: Any]],
              let command = innerHooks.first?["command"] as? String,
              command.contains(":\(HookServer.defaultPort)/"),
              let range = command.range(of: "Bearer ") else {
            return nil
        }
        let after = command[range.upperBound...]
        let token = String(after.prefix(while: { $0 != "'" && $0 != "\"" && $0 != " " }))
        return token.isEmpty ? nil : token
    }

    static func hooksInstalled() -> Bool {
        guard let data = FileManager.default.contents(atPath: userSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }
        // Check that all required hooks are present and point at our port
        for key in ["Stop", "UserPromptSubmit", "Notification", "PermissionRequest", "SubagentStop", "SessionEnd", "PostToolUse"] {
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
            ]],
            "SessionEnd": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/session-end -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                ]]
            ]],
            "PostToolUse": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/prompt -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                ]]
            ]]
        ]

        if var existingHooks = existing["hooks"] as? [String: Any] {
            existingHooks["UserPromptSubmit"] = hooks["UserPromptSubmit"]
            existingHooks["Stop"] = hooks["Stop"]
            existingHooks["Notification"] = hooks["Notification"]
            existingHooks["PermissionRequest"] = hooks["PermissionRequest"]
            existingHooks["SubagentStop"] = hooks["SubagentStop"]
            existingHooks["SessionEnd"] = hooks["SessionEnd"]
            existingHooks["PostToolUse"] = hooks["PostToolUse"]
            existing["hooks"] = existingHooks
        } else {
            existing["hooks"] = hooks
        }

        let data = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: userSettingsPath))
    }

    static func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
