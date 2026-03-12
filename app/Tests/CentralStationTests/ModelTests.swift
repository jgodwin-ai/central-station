import Testing
import Foundation

private enum TaskStatus: String, Codable {
    case pending = "Pending"
    case starting = "Starting"
    case working = "Working"
    case waitingForInput = "Needs Input"
    case completed = "Completed"
    case stopped = "Stopped"
    case error = "Error"
}

private struct PersistedTask: Codable {
    let id: String
    let description: String
    let prompt: String
    let sessionId: String
    let worktreePath: String
    let projectPath: String
    let permissionMode: String?
    let status: TaskStatus
    var remoteAlias: String? = nil
    var sshHost: String? = nil
}

private struct RemoteConfig: Codable {
    var id: String
    var alias: String
    var sshHost: String
    var defaultDirectory: String?
}

@Suite("Model serialization")
struct ModelTests {
    @Test func persistedTaskRoundTrip() throws {
        let task = PersistedTask(
            id: "test-1",
            description: "Test task",
            prompt: "Do the thing",
            sessionId: "abc-123",
            worktreePath: "/tmp/wt",
            projectPath: "/tmp/proj",
            permissionMode: "auto",
            status: .working,
            remoteAlias: "devbox",
            sshHost: "user@10.0.1.5"
        )

        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(PersistedTask.self, from: data)

        #expect(decoded.id == "test-1")
        #expect(decoded.status == .working)
        #expect(decoded.remoteAlias == "devbox")
        #expect(decoded.sshHost == "user@10.0.1.5")
    }

    @Test func persistedTaskDefaultsNil() throws {
        let json = """
        {
            "id": "t1", "description": "d", "prompt": "p",
            "sessionId": "s", "worktreePath": "/w", "projectPath": "/p",
            "status": "Pending"
        }
        """
        let task = try JSONDecoder().decode(PersistedTask.self, from: json.data(using: .utf8)!)
        #expect(task.remoteAlias == nil)
        #expect(task.sshHost == nil)
    }

    @Test func remoteConfigRoundTrip() throws {
        let remote = RemoteConfig(id: "r1", alias: "Dev Server", sshHost: "user@host", defaultDirectory: "/home/user/proj")
        let data = try JSONEncoder().encode(remote)
        let decoded = try JSONDecoder().decode(RemoteConfig.self, from: data)

        #expect(decoded.alias == "Dev Server")
        #expect(decoded.sshHost == "user@host")
        #expect(decoded.defaultDirectory == "/home/user/proj")
    }

    @Test func taskStatusRawValues() {
        #expect(TaskStatus.pending.rawValue == "Pending")
        #expect(TaskStatus.working.rawValue == "Working")
        #expect(TaskStatus.waitingForInput.rawValue == "Needs Input")
        #expect(TaskStatus.completed.rawValue == "Completed")
        #expect(TaskStatus.error.rawValue == "Error")
    }
}
