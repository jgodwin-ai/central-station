import Foundation

enum TerminalLauncher {
    private static var userSettingsPath: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/settings.json")
    }

    static func hooksInstalled() -> Bool {
        guard let data = FileManager.default.contents(atPath: userSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any],
              let stopArr = hooks["Stop"] as? [[String: Any]],
              let first = stopArr.first,
              let innerHooks = first["hooks"] as? [[String: Any]],
              let command = innerHooks.first?["command"] as? String else {
            return false
        }
        return command.contains(":\(HookServer.defaultPort)/")
    }

    static func installHooks() throws {
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

        let hooks: [String: Any] = [
            "Stop": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s -X POST http://127.0.0.1:\(port)/hook/stop -H 'Content-Type: application/json' -d \"$(cat)\""
                ]]
            ]],
            "PreToolUse": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s -X POST http://127.0.0.1:\(port)/hook/permission -H 'Content-Type: application/json' -d \"$(cat)\""
                ]]
            ]]
        ]

        if var existingHooks = existing["hooks"] as? [String: Any] {
            existingHooks["Stop"] = hooks["Stop"]
            existingHooks["PreToolUse"] = hooks["PreToolUse"]
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
