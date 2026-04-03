import Foundation
import SwiftUI

@Observable
@MainActor
final class TaskCoordinator {
    var tasks: [AppTask] = []
    var repoPersistence = RepoPersistence()
    var poppedOutTaskIds: Set<String> = []
    private let hookServer = HookServer()
    private var hookSecret = TerminalLauncher.installedSecret() ?? HookSecret.generate()
    private var sessionToTaskId: [String: String] = [:]

    private static var persistencePath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/central-station-tasks.json")
    }

    private static var reposPersistencePath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/central-station-repos.json")
    }

    var needsInputCount: Int {
        tasks.filter { $0.status == .waitingForInput }.count
    }

    var hooksInstalled: Bool = false
    var accountUsage: AccountUsage?

    func checkHooksInstalled() {
        hooksInstalled = TerminalLauncher.hooksInstalled()
    }

    func installHooks() throws {
        try TerminalLauncher.installHooks(secret: hookSecret)
        hooksInstalled = true
    }

    func loadRepos() {
        guard let data = FileManager.default.contents(atPath: Self.reposPersistencePath),
              let persistence = try? JSONDecoder().decode(RepoPersistence.self, from: data) else {
            return
        }
        repoPersistence = persistence
    }

    func saveRepos() {
        guard let data = try? JSONEncoder().encode(repoPersistence) else { return }
        try? SecureFile.write(data, to: Self.reposPersistencePath)
    }

    func loadPersistedTasks() {
        guard let data = FileManager.default.contents(atPath: Self.persistencePath),
              let persisted = try? JSONDecoder().decode([PersistedTask].self, from: data) else {
            return
        }
        for p in persisted {
            // Skip if worktree no longer exists
            guard FileManager.default.fileExists(atPath: p.worktreePath) else { continue }
            // Skip if already loaded
            guard !tasks.contains(where: { $0.id == p.id }) else { continue }
            let task = AppTask(persisted: p)
            // Everything loads as stopped — user must resume
            if task.status != .completed {
                task.status = .stopped
            }
            tasks.append(task)
            sessionToTaskId[task.sessionId] = task.id
        }
    }

    func saveTasks() {
        let persisted = tasks.map { $0.toPersisted() }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? SecureFile.write(data, to: Self.persistencePath)
    }

    var needsPermissionCount: Int {
        tasks.filter { $0.pendingPermission != nil }.count
    }

    func start() async throws {
        try hookServer.start()
        hookServer.secret = hookSecret
        hookServer.onStop = { [weak self] sessionId, message in
            self?.handleStop(sessionId: sessionId, message: message)
        }
        hookServer.onWorking = { [weak self] sessionId, promptText in
            self?.handleWorking(sessionId: sessionId)
            if let promptText, let taskId = self?.sessionToTaskId[sessionId] {
                self?.summarizeFirstPrompt(taskId: taskId, promptText: promptText)
            }
        }
        hookServer.onPermissionRequest = { [weak self] sessionId, toolName in
            self?.handlePermission(sessionId: sessionId, toolName: toolName)
        }
        hookServer.onNotification = { [weak self] sessionId, notifType in
            self?.handleNotification(sessionId: sessionId, type: notifType)
        }
        saveTasks()
    }

    func addTask(for repo: Repo, customName: String? = nil) async throws -> AppTask {
        let taskId = repoPersistence.nextTaskId(customName: customName)
        try await WorktreeManager.ensureGitRepo(at: repo.path)
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: repo.path, taskId: taskId)
        let task = AppTask(id: taskId, worktreePath: worktreePath, projectPath: repo.path)
        task.status = .working
        task.startedAt = Date()
        tasks.append(task)
        sessionToTaskId[task.sessionId] = task.id
        saveRepos()
        saveTasks()
        return task
    }

    func addRepo(path: String) {
        guard !repoPersistence.repos.contains(where: { $0.path == path }) else { return }
        let repo = Repo(path: path)
        repoPersistence.repos.append(repo)
        saveRepos()
    }

    func removeRepo(id: String) {
        guard let repo = repoPersistence.repos.first(where: { $0.id == id }) else { return }
        let hasActiveTasks = tasks.contains { $0.projectPath == repo.path && $0.status != .completed && $0.status != .stopped }
        guard !hasActiveTasks else { return }
        repoPersistence.repos.removeAll { $0.id == id }
        saveRepos()
    }

    func resumeTask(_ task: AppTask) {
        TerminalStore.shared.killTerminal(for: task.id)
        sessionToTaskId[task.sessionId] = task.id
        task.startedAt = Date()
        task.status = .starting
        saveTasks()
    }

    func refreshDiff(for task: AppTask) async {
        task.diff = await WorktreeManager.getDiff(worktreePath: task.worktreePath)
    }

    func handleMergeAction(task: AppTask, action: MergeAction) async throws -> String? {
        let message: String
        switch action {
        case .mergeToMain(let msg): message = msg
        case .createBranch(let msg): message = msg
        case .createPR(let msg): message = msg
        }

        try await WorktreeManager.commitWorktree(worktreePath: task.worktreePath, message: message)
        var prURL: String?
        switch action {
        case .mergeToMain:
            try await WorktreeManager.mergeToMain(projectPath: task.projectPath, taskId: task.id, message: message)
        case .createBranch:
            try await WorktreeManager.pushBranch(projectPath: task.projectPath, taskId: task.id)
        case .createPR:
            prURL = try await WorktreeManager.createPR(projectPath: task.projectPath, taskId: task.id, message: message)
        }
        task.status = .completed
        saveTasks()
        return prURL
    }

    func deleteTask(_ task: AppTask) async {
        TerminalStore.shared.killTerminal(for: task.id)
        await WorktreeManager.removeWorktree(projectPath: task.projectPath, taskId: task.id)
        sessionToTaskId.removeValue(forKey: task.sessionId)
        tasks.removeAll { $0.id == task.id }
        saveTasks()
    }

    func summarizeFirstPrompt(taskId: String, promptText: String) {
        guard let task = tasks.first(where: { $0.id == taskId }),
              task.description.isEmpty else { return }

        let truncated = String(promptText.prefix(500))
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["claude", "-p", "Summarize this task in 3-5 words as a short title. Output ONLY the title, nothing else: \(truncated)"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let summary = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                await MainActor.run {
                    task.description = summary
                    self.saveTasks()
                }
            }
        }
    }

    func refreshUsage() async {
        // Refresh per-task usage from JSONL files
        for task in tasks where task.status != .completed {
            task.usage = SessionUsageParser.parseForSession(sessionId: task.sessionId)
        }
        // Refresh account-level usage
        accountUsage = await AccountUsageFetcher.fetch()
    }

    func stop() {
        TerminalStore.shared.killAll()
        for task in tasks {
            if task.status == .working || task.status == .waitingForInput || task.status == .pending {
                task.status = .stopped
            }
        }
        saveTasks()
        hookServer.stop()
    }

    func handleProcessExit(taskId: String) {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }
        // Also ignore .starting — the old process is dying after a resume
        guard task.status != .completed && task.status != .stopped && task.status != .starting else { return }
        task.status = .completed
        task.lastActivityAt = Date()
        saveTasks()
    }

    private func handleWorking(sessionId: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        guard task.status != .completed && task.status != .stopped else { return }
        if task.status != .working {
            task.pendingPermission = nil
            task.status = .working
            task.lastActivityAt = Date()
            saveTasks()
        }
    }

    private func handleStop(sessionId: String, message: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        guard task.status != .completed && task.status != .stopped else { return }
        task.pendingPermission = nil
        task.status = .waitingForInput
        task.lastMessage = message
        task.lastActivityAt = Date()
        // Refresh usage for this task
        task.usage = SessionUsageParser.parseForSession(sessionId: sessionId)
        saveTasks()
        Notifier.notify(taskId: task.id, description: task.description)
    }

    private func handlePermission(sessionId: String, toolName: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        guard task.status != .completed && task.status != .stopped else { return }
        task.pendingPermission = toolName
        task.status = .waitingForInput
        task.lastMessage = "Permission needed for \(toolName)"
        task.lastActivityAt = Date()
        saveTasks()
        Notifier.notify(taskId: task.id, description: "\(task.description) — permission needed for \(toolName)")
    }

    private func handleNotification(sessionId: String, type: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        guard task.status != .completed && task.status != .stopped else { return }
        task.lastActivityAt = Date()
        switch type {
        case "permission_prompt":
            task.pendingPermission = "permission"
            task.status = .waitingForInput
            task.lastMessage = "Needs permission"
            saveTasks()
            Notifier.notify(taskId: task.id, description: "\(task.description) — needs permission")
        case "idle_prompt":
            task.status = .waitingForInput
            task.lastMessage = "Claude is idle"
            saveTasks()
            Notifier.notify(taskId: task.id, description: "\(task.description) — idle")
        case "elicitation_dialog":
            task.status = .waitingForInput
            task.lastMessage = "Claude is asking a question"
            saveTasks()
            Notifier.notify(taskId: task.id, description: "\(task.description) — asking a question")
        default:
            break
        }
    }
}
