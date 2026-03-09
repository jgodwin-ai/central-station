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
        let diff: String
        do {
            diff = try await ShellHelper.runGit(in: worktreePath, args: ["diff", "HEAD", "--stat"])
        } catch {
            commitMessage = "Changes from task: \(taskId)"
            isGenerating = false
            return
        }

        if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commitMessage = "Changes from task: \(taskId)"
            isGenerating = false
            return
        }

        let claudePath = "\(NSHomeDirectory())/.local/bin/claude"
        let prompt = "Generate a concise git commit message (subject line + optional body) for these changes. Output ONLY the commit message, nothing else.\n\nTask: \(taskId)\n\nChanged files:\n\(diff)"

        do {
            let result = try await ShellHelper.run(claudePath, arguments: ["-p", prompt])
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            commitMessage = trimmed.isEmpty ? "Changes from task: \(taskId)" : trimmed
        } catch {
            commitMessage = "Changes from task: \(taskId)"
        }
        isGenerating = false
    }
}
