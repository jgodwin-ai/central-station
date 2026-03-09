import SwiftUI

enum MergeAction {
    case mergeOnly(String)
    case mergeAndPush(String)
    case mergeAndPR(String)
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
            Text("Commit & Merge")
                .font(.title2.bold())

            Text("Commit all changes, merge **cs/\(taskId)** back into the base branch.")
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

                Menu("Merge") {
                    Button("Merge locally") {
                        onAction(.mergeOnly(commitMessage))
                        dismiss()
                    }
                    Button("Merge & push") {
                        onAction(.mergeAndPush(commitMessage))
                        dismiss()
                    }
                    Divider()
                    Button("Merge & create PR") {
                        onAction(.mergeAndPR(commitMessage))
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
        // Get the diff summary for context
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

        // Ask Claude to generate a commit message
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
