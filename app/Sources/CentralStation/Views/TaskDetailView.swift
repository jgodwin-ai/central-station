import SwiftUI

enum DetailTab: String, CaseIterable {
    case terminal = "Claude Code"
    case diff = "Diff"
    case shell = "Terminal"
    case finder = "Files"
}

struct TaskDetailView: View {
    let task: AppTask
    let onPopOut: () -> Void
    let onMergeAction: (MergeAction) -> Void
    let onResume: () -> Void
    let onProcessExit: @MainActor () -> Void

    @State private var activeTab: DetailTab = .terminal
    @State private var showMergeSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: task.status.icon)
                            .foregroundStyle(task.status.color)
                        Text(task.id)
                            .font(.title2.bold())
                        Text("— \(task.status.rawValue)")
                            .font(.title3)
                            .foregroundStyle(task.status.color)
                    }
                    Text(task.description)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if task.status == .stopped {
                        Button(action: onResume) {
                            Label("Resume", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }

                    Picker("", selection: $activeTab) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340)

                    if activeTab == .diff {
                        Button(action: { showMergeSheet = true }) {
                            Label("Accept", systemImage: "arrow.triangle.merge")
                        }
                    }

                    Menu {
                        Button(action: onPopOut) {
                            Label("Pop Out Window", systemImage: "rectangle.portrait.and.arrow.forward")
                        }
                        if !task.isRemote {
                            Button(action: {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: task.worktreePath)
                            }) {
                                Label("Reveal in Finder", systemImage: "folder")
                            }
                        }
                        Button(action: {
                            if let host = task.sshHost {
                                let _ = try? ShellHelper.launchDetached("/usr/bin/env", arguments: [
                                    "code", "--remote", "ssh-remote+\(host)", task.worktreePath
                                ])
                            } else {
                                let _ = try? ShellHelper.launchDetached("/usr/bin/env", arguments: [
                                    "code", task.worktreePath
                                ])
                            }
                        }) {
                            Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
            .padding()

            Divider()

            // Notification banner when task needs input
            if task.status == .waitingForInput {
                HStack {
                    Image(systemName: "exclamationmark.bubble.fill")
                    Text("This task needs your input")
                        .font(.callout.bold())
                    Spacer()
                    if let message = task.lastMessage {
                        Text(message.prefix(100) + (message.count > 100 ? "..." : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.15))
                .foregroundStyle(.orange)

                Divider()
            }

            // Content
            if task.status == .stopped {
                VStack(spacing: 16) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Task is stopped")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Resume to start a new Claude Code session in this worktree")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Button(action: onResume) {
                        Label("Resume Task", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch activeTab {
                case .terminal:
                    EmbeddedTerminalView(task: task, onProcessExit: onProcessExit)
                case .diff:
                    FileDiffView(task: task)
                case .shell:
                    EmbeddedShellView(task: task)
                case .finder:
                    EmbeddedFinderView(task: task)
                }
            }
        }
        .sheet(isPresented: $showMergeSheet) {
            MergeSheet(taskId: task.id, worktreePath: task.worktreePath, sshHost: task.sshHost) { action in
                onMergeAction(action)
            }
        }
    }
}
