import Testing
import Foundation
@testable import CentralStationCore

private struct HookPayload: Decodable {
    let session_id: String?
    let hook_event_name: String?
    let stop_hook_active: Bool?
    let last_assistant_message: String?
    let tool_name: String?
    let tool_input: [String: String]?
    let notification_type: String?
}

/// Mirrors TaskCoordinator's handler logic for unit testing
private struct StatusHandler {
    var tasks: [AppTask]

    mutating func handleProcessExit(taskId: String) {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }
        // Also ignore .starting — the old process is dying after a resume
        guard task.status != .completed && task.status != .stopped && task.status != .starting else { return }
        task.status = .completed
        task.lastActivityAt = Date()
    }

    mutating func handleWorking(sessionId: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        guard task.status != .completed && task.status != .stopped else { return }
        if task.status != .working {
            task.pendingPermission = nil
            task.status = .working
            task.lastActivityAt = Date()
        }
    }

    mutating func handleStop(sessionId: String, message: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        guard task.status != .completed && task.status != .stopped else { return }
        task.pendingPermission = nil
        task.status = .waitingForInput
        task.lastMessage = message
        task.lastActivityAt = Date()
    }

    mutating func handlePermission(sessionId: String, toolName: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        guard task.status != .completed && task.status != .stopped else { return }
        task.pendingPermission = toolName
        task.status = .waitingForInput
        task.lastMessage = "Permission needed for \(toolName)"
        task.lastActivityAt = Date()
    }

    mutating func handleNotification(sessionId: String, type: String) {
        guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
        guard task.status != .completed && task.status != .stopped else { return }
        task.lastActivityAt = Date()
        switch type {
        case "permission_prompt":
            task.pendingPermission = "permission"
            task.status = .waitingForInput
            task.lastMessage = "Needs permission"
        case "idle_prompt":
            task.status = .waitingForInput
            task.lastMessage = "Claude is idle"
        case "elicitation_dialog":
            task.status = .waitingForInput
            task.lastMessage = "Claude is asking a question"
        default:
            break
        }
    }

    mutating func resumeTask(_ task: AppTask) {
        task.status = .starting
    }
}

private func makeTask(sessionId: String, status: TaskStatus = .pending) -> AppTask {
    let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
    task.status = status
    return task
}

// MARK: - Status Transition Tests

@Suite("Status transitions")
struct StatusTransitionTests {

    @Test func stopHookActiveTrue_setsWorking() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .waitingForInput
        task.pendingPermission = "Write"
        var handler = StatusHandler(tasks: [task])

        handler.handleWorking(sessionId: task.sessionId)

        #expect(task.status == .working)
        #expect(task.pendingPermission == nil)
        #expect(task.lastActivityAt != nil)
    }

    @Test func stopHookActiveFalse_setsWaitingForInput() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        handler.handleStop(sessionId: task.sessionId, message: "Done with that task")

        #expect(task.status == .waitingForInput)
        #expect(task.lastMessage == "Done with that task")
        #expect(task.pendingPermission == nil)
    }

    @Test func workingToWorkingIsNoOp() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        let before = Date()
        task.lastActivityAt = before
        var handler = StatusHandler(tasks: [task])

        handler.handleWorking(sessionId: task.sessionId)

        #expect(task.status == .working)
        #expect(task.lastActivityAt == before)
    }

    @Test func permissionSetsWaitingForInput() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        handler.handlePermission(sessionId: task.sessionId, toolName: "Bash")

        #expect(task.status == .waitingForInput)
        #expect(task.pendingPermission == "Bash")
        #expect(task.lastMessage == "Permission needed for Bash")
    }

    @Test func workingClearsPermission() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .waitingForInput
        task.pendingPermission = "Bash"
        var handler = StatusHandler(tasks: [task])

        handler.handleWorking(sessionId: task.sessionId)

        #expect(task.status == .working)
        #expect(task.pendingPermission == nil)
    }

    @Test func unknownSessionIdIsIgnored() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        handler.handleWorking(sessionId: "unknown-session")
        handler.handleStop(sessionId: "unknown-session", message: "hi")
        handler.handlePermission(sessionId: "unknown-session", toolName: "Read")

        #expect(task.status == .working)
    }

    @Test func notificationPermissionPrompt() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        handler.handleNotification(sessionId: task.sessionId, type: "permission_prompt")

        #expect(task.status == .waitingForInput)
        #expect(task.pendingPermission == "permission")
        #expect(task.lastMessage == "Needs permission")
    }

    @Test func notificationIdlePrompt() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        handler.handleNotification(sessionId: task.sessionId, type: "idle_prompt")

        #expect(task.status == .waitingForInput)
        #expect(task.lastMessage == "Claude is idle")
    }

    @Test func notificationElicitation() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        handler.handleNotification(sessionId: task.sessionId, type: "elicitation_dialog")

        #expect(task.status == .waitingForInput)
        #expect(task.lastMessage == "Claude is asking a question")
    }

    @Test func unknownNotificationTypeIgnored() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        handler.handleNotification(sessionId: task.sessionId, type: "some_future_type")

        #expect(task.status == .working)
    }

    @Test func fullCycle_working_stop_working() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        handler.handleStop(sessionId: task.sessionId, message: "What should I do next?")
        #expect(task.status == .waitingForInput)

        handler.handleWorking(sessionId: task.sessionId)
        #expect(task.status == .working)
    }

    // MARK: - Process exit tests

    @Test func processExitSetsCompleted() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        handler.handleProcessExit(taskId: task.id)

        #expect(task.status == .completed)
        #expect(task.lastActivityAt != nil)
    }

    @Test func processExitFromWaitingForInput() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .waitingForInput
        var handler = StatusHandler(tasks: [task])

        handler.handleProcessExit(taskId: task.id)

        #expect(task.status == .completed)
    }

    @Test func processExitIgnoredForAlreadyCompleted() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .completed
        let before = Date()
        task.lastActivityAt = before
        var handler = StatusHandler(tasks: [task])

        handler.handleProcessExit(taskId: task.id)

        #expect(task.status == .completed)
        #expect(task.lastActivityAt == before)
    }

    @Test func processExitIgnoredForStopped() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .stopped
        var handler = StatusHandler(tasks: [task])

        handler.handleProcessExit(taskId: task.id)

        #expect(task.status == .stopped)
    }

    @Test func processExitIgnoredForStarting() {
        // Race condition: old process dies after resumeTask sets .starting
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .starting
        var handler = StatusHandler(tasks: [task])

        handler.handleProcessExit(taskId: task.id)

        #expect(task.status == .starting)
    }

    @Test func resumeRaceCondition_oldProcessExitDoesNotBlockHooks() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        // Simulate resume: kill old process, set starting
        handler.resumeTask(task)
        #expect(task.status == .starting)

        // Old process dies — must NOT mark completed
        handler.handleProcessExit(taskId: task.id)
        #expect(task.status == .starting)

        // New process fires hooks — must still work
        handler.handleWorking(sessionId: task.sessionId)
        #expect(task.status == .working)

        handler.handleStop(sessionId: task.sessionId, message: "Done")
        #expect(task.status == .waitingForInput)
    }

    @Test func processExitUnknownTaskIdIgnored() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        handler.handleProcessExit(taskId: "unknown-task")

        #expect(task.status == .working)
    }

    // MARK: - Race condition: hook events must not override completed/stopped

    @Test func stopHookDoesNotOverrideCompleted() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        // Process exits first, marking completed
        handler.handleProcessExit(taskId: task.id)
        #expect(task.status == .completed)

        // Late stop hook arrives — must NOT override completed
        handler.handleStop(sessionId: task.sessionId, message: "late message")
        #expect(task.status == .completed)
    }

    @Test func workingHookDoesNotOverrideCompleted() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .completed
        var handler = StatusHandler(tasks: [task])

        handler.handleWorking(sessionId: task.sessionId)

        #expect(task.status == .completed)
    }

    @Test func permissionHookDoesNotOverrideCompleted() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .completed
        var handler = StatusHandler(tasks: [task])

        handler.handlePermission(sessionId: task.sessionId, toolName: "Bash")

        #expect(task.status == .completed)
        #expect(task.pendingPermission == nil)
    }

    @Test func notificationHookDoesNotOverrideCompleted() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .completed
        var handler = StatusHandler(tasks: [task])

        handler.handleNotification(sessionId: task.sessionId, type: "idle_prompt")

        #expect(task.status == .completed)
    }

    @Test func hooksDoNotOverrideStopped() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .stopped
        var handler = StatusHandler(tasks: [task])

        handler.handleWorking(sessionId: task.sessionId)
        #expect(task.status == .stopped)

        handler.handleStop(sessionId: task.sessionId, message: "msg")
        #expect(task.status == .stopped)

        handler.handlePermission(sessionId: task.sessionId, toolName: "Read")
        #expect(task.status == .stopped)

        handler.handleNotification(sessionId: task.sessionId, type: "permission_prompt")
        #expect(task.status == .stopped)
    }

    @Test func fullLifecycle_working_stop_processExit() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        var handler = StatusHandler(tasks: [task])

        // Claude stops (waiting for input)
        handler.handleStop(sessionId: task.sessionId, message: "All done!")
        #expect(task.status == .waitingForInput)

        // User exits Claude Code — process terminates
        handler.handleProcessExit(taskId: task.id)
        #expect(task.status == .completed)

        // Late hook must not revert
        handler.handleStop(sessionId: task.sessionId, message: "stale")
        #expect(task.status == .completed)
    }
}

// MARK: - Resume Tests

@Suite("Resume logic")
struct ResumeTests {

    @Test func resumeSetsStartingStatus() {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .stopped
        var handler = StatusHandler(tasks: [task])

        handler.resumeTask(task)

        #expect(task.status == .starting)
    }
}

// MARK: - Hook Payload Parsing Tests

@Suite("Hook payload parsing")
struct HookPayloadTests {

    @Test func stopHookActivePayload() throws {
        let json = """
        {
            "session_id": "s1",
            "stop_hook_active": true,
            "last_assistant_message": "Working on it..."
        }
        """
        let payload = try JSONDecoder().decode(HookPayload.self, from: json.data(using: .utf8)!)

        #expect(payload.session_id == "s1")
        #expect(payload.stop_hook_active == true)
        #expect(payload.last_assistant_message == "Working on it...")
    }

    @Test func stopHookInactivePayload() throws {
        let json = """
        {
            "session_id": "s1",
            "stop_hook_active": false,
            "last_assistant_message": "Done! What's next?"
        }
        """
        let payload = try JSONDecoder().decode(HookPayload.self, from: json.data(using: .utf8)!)

        #expect(payload.stop_hook_active == false)
    }

    @Test func notificationPayload() throws {
        let json = """
        {
            "session_id": "s1",
            "notification_type": "permission_prompt"
        }
        """
        let payload = try JSONDecoder().decode(HookPayload.self, from: json.data(using: .utf8)!)

        #expect(payload.notification_type == "permission_prompt")
        #expect(payload.stop_hook_active == nil)
    }

    @Test func permissionPayload() throws {
        let json = """
        {
            "session_id": "s1",
            "tool_name": "Bash"
        }
        """
        let payload = try JSONDecoder().decode(HookPayload.self, from: json.data(using: .utf8)!)

        #expect(payload.tool_name == "Bash")
    }

    @Test func minimalPayload() throws {
        let json = "{}"
        let payload = try JSONDecoder().decode(HookPayload.self, from: json.data(using: .utf8)!)

        #expect(payload.session_id == nil)
        #expect(payload.stop_hook_active == nil)
    }
}

// MARK: - Hook End-to-End Tests

/// Tests the full chain: payload → routing → handler → final task state.
/// Catches composition bugs where routing and handling are individually correct
/// but don't work together (e.g. SubagentStop routed to wrong handler).
@Suite("Hook end-to-end")
struct HookEndToEndTests {

    /// Combined routing + handling — mirrors HookServer.processRequest → TaskCoordinator
    private func dispatch(endpoint: String, payload: HookPayload, handler: inout StatusHandler) {
        if endpoint == "/hook/stop" {
            if payload.stop_hook_active == true { return }
            guard let sessionId = payload.session_id else { return }
            if payload.hook_event_name == "SubagentStop" {
                handler.handleWorking(sessionId: sessionId)
            } else {
                handler.handleStop(sessionId: sessionId, message: payload.last_assistant_message ?? "")
            }
        } else if endpoint == "/hook/prompt" {
            guard let sessionId = payload.session_id else { return }
            handler.handleWorking(sessionId: sessionId)
        } else if endpoint == "/hook/notification" {
            guard let sessionId = payload.session_id else { return }
            let notifType = payload.notification_type ?? payload.hook_event_name ?? "unknown"
            handler.handleNotification(sessionId: sessionId, type: notifType)
        } else if endpoint == "/hook/permission" {
            guard let sessionId = payload.session_id else { return }
            let toolName = payload.tool_name ?? "unknown"
            handler.handlePermission(sessionId: sessionId, toolName: toolName)
        }
    }

    private func makeWorkingTask() -> (AppTask, StatusHandler) {
        let task = AppTask(id: "t1", worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = .working
        let handler = StatusHandler(tasks: [task])
        return (task, handler)
    }

    // MARK: - Stop

    @Test func stop_setsWaitingForInput() {
        var (task, handler) = makeWorkingTask()
        let payload = HookPayload(session_id: task.sessionId, hook_event_name: "Stop",
                                   stop_hook_active: false, last_assistant_message: "All done!",
                                   tool_name: nil, tool_input: nil, notification_type: nil)

        dispatch(endpoint: "/hook/stop", payload: payload, handler: &handler)

        #expect(task.status == .waitingForInput)
        #expect(task.lastMessage == "All done!")
        #expect(task.pendingPermission == nil)
    }

    @Test func stop_hookActive_ignored() {
        var (task, handler) = makeWorkingTask()
        let payload = HookPayload(session_id: task.sessionId, hook_event_name: "Stop",
                                   stop_hook_active: true, last_assistant_message: "Loop",
                                   tool_name: nil, tool_input: nil, notification_type: nil)

        dispatch(endpoint: "/hook/stop", payload: payload, handler: &handler)

        #expect(task.status == .working,
                "stop_hook_active=true must be ignored to prevent loops")
    }

    // MARK: - SubagentStop

    @Test func subagentStop_keepsWorking() {
        var (task, handler) = makeWorkingTask()
        task.lastMessage = "Running subagents..."
        let payload = HookPayload(session_id: task.sessionId, hook_event_name: "SubagentStop",
                                   stop_hook_active: false, last_assistant_message: "Subagent done",
                                   tool_name: nil, tool_input: nil, notification_type: nil)

        dispatch(endpoint: "/hook/stop", payload: payload, handler: &handler)

        #expect(task.status == .working,
                "SubagentStop must not flip to .waitingForInput — main agent still running")
        #expect(task.lastMessage == "Running subagents...",
                "SubagentStop must not overwrite lastMessage")
        #expect(task.pendingPermission == nil)
    }

    // MARK: - UserPromptSubmit

    @Test func userPromptSubmit_setsWorking() {
        var (task, handler) = makeWorkingTask()
        task.status = .waitingForInput
        task.pendingPermission = "Bash"
        let payload = HookPayload(session_id: task.sessionId, hook_event_name: "UserPromptSubmit",
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: nil)

        dispatch(endpoint: "/hook/prompt", payload: payload, handler: &handler)

        #expect(task.status == .working)
        #expect(task.pendingPermission == nil,
                "UserPromptSubmit must clear pending permission")
    }

    // MARK: - Notification

    @Test func notification_permissionPrompt_setsWaitingForInput() {
        var (task, handler) = makeWorkingTask()
        let payload = HookPayload(session_id: task.sessionId, hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: "permission_prompt")

        dispatch(endpoint: "/hook/notification", payload: payload, handler: &handler)

        #expect(task.status == .waitingForInput)
        #expect(task.pendingPermission == "permission")
        #expect(task.lastMessage == "Needs permission")
    }

    @Test func notification_idlePrompt_setsWaitingForInput() {
        var (task, handler) = makeWorkingTask()
        let payload = HookPayload(session_id: task.sessionId, hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: "idle_prompt")

        dispatch(endpoint: "/hook/notification", payload: payload, handler: &handler)

        #expect(task.status == .waitingForInput)
        #expect(task.lastMessage == "Claude is idle")
    }

    @Test func notification_elicitationDialog_setsWaitingForInput() {
        var (task, handler) = makeWorkingTask()
        let payload = HookPayload(session_id: task.sessionId, hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: "elicitation_dialog")

        dispatch(endpoint: "/hook/notification", payload: payload, handler: &handler)

        #expect(task.status == .waitingForInput)
        #expect(task.lastMessage == "Claude is asking a question")
    }

    // MARK: - PermissionRequest

    @Test func permissionRequest_setsWaitingForInput() {
        var (task, handler) = makeWorkingTask()
        let payload = HookPayload(session_id: task.sessionId, hook_event_name: "PermissionRequest",
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: "Bash", tool_input: nil, notification_type: nil)

        dispatch(endpoint: "/hook/permission", payload: payload, handler: &handler)

        #expect(task.status == .waitingForInput)
        #expect(task.pendingPermission == "Bash")
        #expect(task.lastMessage == "Permission needed for Bash")
    }
}
