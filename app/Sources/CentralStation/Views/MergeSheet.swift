import SwiftUI

enum MergeAction {
    case mergeToMain(String)
    case createBranch(String)
    case createPR(String)
}

struct MergeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let taskId: String
    let worktreePath: String
    let sshHost: String?
    let onAction: (MergeAction) -> Void

    @State private var commitMessage = ""
    @State private var isGenerating = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accept Changes")
                .font(.title2.bold())

            Text("Commit changes from **cs/\(taskId)** and choose how to integrate them.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Commit Message")
                        .font(.caption)
                    Spacer()
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                TextEditor(text: $commitMessage)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .border(Color.secondary.opacity(0.3))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Menu("Accept") {
                    Button("Merge to main") {
                        onAction(.mergeToMain(commitMessage))
                        dismiss()
                    }
                    Button("Create branch") {
                        onAction(.createBranch(commitMessage))
                        dismiss()
                    }
                    Divider()
                    Button("Create PR") {
                        onAction(.createPR(commitMessage))
                        dismiss()
                    }
                }
                .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
            }
        }
        .padding()
        .frame(width: 520, height: 340)
        .task { await generateMessage() }
    }

    private func generateMessage() async {
        // Run Claude Code in the worktree so it has full context of the changes,
        // then ask it to write a commit message based on what it sees.
        let claudePath = "\(NSHomeDirectory())/.local/bin/claude"
        let prompt = "Look at the changes in this repo (use git diff HEAD and git status). Write a concise git commit message: a clear subject line (max 72 chars) describing what changed and why, optionally followed by a blank line and short body. Output ONLY the commit message, nothing else."

        do {
            let result: String
            if let host = sshHost {
                // Remote: run claude on the remote in the worktree
                let escapedPath = "'" + worktreePath.replacingOccurrences(of: "'", with: "'\\''") + "'"
                let escapedPrompt = "'" + prompt.replacingOccurrences(of: "'", with: "'\\''") + "'"
                result = try await RemoteShell.run(host: host, command: "cd \(escapedPath) && claude -p \(escapedPrompt)")
            } else {
                // Local: run claude in the worktree directory
                result = try await ShellHelper.run(claudePath, arguments: ["-p", prompt], currentDirectory: worktreePath)
            }
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            commitMessage = trimmed.isEmpty ? "Changes from task: \(taskId)" : trimmed
        } catch {
            commitMessage = "Changes from task: \(taskId)"
        }
        isGenerating = false
    }
}
