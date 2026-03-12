import SwiftUI
import AppKit

struct ContentView: View {
    @State var coordinator: TaskCoordinator
    @State private var selectedTask: AppTask?
    @State private var showAddTask = false
    @State private var showHookInfo = false
    @State private var showManageRemotes = false
    @State private var showChimeSettings = false
    @State private var mergeError: String?
    @State private var updateInfo: UpdateChecker.UpdateInfo?
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if let update = updateInfo {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.blue)
                        Text("v\(update.version) available")
                            .font(.caption)
                        Spacer()
                        Button("Update") {
                            if let url = URL(string: update.url) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        Button {
                            updateInfo = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.1))
                    Divider()
                }

                Button(action: { showAddTask = true }) {
                    Label("New Task", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)
                .padding(10)

                Divider()

                TaskListView(
                    tasks: coordinator.tasks,
                    selectedTask: $selectedTask,
                    onFocus: { task in
                        if coordinator.poppedOutTaskIds.contains(task.id) {
                            openWindow(id: "terminal", value: task.id)
                        }
                    },
                    onStop: { task in
                        TerminalStore.shared.killTerminal(for: task.id)
                        task.status = .completed
                    },
                    onDelete: { task in
                        Task {
                            if selectedTask?.id == task.id {
                                selectedTask = nil
                            }
                            await coordinator.deleteTask(task)
                        }
                    }
                )

                Divider()

                HStack {
                    Button(action: { showHookInfo = true }) {
                        Label("Hooks", systemImage: coordinator.hooksInstalled ? "checkmark.circle" : "exclamationmark.triangle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(coordinator.hooksInstalled ? Color.secondary : Color.orange)
                    Spacer()
                    Button(action: { showChimeSettings = true }) {
                        Image(systemName: "bell.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Notification settings")
                    Button(action: { showManageRemotes = true }) {
                        Label("Remotes", systemImage: "network")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            .background(.background.secondary)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            if let task = selectedTask {
                let isPoppedOut = coordinator.poppedOutTaskIds.contains(task.id)

                if isPoppedOut {
                    // Terminal is in a separate window
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.portrait.and.arrow.forward")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Terminal is in a separate window")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Focus Window") {
                                openWindow(id: "terminal", value: task.id)
                            }
                            Button("Dock Back") {
                                coordinator.poppedOutTaskIds.remove(task.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TaskDetailView(
                        task: task,
                        onPopOut: {
                            coordinator.poppedOutTaskIds.insert(task.id)
                            openWindow(id: "terminal", value: task.id)
                        },
                        onMergeAction: { action in
                            Task {
                                do {
                                    let prURL = try await coordinator.handleMergeAction(task: task, action: action)
                                    if let prURL, let url = URL(string: prURL) {
                                        NSWorkspace.shared.open(url)
                                    }
                                } catch {
                                    mergeError = error.localizedDescription
                                }
                            }
                        },
                        onResume: {
                            coordinator.resumeTask(task)
                        }
                    )
                    .id("\(task.id)-\(task.status)")
                }
            } else if coordinator.tasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No tasks yet")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Create a task to start a Claude Code session")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Button("New Task") { showAddTask = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Select a Task",
                    systemImage: "sidebar.left",
                    description: Text("Choose a task from the sidebar")
                )
            }
        }
        .onReceive(timer) { _ in
            coordinator.tasks.forEach { _ in }
        }
        .sheet(isPresented: $showAddTask) {
            AddTaskSheet(defaultProjectPath: coordinator.projectPath, remoteStore: coordinator.remoteStore) { id, description, prompt, mode, customPath, remote, remotePath in
                Task {
                    if let remote, let remotePath {
                        try? await coordinator.addRemoteTask(
                            id: id, description: description, prompt: prompt,
                            permissionMode: mode, remote: remote, remotePath: remotePath
                        )
                    } else {
                        try? await coordinator.addTask(
                            id: id, description: description,
                            prompt: prompt, permissionMode: mode,
                            customProjectPath: customPath
                        )
                    }
                    if let newTask = coordinator.tasks.last {
                        selectedTask = newTask
                    }
                }
            }
        }
        .sheet(isPresented: $showManageRemotes) {
            ManageRemotesSheet(remoteStore: coordinator.remoteStore)
        }
        .sheet(isPresented: $showChimeSettings) {
            ChimeSettingsSheet()
        }
        .sheet(isPresented: $showHookInfo) {
            HookInfoSheet(
                port: HookServer.defaultPort,
                isInstalled: coordinator.hooksInstalled,
                onInstall: { try? coordinator.installHooks() }
            )
        }
        .alert("Merge Failed", isPresented: Binding(get: { mergeError != nil }, set: { if !$0 { mergeError = nil } })) {
            Button("OK") { mergeError = nil }
        } message: {
            Text(mergeError ?? "")
        }
        .onAppear {
            coordinator.checkHooksInstalled()
            if let first = coordinator.tasks.first {
                selectedTask = first
            }
            if !coordinator.hooksInstalled {
                showHookInfo = true
            }
            Task {
                updateInfo = await UpdateChecker.check()
            }
        }
    }
}
