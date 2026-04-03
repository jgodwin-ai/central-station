import Foundation
import SwiftTerm
import AppKit

/// Resolves the user's full shell environment once at launch so spawned terminals
/// get the same PATH regardless of how CentralStation itself was started.
/// Call `UserShellEnv.resolve()` early in app startup (off the main-thread view update path).
enum UserShellEnv {
    /// The user's full PATH as their interactive login shell sees it.
    nonisolated(unsafe) private(set) static var path: String = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"

    /// Resolved absolute path to the `claude` binary.
    nonisolated(unsafe) private(set) static var claudePath: String = "claude"

    /// Resolve the user's shell environment. Call once during app startup.
    /// This spawns a shell subprocess, so it must NOT run inside a `dispatch_once` or SwiftUI view update.
    static func resolve() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // Login shell sources profile files; avoid -i which can hang waiting for TTY
        process.arguments = ["-lc", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let resolved = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !resolved.isEmpty {
            path = resolved
        }

        // Ensure common user bin directories are on PATH even if login shell missed them
        // (e.g. PATH additions in .zshrc/.bashrc which login-only shells skip)
        let home = NSHomeDirectory()
        let extraDirs = [
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "/opt/homebrew/bin",
        ]
        let existing = Set(path.split(separator: ":").map(String.init))
        let missing = extraDirs.filter { !existing.contains($0) && FileManager.default.fileExists(atPath: $0) }
        if !missing.isEmpty {
            path = (missing + [path]).joined(separator: ":")
        }

        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/claude"
            if FileManager.default.fileExists(atPath: candidate) {
                claudePath = candidate
                return
            }
        }
    }
}

/// Manages a single LocalProcessTerminalView per task so it can be moved between windows.
@MainActor
final class TerminalStore {
    static let shared = TerminalStore()

    private var terminals: [String: LocalProcessTerminalView] = [:]
    private var delegates: [String: ProcessDelegate] = [:]

    func terminal(for task: AppTask, onProcessExit: @escaping @MainActor () -> Void) -> LocalProcessTerminalView {
        if let existing = terminals[task.id] {
            return existing
        }

        let termView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        termView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // Use --resume if this session already exists, --session-id for new sessions
        let sessionFlag = Self.sessionExists(task.sessionId, cwd: task.worktreePath) ? "--resume" : "--session-id"
        let cmd = "cd \(shellEscape(task.worktreePath)) && exec \(shellEscape(UserShellEnv.claudePath)) \(sessionFlag) \(task.sessionId)"

        // Build environment with the resolved PATH so claude and its subprocesses find tools
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = UserShellEnv.path
        let envArray = env.map { "\($0.key)=\($0.value)" }

        let delegate = ProcessDelegate(onProcessExit: onProcessExit)
        delegates[task.id] = delegate
        termView.processDelegate = delegate

        termView.startProcess(
            executable: shell,
            args: ["-l", "-c", cmd],
            environment: envArray,
            execName: "claude",
            currentDirectory: task.worktreePath
        )

        terminals[task.id] = termView
        return termView
    }

    /// Check if a session transcript already exists (meaning this is a resume, not a new session).
    private static func sessionExists(_ sessionId: String, cwd: String) -> Bool {
        // Claude stores transcripts in ~/.claude/projects/<escaped-cwd>/<sessionId>.jsonl
        let projectsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: projectsDir) else { return false }
        for dir in dirs {
            let transcript = (projectsDir as NSString)
                .appendingPathComponent(dir)
                .appending("/\(sessionId).jsonl")
            if FileManager.default.fileExists(atPath: transcript) {
                return true
            }
        }
        return false
    }

    private func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func hasTerminal(for taskId: String) -> Bool {
        terminals[taskId] != nil
    }

    func killAll() {
        for taskId in terminals.keys {
            killTerminal(for: taskId)
        }
    }

    func killTerminal(for taskId: String) {
        guard let termView = terminals[taskId] else { return }
        let pid = termView.process?.shellPid ?? 0
        if pid > 0 {
            // Kill the entire process group to catch child processes
            kill(-pid, SIGTERM)
            // Also kill the process directly as fallback
            kill(pid, SIGTERM)
        }
        termView.removeFromSuperview()
        terminals.removeValue(forKey: taskId)
        delegates.removeValue(forKey: taskId)
    }
}

final class ProcessDelegate: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
    let onProcessExit: @MainActor () -> Void

    init(onProcessExit: @escaping @MainActor () -> Void) {
        self.onProcessExit = onProcessExit
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.onProcessExit()
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
