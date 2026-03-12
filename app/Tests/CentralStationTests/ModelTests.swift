import Testing
import Foundation
import SwiftUI
@testable import CentralStationCore

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

    // MARK: - TaskStatus color & icon coverage

    @Test func taskStatusColorIsNonNilForAllCases() {
        let allCases: [TaskStatus] = [.pending, .starting, .working, .waitingForInput, .completed, .stopped, .error]
        for status in allCases {
            // Color has no Equatable conformance, so just access it to exercise the code path
            let _: Color = status.color
        }
    }

    @Test func taskStatusIconStrings() {
        #expect(TaskStatus.pending.icon == "circle")
        #expect(TaskStatus.starting.icon == "circle.dotted")
        #expect(TaskStatus.working.icon == "circle.fill")
        #expect(TaskStatus.waitingForInput.icon == "pause.circle.fill")
        #expect(TaskStatus.completed.icon == "checkmark.circle.fill")
        #expect(TaskStatus.stopped.icon == "stop.circle")
        #expect(TaskStatus.error.icon == "xmark.circle.fill")
    }

    // MARK: - AppTask init from TaskConfig

    @Test func appTaskInitFromTaskConfig() {
        let config = TaskConfig(id: "cfg-1", description: "Config task", prompt: "Do stuff", permissionMode: "auto")
        let task = AppTask(config: config, worktreePath: "/tmp/wt", projectPath: "/tmp/proj")

        #expect(task.id == "cfg-1")
        #expect(task.description == "Config task")
        #expect(task.prompt == "Do stuff")
        #expect(task.permissionMode == "auto")
        #expect(task.worktreePath == "/tmp/wt")
        #expect(task.projectPath == "/tmp/proj")
        #expect(!task.sessionId.isEmpty)
        #expect(task.status == .pending)
        #expect(task.isResume == false)
    }

    // MARK: - AppTask init from PersistedTask

    @Test func appTaskInitFromPersistedTask() {
        let persisted = PersistedTask(
            id: "p-1", description: "Persisted", prompt: "resume me",
            sessionId: "sess-42", worktreePath: "/wt", projectPath: "/proj",
            permissionMode: "default", status: .working,
            remoteAlias: "box", sshHost: "user@remote"
        )
        let task = AppTask(persisted: persisted)

        #expect(task.id == "p-1")
        #expect(task.description == "Persisted")
        #expect(task.prompt == "resume me")
        #expect(task.sessionId == "sess-42")
        #expect(task.worktreePath == "/wt")
        #expect(task.projectPath == "/proj")
        #expect(task.permissionMode == "default")
        #expect(task.status == .working)
        #expect(task.remoteAlias == "box")
        #expect(task.sshHost == "user@remote")
        #expect(task.isResume == true)
    }

    // MARK: - AppTask.toPersisted() round-trip

    @Test func appTaskToPersistedRoundTrip() {
        let task = AppTask(
            id: "rt-1", description: "Round trip", prompt: "go",
            worktreePath: "/wt", projectPath: "/proj",
            permissionMode: "auto", remoteAlias: "dev", sshHost: "u@h"
        )
        task.status = .completed

        let persisted = task.toPersisted()
        #expect(persisted.id == "rt-1")
        #expect(persisted.description == "Round trip")
        #expect(persisted.prompt == "go")
        #expect(persisted.sessionId == task.sessionId)
        #expect(persisted.worktreePath == "/wt")
        #expect(persisted.projectPath == "/proj")
        #expect(persisted.permissionMode == "auto")
        #expect(persisted.status == .completed)
        #expect(persisted.remoteAlias == "dev")
        #expect(persisted.sshHost == "u@h")
    }

    // MARK: - AppTask.isRemote

    @Test func appTaskIsRemote() {
        let remote = AppTask(
            id: "r1", description: "d", prompt: "p",
            worktreePath: "/w", projectPath: "/p", sshHost: "u@h"
        )
        #expect(remote.isRemote == true)

        let local = AppTask(
            id: "l1", description: "d", prompt: "p",
            worktreePath: "/w", projectPath: "/p"
        )
        #expect(local.isRemote == false)
    }

    // MARK: - AppTask.elapsed

    @Test func appTaskElapsedWhenStartedAtIsNil() {
        let task = AppTask(
            id: "e1", description: "d", prompt: "p",
            worktreePath: "/w", projectPath: "/p"
        )
        #expect(task.elapsed == "--")
    }

    @Test func appTaskElapsedWhenStartedAtIsSet() {
        let task = AppTask(
            id: "e2", description: "d", prompt: "p",
            worktreePath: "/w", projectPath: "/p"
        )
        // Set startedAt to 125 seconds ago => 2m 05s
        task.startedAt = Date().addingTimeInterval(-125)
        let elapsed = task.elapsed
        // Should match pattern like "2m 05s" (could be 2m 04s due to timing)
        #expect(elapsed.contains("m"))
        #expect(elapsed.contains("s"))
        #expect(elapsed != "--")
    }
}
