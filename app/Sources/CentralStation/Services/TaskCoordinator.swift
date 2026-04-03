import Foundation
import SwiftUI

@Observable
@MainActor
final class TaskCoordinator {
    var tasks: [AppTask] = []
    var projectPath: String = ""
    var poppedOutTaskIds: Set<String> = []
    private let hookServer = HookServer()
    private var hookSecret = TerminalLauncher.installedSecret() ?? HookSecret.generate()
    let remoteStore = RemoteStore()
    private var sessionToTaskId: [String: String] = [:]

    private static var persistencePath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/central-station-tasks.json")
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

    func loadPersistedTasks() {
        guard let data = FileManager.default.contents(atPath: Self.persistencePath),
              let persisted = try? JSONDecoder().decode([PersistedTask].self, from: data) else {
            return
        }
        for p in persisted {
            // Skip if worktree no longer exists
            guard FileManager.default.fileExists(atPath: p.worktreePath) else { continue }
            // Skip if already loaded (e.g., from config file)
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

    func loadConfig(from path: String) throws {
        let config = try ConfigLoader.load(from: path)
        self.projectPath = config.project
        for taskConfig in config.tasks {
            let sanitizedId = Validation.sanitizeTaskId(taskConfig.id)
            guard !sanitizedId.isEmpty else { continue }
            guard !tasks.contains(where: { $0.id == sanitizedId }) else { continue }
            let sanitizedConfig = taskConfig.withId(sanitizedId)
            let task = AppTask(config: sanitizedConfig, worktreePath: "", projectPath: self.projectPath)
            tasks.append(task)
            sessionToTaskId[task.sessionId] = task.id
        }
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
        hookServer.onWorking = { [weak self] sessionId in
            self?.handleWorking(sessionId: sessionId)
        }
        hookServer.onPermissionRequest = { [weak self] sessionId, toolName in
            self?.handlePermission(sessionId: sessionId, toolName: toolName)
        }
        hookServer.onNotification = { [weak self] sessionId, notifType in
            self?.handleNotification(sessionId: sessionId, type: notifType)
        }
        hookServer.onSessionEnd = { [weak self] sessionId in
            self?.handleSessionEnd(sessionId: sessionId)
        }

        // Only create worktrees for new (pending) tasks from config
        let pendingTasks = tasks.filter { $0.status == .pending }
        if !pendingTasks.isEmpty {
            try await WorktreeManager.ensureGitRepo(at: projectPath)
        }

        for task in pendingTasks {
            let worktreePath = try await WorktreeManager.createWorktree(
                projectPath: projectPath, taskId: task.id
            )
            task.worktreePath = worktreePath
            task.startedAt = Date()
            task.status = .working
        }

        saveTasks()
    }

    func addTask(id: String, description: String, prompt: String, permissionMode: String? = nil, customProjectPath: String? = nil, useWorktree: Bool = true) async throws {
        let sanitizedId = Validation.sanitizeTaskId(id)
        let effectivePath = customProjectPath ?? projectPath
        try await WorktreeManager.ensureGitRepo(at: effectivePath)
        let worktreePath: String
        if useWorktree {
            worktreePath = try await WorktreeManager.createWorktree(
                projectPath: effectivePath, taskId: sanitizedId
            )
        } else {
            worktreePath = effectivePath
        }
        let task = AppTask(
            id: sanitizedId,
            description: description,
            prompt: prompt,
            worktreePath: worktreePath,
            projectPath: effectivePath,
            permissionMode: permissionMode
        )

        tasks.append(task)
        sessionToTaskId[task.sessionId] = task.id
        task.startedAt = Date()
        task.status = .working
        saveTasks()
    }

    func addRemoteTask(id: String, description: String, prompt: String, permissionMode: String?, remote: RemoteConfig, remotePath: String) async throws {
        let sanitizedId = Validation.sanitizeTaskId(id)
        try await TerminalLauncher.installHooksOnRemote(host: remote.sshHost, secret: hookSecret)
        try await WorktreeManager.ensureGitRepoRemote(host: remote.sshHost, at: remotePath)
        let worktreePath = try await WorktreeManager.createWorktreeRemote(
            host: remote.sshHost, projectPath: remotePath, taskId: sanitizedId
        )
        let task = AppTask(
            id: sanitizedId, description: description, prompt: prompt,
            worktreePath: worktreePath, projectPath: remotePath,
            permissionMode: permissionMode,
            remoteAlias: remote.alias, sshHost: remote.sshHost
        )
        tasks.append(task)
        sessionToTaskId[task.sessionId] = task.id
        task.startedAt = Date()
        task.status = .working
        saveTasks()

        // Update default directory on remote
        var updated = remote
        updated.defaultDirectory = remotePath
        remoteStore.update(updated)
    }

    func resumeTask(_ task: AppTask) {
        TerminalStore.shared.killTerminal(for: task.id)
        sessionToTaskId[task.sessionId] = task.id
        task.isResume = true
        task.startedAt = Date()
        task.status = .starting
        saveTasks()
    }

    func refreshDiff(for task: AppTask) async {
        if let host = task.sshHost {
            task.diff = await WorktreeManager.getDiffRemote(host: host, worktreePath: task.worktreePath)
        } else {
            task.diff = await WorktreeManager.getDiff(worktreePath: task.worktreePath)
        }
    }

    func handleMergeAction(task: AppTask, action: MergeAction) async throws -> String? {
        let message: String
        switch action {
        case .mergeToMain(let msg): message = msg
        case .createBranch(let msg): message = msg
        case .createPR(let msg): message = msg
        }

        if let host = task.sshHost {
            try await WorktreeManager.commitWorktreeRemote(host: host, worktreePath: task.worktreePath, message: message)
            var prURL: String?
            switch action {
            case .mergeToMain:
                try await WorktreeManager.mergeToMainRemote(host: host, projectPath: task.projectPath, taskId: task.id, message: message)
            case .createBranch:
                try await WorktreeManager.pushBranchRemote(host: host, projectPath: task.projectPath, taskId: task.id)
            case .createPR:
                prURL = try await WorktreeManager.createPRRemote(host: host, projectPath: task.projectPath, taskId: task.id, message: message)
            }
            task.status = .completed
            saveTasks()
            return prURL
        } else {
            try await WorktreeManager.commitWorktree(worktreePath: task.worktreePath, message: message)
            var prURL: String?
            switch action {
            case .mergeToMain:
                if task.hasWorktree {
                    try await WorktreeManager.mergeToMain(projectPath: task.projectPath, taskId: task.id, message: message)
                }
                // No worktree = already on main, commit is enough
            case .createBranch:
                try await WorktreeManager.pushBranch(projectPath: task.projectPath, taskId: task.id, hasWorktree: task.hasWorktree)
            case .createPR:
                prURL = try await WorktreeManager.createPR(projectPath: task.projectPath, taskId: task.id, message: message, hasWorktree: task.hasWorktree)
            }
            task.status = .completed
            saveTasks()
            return prURL
        }
    }

    func deleteTask(_ task: AppTask) async {
        TerminalStore.shared.killTerminal(for: task.id)
        if let host = task.sshHost {
            await WorktreeManager.removeWorktreeRemote(host: host, projectPath: task.projectPath, taskId: task.id)
        } else {
            await WorktreeManager.removeWorktree(projectPath: task.projectPath, taskId: task.id)
        }
        sessionToTaskId.removeValue(forKey: task.sessionId)
        tasks.removeAll { $0.id == task.id }
        saveTasks()
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

    private func handleSessionEnd(sessionId: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        guard task.status != .completed && task.status != .stopped else { return }
        task.status = .completed
        task.lastActivityAt = Date()
        saveTasks()
    }
}
