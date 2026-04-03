import Testing
import Foundation
import SwiftUI
@testable import CentralStationCore

@Suite("Model serialization")
struct ModelTests {
    @Test func persistedTaskRoundTrip() throws {
        let task = PersistedTask(
            id: "2026-04-03-task-1",
            description: "Test task",
            sessionId: "abc-123",
            worktreePath: "/tmp/wt",
            projectPath: "/tmp/proj",
            status: .working
        )

        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(PersistedTask.self, from: data)

        #expect(decoded.id == "2026-04-03-task-1")
        #expect(decoded.status == .working)
        #expect(decoded.description == "Test task")
    }

    @Test func persistedTaskDefaultsEmptyDescription() throws {
        let json = """
        {
            "id": "t1", "sessionId": "s",
            "worktreePath": "/w", "projectPath": "/p",
            "status": "Pending"
        }
        """
        let task = try JSONDecoder().decode(PersistedTask.self, from: json.data(using: .utf8)!)
        #expect(task.description == "")
    }

    @Test func taskStatusRawValues() {
        #expect(TaskStatus.pending.rawValue == "Pending")
        #expect(TaskStatus.working.rawValue == "Working")
        #expect(TaskStatus.waitingForInput.rawValue == "Needs Input")
        #expect(TaskStatus.completed.rawValue == "Completed")
        #expect(TaskStatus.error.rawValue == "Error")
    }

    @Test func taskStatusColorIsNonNilForAllCases() {
        let allCases: [TaskStatus] = [.pending, .starting, .working, .waitingForInput, .completed, .stopped, .error]
        for status in allCases {
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

    @Test func appTaskInitSimple() {
        let task = AppTask(
            id: "2026-04-03-task-1",
            worktreePath: "/tmp/wt",
            projectPath: "/tmp/proj"
        )

        #expect(task.id == "2026-04-03-task-1")
        #expect(task.description == "")
        #expect(task.worktreePath == "/tmp/wt")
        #expect(task.projectPath == "/tmp/proj")
        #expect(!task.sessionId.isEmpty)
        #expect(task.status == .pending)
    }

    @Test func appTaskInitFromPersistedTask() {
        let persisted = PersistedTask(
            id: "2026-04-03-task-1", description: "Persisted",
            sessionId: "sess-42", worktreePath: "/wt", projectPath: "/proj",
            status: .working
        )
        let task = AppTask(persisted: persisted)

        #expect(task.id == "2026-04-03-task-1")
        #expect(task.description == "Persisted")
        #expect(task.sessionId == "sess-42")
        #expect(task.worktreePath == "/wt")
        #expect(task.projectPath == "/proj")
        #expect(task.status == .working)
    }

    @Test func appTaskToPersistedRoundTrip() {
        let task = AppTask(
            id: "2026-04-03-task-1",
            worktreePath: "/wt",
            projectPath: "/proj"
        )
        task.description = "Round trip"
        task.status = .completed

        let persisted = task.toPersisted()
        #expect(persisted.id == "2026-04-03-task-1")
        #expect(persisted.description == "Round trip")
        #expect(persisted.sessionId == task.sessionId)
        #expect(persisted.status == .completed)
    }

    @Test func appTaskElapsedWhenStartedAtIsNil() {
        let task = AppTask(
            id: "e1",
            worktreePath: "/w",
            projectPath: "/p"
        )
        #expect(task.elapsed == "--")
    }

    @Test func appTaskElapsedWhenStartedAtIsSet() {
        let task = AppTask(
            id: "e2",
            worktreePath: "/w",
            projectPath: "/p"
        )
        task.startedAt = Date().addingTimeInterval(-125)
        let elapsed = task.elapsed
        #expect(elapsed.contains("m"))
        #expect(elapsed.contains("s"))
        #expect(elapsed != "--")
    }
}
