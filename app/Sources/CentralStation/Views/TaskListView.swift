import SwiftUI

struct TaskListView: View {
    let tasks: [AppTask]
    @Binding var selectedTask: AppTask?
    let onFocus: (AppTask) -> Void
    let onStop: (AppTask) -> Void
    let onDelete: (AppTask) -> Void
    var onResume: ((AppTask) -> Void)?
    var onAddTaskForRepo: ((String) -> Void)?

    private var groupedTasks: [(directory: String, label: String, tasks: [AppTask])] {
        AppTask.groupByRepo(tasks)
    }

    var body: some View {
        List(selection: Binding(
            get: { selectedTask?.id },
            set: { id in
                selectedTask = tasks.first { $0.id == id }
                // Auto-resume stopped tasks when selected
                if let task = selectedTask, task.status == .stopped {
                    onResume?(task)
                }
            }
        )) {
            ForEach(groupedTasks, id: \.directory) { group in
                Section {
                    ForEach(group.tasks) { task in
                        TaskRow(task: task, onFocus: { onFocus(task) }, onStop: { onStop(task) }, onDelete: { onDelete(task) }, onResume: { onResume?(task) })
                            .tag(task.id)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.caption2)
                        Text(group.label)
                            .font(.caption.bold())
                        Spacer()
                        Button(action: { onAddTaskForRepo?(group.directory) }) {
                            Image(systemName: "plus")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("New task in \(group.label)")
                    }
                    .foregroundStyle(.secondary)
                    .help(group.directory)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct TaskRow: View {
    let task: AppTask
    let onFocus: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void
    var onResume: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.status.icon)
                .foregroundStyle(task.status.color)
                .font(.title3)

            if task.isRemote {
                Image(systemName: "network")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .help(task.remoteAlias ?? task.sshHost ?? "Remote")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.id)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(task.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let usage = task.usage, usage.totalTokens > 0 {
                        Text(usage.formattedTokens)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Text(usage.formattedCost)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if let tool = task.pendingPermission {
                HStack(spacing: 3) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                    Text(tool)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.yellow.opacity(0.2))
                .foregroundStyle(.yellow)
                .clipShape(Capsule())
            }

            if task.status == .completed {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove task and delete worktree")
            }

            Text(task.elapsed)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Focus Terminal") { onFocus() }
            if !task.isRemote {
                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: task.worktreePath)
                }) {
                    Text("Reveal in Finder")
                }
            }
            if task.status == .completed {
                Button("Resume Task") { onResume?() }
            }
            if task.status != .completed {
                Divider()
                Button("Stop Task", role: .destructive) { onStop() }
            }
            Divider()
            Button("Remove Task", role: .destructive) { onDelete() }
        }
    }
}
