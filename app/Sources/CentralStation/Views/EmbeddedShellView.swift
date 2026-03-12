import SwiftUI
import SwiftTerm
import AppKit

/// Embeds a regular shell terminal (not Claude) in the worktree directory.
/// For remote tasks, SSHs into the remote and cd's to the worktree.
struct EmbeddedShellView: NSViewRepresentable {
    let task: AppTask

    @State private var shellTerminal: LocalProcessTerminalView?

    func makeNSView(context: Context) -> NSView {
        let termView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        termView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        if let sshHost = task.sshHost {
            // Remote: SSH into the remote machine
            let escapedPath = "'" + task.worktreePath.replacingOccurrences(of: "'", with: "'\\''") + "'"
            termView.startProcess(
                executable: "/usr/bin/ssh",
                args: ["-t", sshHost, "cd \(escapedPath) && exec $SHELL -l"],
                environment: nil,
                execName: "ssh",
                currentDirectory: NSHomeDirectory()
            )
        } else {
            // Local: launch login shell in the worktree
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            termView.startProcess(
                executable: shell,
                args: ["-l"],
                environment: nil,
                execName: (shell as NSString).lastPathComponent,
                currentDirectory: task.worktreePath
            )
        }

        let container = NSView(frame: .zero)
        container.addSubview(termView)
        termView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            termView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            termView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            termView.topAnchor.constraint(equalTo: container.topAnchor),
            termView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
