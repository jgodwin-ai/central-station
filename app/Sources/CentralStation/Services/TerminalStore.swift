import Foundation
import SwiftTerm
import AppKit

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

        let claudePath = "\(NSHomeDirectory())/.local/bin/claude"
        var args: [String]
        if task.isResume {
            args = ["--resume", task.sessionId]
        } else {
            args = ["--session-id", task.sessionId]
            if let mode = task.permissionMode {
                args += ["--permission-mode", mode]
            }
            args.append(task.prompt)
        }

        let delegate = ProcessDelegate(onProcessExit: onProcessExit)
        delegates[task.id] = delegate
        termView.processDelegate = delegate

        termView.startProcess(
            executable: claudePath,
            args: args,
            environment: nil,
            execName: "claude",
            currentDirectory: task.worktreePath
        )

        terminals[task.id] = termView
        return termView
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
