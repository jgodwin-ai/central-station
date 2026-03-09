import Foundation
import SwiftUI

enum TaskStatus: String, Sendable {
    case pending = "Pending"
    case starting = "Starting"
    case working = "Working"
    case waitingForInput = "Needs Input"
    case completed = "Completed"
    case error = "Error"

    var color: Color {
        switch self {
        case .pending: .gray
        case .starting: .yellow
        case .working: .green
        case .waitingForInput: .orange
        case .completed: .cyan
        case .error: .red
        }
    }

    var icon: String {
        switch self {
        case .pending: "circle"
        case .starting: "circle.dotted"
        case .working: "circle.fill"
        case .waitingForInput: "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        }
    }
}

@Observable
final class AppTask: Identifiable, @unchecked Sendable {
    let id: String
    let description: String
    let prompt: String
    let sessionId: String
    var worktreePath: String
    var projectPath: String
    var terminalWindowId: Int?
    var status: TaskStatus = .pending
    var startedAt: Date?
    var lastActivityAt: Date?
    var lastMessage: String?
    var permissionMode: String?
    var diff: String?
    var pendingPermission: String?

    var elapsed: String {
        guard let startedAt else { return "--" }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        let m = seconds / 60
        let s = seconds % 60
        return "\(m)m \(String(format: "%02d", s))s"
    }

    init(config: TaskConfig, worktreePath: String, projectPath: String) {
        self.id = config.id
        self.description = config.description
        self.prompt = config.prompt
        self.sessionId = UUID().uuidString.lowercased()
        self.worktreePath = worktreePath
        self.projectPath = projectPath
        self.permissionMode = config.permissionMode
    }

    init(id: String, description: String, prompt: String, worktreePath: String, projectPath: String, permissionMode: String? = nil) {
        self.id = id
        self.description = description
        self.prompt = prompt
        self.sessionId = UUID().uuidString.lowercased()
        self.worktreePath = worktreePath
        self.projectPath = projectPath
        self.permissionMode = permissionMode
    }
}
