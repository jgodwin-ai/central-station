import SwiftUI

struct TaskListView: View {
    let tasks: [AppTask]
    @Binding var selectedTask: AppTask?
    let onFocus: (AppTask) -> Void
    let onStop: (AppTask) -> Void
    let onDelete: (AppTask) -> Void
    var onResume: ((AppTask) -> Void)?

    private var groupedTasks: [(directory: String, label: String, tasks: [AppTask])] {
        var groups: [String: [AppTask]] = [:]
        for task in tasks {
            let dir = task.projectPath
            groups[dir, default: []].append(task)
        }
        return groups.sorted { $0.key < $1.key }.map { dir, tasks in
            let label = (dir as NSString).lastPathComponent
            return (directory: dir, label: label, tasks: tasks)
        }
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
                        TaskRow(task: task, onFocus: { onFocus(task) }, onStop: { onStop(task) }, onDelete: { onDelete(task) })
                            .tag(task.id)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.caption2)
                        Text(group.label)
                            .font(.caption.bold())
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
                Text(task.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
            if task.status != .completed {
                Divider()
                Button("Stop Task", role: .destructive) { onStop() }
            }
            Divider()
            Button("Remove Task", role: .destructive) { onDelete() }
        }
    }
}
