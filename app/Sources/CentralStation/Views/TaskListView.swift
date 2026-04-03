import SwiftUI

struct TaskListView: View {
    let repos: [Repo]
    let tasks: [AppTask]
    @Binding var selectedTaskId: String?
    var onAddTask: (Repo) -> Void
    var onRemoveRepo: (Repo) -> Void
    let onFocus: (AppTask) -> Void
    let onStop: (AppTask) -> Void
    let onDelete: (AppTask) -> Void
    var onResume: ((AppTask) -> Void)?

    private func tasksForRepo(_ repo: Repo) -> [AppTask] {
        tasks.filter { $0.projectPath == repo.path }
    }

    var body: some View {
        List(selection: Binding(
            get: { selectedTaskId },
            set: { id in
                selectedTaskId = id
                if let id, let task = tasks.first(where: { $0.id == id }),
                   task.status == .stopped {
                    onResume?(task)
                }
            }
        )) {
            ForEach(repos) { repo in
                Section {
                    ForEach(tasksForRepo(repo)) { task in
                        TaskRow(task: task, onFocus: { onFocus(task) }, onStop: { onStop(task) }, onDelete: { onDelete(task) }, onResume: { onResume?(task) })
                            .tag(task.id)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.caption2)
                        Text(repo.name)
                            .font(.caption.bold())
                        Spacer()
                        Button(action: { onAddTask(repo) }) {
                            Image(systemName: "plus")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("New task in \(repo.name)")
                    }
                    .foregroundStyle(.secondary)
                    .help(repo.path)
                    .contextMenu {
                        Button("Remove Repo", role: .destructive) {
                            onRemoveRepo(repo)
                        }
                    }
                }
            }

            // Show tasks that don't belong to any registered repo (orphaned)
            let orphanedTasks = tasks.filter { task in
                !repos.contains { $0.path == task.projectPath }
            }
            if !orphanedTasks.isEmpty {
                let grouped = AppTask.groupByRepo(orphanedTasks)
                ForEach(grouped, id: \.directory) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            TaskRow(task: task, onFocus: { onFocus(task) }, onStop: { onStop(task) }, onDelete: { onDelete(task) }, onResume: { onResume?(task) })
                                .tag(task.id)
                        }
                    } header: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text(group.label)
                                .font(.caption.bold())
                        }
                        .foregroundStyle(.secondary)
                        .help(group.directory)
                    }
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

            VStack(alignment: .leading, spacing: 2) {
                Text(task.description.isEmpty ? task.id : task.description)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(task.id)
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
            Button(action: {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: task.worktreePath)
            }) {
                Text("Reveal in Finder")
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
