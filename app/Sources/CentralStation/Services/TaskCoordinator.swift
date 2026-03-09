import Foundation
import SwiftUI

@Observable
@MainActor
final class TaskCoordinator {
    var tasks: [AppTask] = []
    var projectPath: String = ""
    var poppedOutTaskIds: Set<String> = []
    private let hookServer = HookServer()
    private var sessionToTaskId: [String: String] = [:]

    var needsInputCount: Int {
        tasks.filter { $0.status == .waitingForInput }.count
    }

    var hooksInstalled: Bool = false

    func checkHooksInstalled() {
        hooksInstalled = TerminalLauncher.hooksInstalled()
    }

    func installHooks() throws {
        try TerminalLauncher.installHooks()
        hooksInstalled = true
    }

    func loadConfig(from path: String) throws {
        let config = try ConfigLoader.load(from: path)
        self.projectPath = config.project
        for taskConfig in config.tasks {
            let task = AppTask(config: taskConfig, worktreePath: "", projectPath: self.projectPath)
            tasks.append(task)
            sessionToTaskId[task.sessionId] = task.id
        }
    }

    var needsPermissionCount: Int {
        tasks.filter { $0.pendingPermission != nil }.count
    }

    func start() async throws {
        try hookServer.start()
        hookServer.onStop = { [weak self] sessionId, message in
            self?.handleStop(sessionId: sessionId, message: message)
        }
        hookServer.onPermissionRequest = { [weak self] sessionId, toolName in
            self?.handlePermission(sessionId: sessionId, toolName: toolName)
        }

        if !tasks.isEmpty {
            try await WorktreeManager.ensureGitRepo(at: projectPath)
        }

        // Create worktrees for pre-configured tasks
        for task in tasks {
            let worktreePath = try await WorktreeManager.createWorktree(
                projectPath: projectPath, taskId: task.id
            )
            task.worktreePath = worktreePath
            task.startedAt = Date()
            task.status = .working
        }
    }

    func addTask(id: String, description: String, prompt: String, permissionMode: String? = nil, customProjectPath: String? = nil) async throws {
        let effectivePath = customProjectPath ?? projectPath
        try await WorktreeManager.ensureGitRepo(at: effectivePath)
        let worktreePath = try await WorktreeManager.createWorktree(
            projectPath: effectivePath, taskId: id
        )
        let task = AppTask(
            id: id,
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
    }

    func refreshDiff(for task: AppTask) async {
        task.diff = await WorktreeManager.getDiff(worktreePath: task.worktreePath)
    }

    func handleMergeAction(task: AppTask, action: MergeAction) async throws -> String? {
        let message: String
        switch action {
        case .mergeOnly(let msg): message = msg
        case .mergeAndPush(let msg): message = msg
        case .mergeAndPR(let msg): message = msg
        }

        try await WorktreeManager.commitAndMerge(
            worktreePath: task.worktreePath,
            projectPath: task.projectPath,
            taskId: task.id,
            message: message
        )

        var prURL: String?
        switch action {
        case .mergeOnly:
            break
        case .mergeAndPush:
            try await WorktreeManager.pushBranch(projectPath: task.projectPath, taskId: task.id)
        case .mergeAndPR:
            prURL = try await WorktreeManager.createPR(projectPath: task.projectPath, taskId: task.id, message: message)
        }

        task.status = .completed
        return prURL
    }

    func stop() {
        hookServer.stop()
    }

    private func handleStop(sessionId: String, message: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        task.pendingPermission = nil
        task.status = .waitingForInput
        task.lastMessage = message
        task.lastActivityAt = Date()
        Notifier.notify(taskId: task.id, description: task.description)
    }

    private func handlePermission(sessionId: String, toolName: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        task.pendingPermission = toolName
        task.lastActivityAt = Date()
    }
}
