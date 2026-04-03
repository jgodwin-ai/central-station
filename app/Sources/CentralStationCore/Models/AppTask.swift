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
    public var description: String
    public let sessionId: String
    public let worktreePath: String
    public let projectPath: String
    public var status: TaskStatus

    public init(id: String, description: String = "", sessionId: String,
                worktreePath: String, projectPath: String, status: TaskStatus) {
        self.id = id
        self.description = description
        self.sessionId = sessionId
        self.worktreePath = worktreePath
        self.projectPath = projectPath
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        sessionId = try container.decode(String.self, forKey: .sessionId)
        worktreePath = try container.decode(String.self, forKey: .worktreePath)
        projectPath = try container.decode(String.self, forKey: .projectPath)
        status = try container.decode(TaskStatus.self, forKey: .status)
    }
}

@Observable
public final class AppTask: Identifiable, @unchecked Sendable {
    public let id: String
    public var description: String
    public let sessionId: String
    public var worktreePath: String
    public var projectPath: String
    public var terminalWindowId: Int?
    public var status: TaskStatus = .pending
    public var startedAt: Date?
    public var lastActivityAt: Date?
    public var lastMessage: String?
    public var diff: String?
    public var pendingPermission: String?
    public var usage: SessionUsage?

    public var elapsed: String {
        guard let startedAt else { return "--" }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        let m = seconds / 60
        let s = seconds % 60
        return "\(m)m \(String(format: "%02d", s))s"
    }

    public init(id: String, worktreePath: String, projectPath: String) {
        self.id = id
        self.description = ""
        self.sessionId = UUID().uuidString
        self.worktreePath = worktreePath
        self.projectPath = projectPath
    }

    public init(persisted: PersistedTask) {
        self.id = persisted.id
        self.description = persisted.description
        self.sessionId = persisted.sessionId
        self.worktreePath = persisted.worktreePath
        self.projectPath = persisted.projectPath
        self.status = persisted.status
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
            id: id, description: description,
            sessionId: sessionId,
            worktreePath: worktreePath, projectPath: projectPath,
            status: status
        )
    }
}
