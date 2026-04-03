import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State var coordinator: TaskCoordinator
    var recommendedWarning: String?
    @State private var selectedTaskId: String?
    @State private var showHookInfo = false
    @State private var showChimeSettings = false
    @State private var showRecommendedWarning = true
    @State private var showNotGitRepoAlert = false
    @State private var showNewTaskPopover = false
    @State private var newTaskName = ""
    @State private var newTaskRepo: Repo?
    @State private var mergeError: String?
    @State private var updateInfo: UpdateChecker.UpdateInfo?
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @Environment(\.openWindow) private var openWindow

    private var selectedTask: AppTask? {
        guard let selectedTaskId else { return nil }
        return coordinator.tasks.first { $0.id == selectedTaskId }
    }

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
                            if Validation.isValidUpdateURL(update.url),
                               let url = URL(string: update.url) {
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

                if let warning = recommendedWarning, showRecommendedWarning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.caption)
                            .lineLimit(3)
                        Spacer()
                        Button {
                            showRecommendedWarning = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.1))
                    Divider()
                }

                TaskListView(
                    repos: coordinator.repoPersistence.repos,
                    tasks: coordinator.tasks,
                    selectedTaskId: $selectedTaskId,
                    onAddTask: { repo in
                        if coordinator.repoPersistence.requireTaskName {
                            newTaskRepo = repo
                            newTaskName = ""
                            showNewTaskPopover = true
                        } else {
                            Task {
                                if let task = try? await coordinator.addTask(for: repo) {
                                    selectedTaskId = task.id
                                }
                            }
                        }
                    },
                    onRemoveRepo: { repo in
                        coordinator.removeRepo(id: repo.id)
                    },
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
                            if selectedTaskId == task.id {
                                selectedTaskId = nil
                            }
                            await coordinator.deleteTask(task)
                        }
                    },
                    onResume: { task in
                        coordinator.resumeTask(task)
                    }
                )

                Divider()

                if coordinator.needsInputCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                        Text("\(coordinator.needsInputCount) waiting")
                            .font(.caption)
                        Spacer()
                        Text("Cmd+Up/Down")
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    Divider()
                }

                if let acct = coordinator.accountUsage {
                    VStack(spacing: 4) {
                        UsageBar(label: "5h", percent: acct.fiveHourPercent, resetIn: acct.fiveHourResetIn)
                        UsageBar(label: "7d", percent: acct.sevenDayPercent, resetIn: acct.sevenDayResetIn)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    Divider()
                }

                HStack {
                    Button(action: { showHookInfo = true }) {
                        Label("Hooks", systemImage: coordinator.hooksInstalled ? "checkmark.circle" : "exclamationmark.triangle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(coordinator.hooksInstalled ? Color.secondary : Color.orange)
                    Spacer()
                    Toggle(isOn: Binding(
                        get: { coordinator.repoPersistence.requireTaskName },
                        set: { coordinator.repoPersistence.requireTaskName = $0; coordinator.saveRepos() }
                    )) {
                        Image(systemName: "tag")
                    }
                    .toggleStyle(.checkbox)
                    .help("Require task name before creating")
                    Button(action: { showChimeSettings = true }) {
                        Image(systemName: "bell.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Notification settings")
                }
                .padding(8)
            }
            .background(.background.secondary)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: pickRepoFolder) {
                        Label("Add Repo", systemImage: "plus.rectangle.on.folder")
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        let path = url.path
                        if FileManager.default.fileExists(atPath: path + "/.git") {
                            DispatchQueue.main.async {
                                coordinator.addRepo(path: path)
                            }
                        }
                    }
                }
                return true
            }
        } detail: {
            if let task = selectedTask {
                let isPoppedOut = coordinator.poppedOutTaskIds.contains(task.id)

                if isPoppedOut {
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
                                    if let prURL, Validation.isValidPRURL(prURL),
                                       let url = URL(string: prURL) {
                                        NSWorkspace.shared.open(url)
                                    }
                                } catch {
                                    mergeError = error.localizedDescription
                                }
                            }
                        },
                        onResume: {
                            coordinator.resumeTask(task)
                        },
                        onProcessExit: {
                            coordinator.handleProcessExit(taskId: task.id)
                        }
                    )
                    .id("\(task.id)-\(task.status)")
                }
            } else if coordinator.tasks.isEmpty && coordinator.repoPersistence.repos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No repos yet")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Add a git repository to start creating tasks")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Button("Add Repo") { pickRepoFolder() }
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
            Task { await coordinator.refreshUsage() }
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
        .alert("Not a Git Repository", isPresented: $showNotGitRepoAlert) {
            Button("OK") {}
        } message: {
            Text("The selected folder is not a git repository. Please select a folder that contains a .git directory.")
        }
        .sheet(isPresented: $showNewTaskPopover) {
            VStack(spacing: 12) {
                Text("New Task")
                    .font(.headline)
                TextField("Task name (used for branch)", text: $newTaskName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit {
                        createNamedTask()
                    }
                Text("Branch: cs/\(previewTaskId)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                HStack {
                    Button("Cancel") {
                        showNewTaskPopover = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Create") {
                        createNamedTask()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTaskName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
        }
        .background {
            Button("") { selectNextNeedingInput(forward: true) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .hidden()
            Button("") { selectNextNeedingInput(forward: false) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .hidden()
        }
        .onAppear {
            coordinator.checkHooksInstalled()
            if let first = coordinator.tasks.first {
                selectedTaskId = first.id
            }
            if !coordinator.hooksInstalled {
                showHookInfo = true
            }
            Task {
                updateInfo = await UpdateChecker.check()
            }
        }
    }

    private var previewTaskId: String {
        let name = newTaskName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "..." }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        let slug = Validation.sanitizeTaskId(name)
        return "\(date)-\(slug)"
    }

    private func createNamedTask() {
        guard let repo = newTaskRepo else { return }
        let name = newTaskName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        showNewTaskPopover = false
        Task {
            if let task = try? await coordinator.addTask(for: repo, customName: name) {
                selectedTaskId = task.id
            }
        }
    }

    private func pickRepoFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository folder"
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if FileManager.default.fileExists(atPath: path + "/.git") {
                coordinator.addRepo(path: path)
            } else {
                showNotGitRepoAlert = true
            }
        }
    }

    private func selectNextNeedingInput(forward: Bool) {
        let waiting = coordinator.tasks.filter { $0.status == .waitingForInput }
        guard !waiting.isEmpty else { return }

        if let currentId = selectedTaskId,
           let currentIdx = waiting.firstIndex(where: { $0.id == currentId }) {
            let nextIdx = forward
                ? waiting.index(after: currentIdx) % waiting.count
                : (currentIdx == waiting.startIndex ? waiting.count - 1 : waiting.index(before: currentIdx))
            selectedTaskId = waiting[nextIdx].id
        } else {
            selectedTaskId = forward ? waiting.first?.id : waiting.last?.id
        }
    }
}
