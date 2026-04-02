import Foundation
import SwiftUI

public enum TaskStatus: String, Sendable, Codable {
    case pending = "Pending"
    case starting = "Starting"
    case working = "Working"
    case waitingForInput = "Needs Input"
    case completed = "Completed"
    case stopped = "Stopped"
    case error = "Error"

    public var color: Color {
        switch self {
        case .pending: .gray
        case .starting: .yellow
        case .working: .green
        case .waitingForInput: .orange
        case .completed: .cyan
        case .stopped: .secondary
        case .error: .red
        }
    }

    public var icon: String {
        switch self {
        case .pending: "circle"
        case .starting: "circle.dotted"
        case .working: "circle.fill"
        case .waitingForInput: "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .stopped: "stop.circle"
        case .error: "xmark.circle.fill"
        }
    }
}

public struct PersistedTask: Codable {
    public let id: String
    public let description: String
    public let prompt: String
    public let sessionId: String
    public let worktreePath: String
    public let projectPath: String
    public let permissionMode: String?
    public let status: TaskStatus
    public var remoteAlias: String?
    public var sshHost: String?

    public init(id: String, description: String, prompt: String, sessionId: String,
                worktreePath: String, projectPath: String, permissionMode: String?,
                status: TaskStatus, remoteAlias: String? = nil, sshHost: String? = nil) {
        self.id = id
        self.description = description
        self.prompt = prompt
        self.sessionId = sessionId
        self.worktreePath = worktreePath
        self.projectPath = projectPath
        self.permissionMode = permissionMode
        self.status = status
        self.remoteAlias = remoteAlias
        self.sshHost = sshHost
    }
}

@Observable
public final class AppTask: Identifiable, @unchecked Sendable {
    public let id: String
    public let description: String
    public let prompt: String
    public let sessionId: String
    public var worktreePath: String
    public var projectPath: String
    public var terminalWindowId: Int?
    public var status: TaskStatus = .pending
    public var startedAt: Date?
    public var lastActivityAt: Date?
    public var lastMessage: String?
    public var permissionMode: String?
    public var diff: String?
    public var pendingPermission: String?
    public var remoteAlias: String?
    public var sshHost: String?
    public var isResume: Bool = false
    public var usage: SessionUsage?

    public var isRemote: Bool { sshHost != nil }
    public var hasWorktree: Bool { worktreePath != projectPath }

    public var elapsed: String {
        guard let startedAt else { return "--" }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        let m = seconds / 60
        let s = seconds % 60
        return "\(m)m \(String(format: "%02d", s))s"
    }

    public init(config: TaskConfig, worktreePath: String, projectPath: String) {
        self.id = config.id
        self.description = config.description
        self.prompt = config.prompt
        self.sessionId = UUID().uuidString.lowercased()
        self.worktreePath = worktreePath
        self.projectPath = projectPath
        self.permissionMode = config.permissionMode
    }

    public init(id: String, description: String, prompt: String, worktreePath: String, projectPath: String, permissionMode: String? = nil, remoteAlias: String? = nil, sshHost: String? = nil) {
        self.id = id
        self.description = description
        self.prompt = prompt
        self.sessionId = UUID().uuidString.lowercased()
        self.worktreePath = worktreePath
        self.projectPath = projectPath
        self.permissionMode = permissionMode
        self.remoteAlias = remoteAlias
        self.sshHost = sshHost
    }

    public init(persisted: PersistedTask) {
        self.id = persisted.id
        self.description = persisted.description
        self.prompt = persisted.prompt
        self.sessionId = persisted.sessionId
        self.worktreePath = persisted.worktreePath
        self.projectPath = persisted.projectPath
        self.permissionMode = persisted.permissionMode
        self.status = persisted.status
        self.remoteAlias = persisted.remoteAlias
        self.sshHost = persisted.sshHost
        self.isResume = true
    }

    public static func groupByRepo(_ tasks: [AppTask]) -> [(directory: String, label: String, tasks: [AppTask])] {
        var groups: [String: [AppTask]] = [:]
        for task in tasks {
            groups[task.projectPath, default: []].append(task)
        }
        return groups.sorted { $0.key < $1.key }.map { dir, tasks in
            let label = (dir as NSString).lastPathComponent
            return (directory: dir, label: label, tasks: tasks)
        }
    }

    public func toPersisted() -> PersistedTask {
        PersistedTask(
            id: id, description: description, prompt: prompt,
            sessionId: sessionId, worktreePath: worktreePath,
            projectPath: projectPath, permissionMode: permissionMode,
            status: status, remoteAlias: remoteAlias, sshHost: sshHost
        )
    }
}
