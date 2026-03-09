import SwiftUI
import AppKit

struct ContentView: View {
    @State var coordinator: TaskCoordinator
    @State private var selectedTask: AppTask?
    @State private var showAddTask = false
    @State private var showHookInfo = false
    @State private var mergeError: String?
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
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
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
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
                        }
                    )
                    .id(task.id)
                }
            } else {
                ContentUnavailableView(
                    "Select a Task",
                    systemImage: "sidebar.left",
                    description: Text("Choose a task from the sidebar to view its terminal and diffs")
                )
            }
        }
        .onReceive(timer) { _ in
            coordinator.tasks.forEach { _ in }
        }
        .sheet(isPresented: $showAddTask) {
            AddTaskSheet(defaultProjectPath: coordinator.projectPath) { id, description, prompt, mode, customPath in
                Task {
                    try? await coordinator.addTask(
                        id: id, description: description,
                        prompt: prompt, permissionMode: mode,
                        customProjectPath: customPath
                    )
                    if let newTask = coordinator.tasks.last {
                        selectedTask = newTask
                    }
                }
            }
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
        }
    }
}
