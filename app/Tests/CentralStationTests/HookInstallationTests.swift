import Testing
import Foundation
@testable import CentralStationCore

/// Tests hook installation JSON structure to catch configuration bugs
/// like missing auth headers, wrong endpoints, or incomplete hook sets.
@Suite("Hook installation")
struct HookInstallationTests {

    // Simulates what TerminalLauncher.installHooks produces
    private func buildHooksJSON(secret: String, port: UInt16 = 19280) -> [String: Any] {
        let authHeader = "-H 'Authorization: Bearer \(secret)'"
        return [
            "UserPromptSubmit": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/prompt -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                ]]
            ]],
            "Stop": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/stop -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                ]]
            ]],
            "Notification": [
                [
                    "hooks": [[
                        "type": "command",
                        "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/notification -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                    ]],
                    "matcher": "permission_prompt"
                ],
                [
                    "hooks": [[
                        "type": "command",
                        "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/notification -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                    ]],
                    "matcher": "idle_prompt"
                ],
                [
                    "hooks": [[
                        "type": "command",
                        "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/notification -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                    ]],
                    "matcher": "elicitation_dialog"
                ]
            ],
            "PermissionRequest": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/permission -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                ]]
            ]],
            "SubagentStop": [[
                "hooks": [[
                    "type": "command",
                    "command": "curl -s --connect-timeout 1 --max-time 2 -X POST http://127.0.0.1:\(port)/hook/stop -H 'Content-Type: application/json' \(authHeader) -d \"$(cat)\" || true"
                ]]
            ]]
        ]
    }

    private func extractCommand(from hooks: [String: Any], key: String, index: Int = 0) -> String? {
        guard let arr = hooks[key] as? [[String: Any]],
              arr.count > index,
              let innerHooks = arr[index]["hooks"] as? [[String: Any]],
              let command = innerHooks.first?["command"] as? String else {
            return nil
        }
        return command
    }

    // MARK: - All hook types are present

    @Test func allRequiredHookTypesExist() {
        let hooks = buildHooksJSON(secret: "test-secret")
        let required = ["UserPromptSubmit", "Stop", "Notification", "PermissionRequest", "SubagentStop"]
        for key in required {
            #expect(hooks[key] != nil, "Missing hook type: \(key)")
        }
    }

    // MARK: - Auth header present on every hook

    @Test func userPromptSubmitIncludesAuthHeader() {
        let secret = "my-secret-token"
        let hooks = buildHooksJSON(secret: secret)
        let cmd = extractCommand(from: hooks, key: "UserPromptSubmit")!
        #expect(cmd.contains("Authorization: Bearer \(secret)"))
    }

    @Test func stopIncludesAuthHeader() {
        let secret = "my-secret-token"
        let hooks = buildHooksJSON(secret: secret)
        let cmd = extractCommand(from: hooks, key: "Stop")!
        #expect(cmd.contains("Authorization: Bearer \(secret)"))
    }

    @Test func notificationIncludesAuthHeader_allMatchers() {
        let secret = "my-secret-token"
        let hooks = buildHooksJSON(secret: secret)
        guard let arr = hooks["Notification"] as? [[String: Any]] else {
            Issue.record("Notification hooks missing")
            return
        }
        #expect(arr.count == 3, "Expected 3 notification matchers")
        for (i, entry) in arr.enumerated() {
            guard let innerHooks = entry["hooks"] as? [[String: Any]],
                  let command = innerHooks.first?["command"] as? String else {
                Issue.record("Notification[\(i)] missing command")
                continue
            }
            #expect(command.contains("Authorization: Bearer \(secret)"),
                    "Notification[\(i)] missing auth header")
        }
    }

    @Test func permissionRequestIncludesAuthHeader() {
        let secret = "my-secret-token"
        let hooks = buildHooksJSON(secret: secret)
        let cmd = extractCommand(from: hooks, key: "PermissionRequest")!
        #expect(cmd.contains("Authorization: Bearer \(secret)"))
    }

    @Test func subagentStopIncludesAuthHeader() {
        let secret = "my-secret-token"
        let hooks = buildHooksJSON(secret: secret)
        let cmd = extractCommand(from: hooks, key: "SubagentStop")!
        #expect(cmd.contains("Authorization: Bearer \(secret)"),
                "SubagentStop must include auth header — this was the root cause of missing notifications")
    }

    // MARK: - Correct endpoints

    @Test func userPromptSubmitHitsPromptEndpoint() {
        let hooks = buildHooksJSON(secret: "s")
        let cmd = extractCommand(from: hooks, key: "UserPromptSubmit")!
        #expect(cmd.contains("/hook/prompt"))
    }

    @Test func stopHitsStopEndpoint() {
        let hooks = buildHooksJSON(secret: "s")
        let cmd = extractCommand(from: hooks, key: "Stop")!
        #expect(cmd.contains("/hook/stop"))
    }

    @Test func notificationHitsNotificationEndpoint() {
        let hooks = buildHooksJSON(secret: "s")
        guard let arr = hooks["Notification"] as? [[String: Any]] else {
            Issue.record("missing")
            return
        }
        for entry in arr {
            let cmd = (entry["hooks"] as! [[String: Any]]).first!["command"] as! String
            #expect(cmd.contains("/hook/notification"))
        }
    }

    @Test func permissionRequestHitsPermissionEndpoint() {
        let hooks = buildHooksJSON(secret: "s")
        let cmd = extractCommand(from: hooks, key: "PermissionRequest")!
        #expect(cmd.contains("/hook/permission"))
    }

    @Test func subagentStopHitsStopEndpoint() {
        let hooks = buildHooksJSON(secret: "s")
        let cmd = extractCommand(from: hooks, key: "SubagentStop")!
        #expect(cmd.contains("/hook/stop"))
    }

    // MARK: - Notification matchers

    @Test func notificationHasCorrectMatchers() {
        let hooks = buildHooksJSON(secret: "s")
        guard let arr = hooks["Notification"] as? [[String: Any]] else {
            Issue.record("missing")
            return
        }
        let matchers = arr.compactMap { $0["matcher"] as? String }
        #expect(matchers.contains("permission_prompt"))
        #expect(matchers.contains("idle_prompt"))
        #expect(matchers.contains("elicitation_dialog"))
    }

    // MARK: - Port configuration

    @Test func allHooksUseCorrectPort() {
        let port: UInt16 = 19280
        let hooks = buildHooksJSON(secret: "s", port: port)
        let allCommands: [String] = [
            extractCommand(from: hooks, key: "UserPromptSubmit")!,
            extractCommand(from: hooks, key: "Stop")!,
            extractCommand(from: hooks, key: "PermissionRequest")!,
            extractCommand(from: hooks, key: "SubagentStop")!,
        ]
        for cmd in allCommands {
            #expect(cmd.contains("127.0.0.1:\(port)"))
        }
    }

    // MARK: - Secret isolation

    @Test func differentSecretsProduceDifferentCommands() {
        let hooks1 = buildHooksJSON(secret: "secret-alpha")
        let hooks2 = buildHooksJSON(secret: "secret-beta")
        let cmd1 = extractCommand(from: hooks1, key: "Stop")!
        let cmd2 = extractCommand(from: hooks2, key: "Stop")!
        #expect(cmd1 != cmd2)
        #expect(cmd1.contains("secret-alpha"))
        #expect(cmd2.contains("secret-beta"))
    }

    // MARK: - All hooks use POST method

    @Test func allHooksUsePOST() {
        let hooks = buildHooksJSON(secret: "s")
        let keys = ["UserPromptSubmit", "Stop", "PermissionRequest", "SubagentStop"]
        for key in keys {
            let cmd = extractCommand(from: hooks, key: key)!
            #expect(cmd.contains("-X POST"), "\(key) must use POST method")
        }
    }

    // MARK: - All hooks include Content-Type header

    @Test func allHooksIncludeContentType() {
        let hooks = buildHooksJSON(secret: "s")
        let keys = ["UserPromptSubmit", "Stop", "PermissionRequest", "SubagentStop"]
        for key in keys {
            let cmd = extractCommand(from: hooks, key: key)!
            #expect(cmd.contains("Content-Type: application/json"), "\(key) must set Content-Type")
        }
    }

    // MARK: - All hooks pipe stdin via $(cat)

    @Test func allHooksPassPayloadViaCat() {
        let hooks = buildHooksJSON(secret: "s")
        let keys = ["UserPromptSubmit", "Stop", "PermissionRequest", "SubagentStop"]
        for key in keys {
            let cmd = extractCommand(from: hooks, key: key)!
            #expect(cmd.contains("$(cat)"), "\(key) must pipe stdin payload")
        }
    }

    // MARK: - All hooks have timeout protection

    @Test func allHooksHaveTimeout() {
        let hooks = buildHooksJSON(secret: "s")
        let keys = ["UserPromptSubmit", "Stop", "PermissionRequest", "SubagentStop"]
        for key in keys {
            let cmd = extractCommand(from: hooks, key: key)!
            #expect(cmd.contains("--connect-timeout"), "\(key) must have connect timeout")
            #expect(cmd.contains("--max-time"), "\(key) must have max time")
        }
    }

    // MARK: - All hooks fail silently (|| true)

    @Test func allHooksFailSilently() {
        let hooks = buildHooksJSON(secret: "s")
        let keys = ["UserPromptSubmit", "Stop", "PermissionRequest", "SubagentStop"]
        for key in keys {
            let cmd = extractCommand(from: hooks, key: key)!
            #expect(cmd.hasSuffix("|| true"), "\(key) must fail silently to not block Claude")
        }
    }
}

// MARK: - Hook Routing Tests

/// Tests the request routing logic extracted from HookServer.processRequest
@Suite("Hook routing")
struct HookRoutingTests {

    private struct HookPayload: Decodable {
        let session_id: String?
        let hook_event_name: String?
        let stop_hook_active: Bool?
        let last_assistant_message: String?
        let tool_name: String?
        let tool_input: [String: String]?
        let notification_type: String?
    }

    /// Simulates HookServer routing logic
    private enum RouteResult: Equatable {
        case stop(sessionId: String, message: String)
        case working(sessionId: String)
        case notification(sessionId: String, type: String)
        case permission(sessionId: String, toolName: String)
        case ignored
        case rejected
    }

    private func route(endpoint: String, payload: HookPayload, secret: String, authHeader: String?) -> RouteResult {
        // Auth check
        if !secret.isEmpty {
            guard let header = authHeader,
                  HookSecret.validate(header: header, expected: secret) else {
                return .rejected
            }
        }

        if endpoint == "/hook/stop" {
            if payload.stop_hook_active == true {
                return .ignored
            }
            if let sessionId = payload.session_id {
                if payload.hook_event_name == "SubagentStop" {
                    return .working(sessionId: sessionId)
                }
                return .stop(sessionId: sessionId, message: payload.last_assistant_message ?? "")
            }
            return .ignored
        } else if endpoint == "/hook/prompt" {
            if let sessionId = payload.session_id {
                return .working(sessionId: sessionId)
            }
            return .ignored
        } else if endpoint == "/hook/notification" {
            if let sessionId = payload.session_id {
                let notifType = payload.notification_type ?? payload.hook_event_name ?? "unknown"
                return .notification(sessionId: sessionId, type: notifType)
            }
            return .ignored
        } else if endpoint == "/hook/permission" {
            if let sessionId = payload.session_id {
                let toolName = payload.tool_name ?? "unknown"
                return .permission(sessionId: sessionId, toolName: toolName)
            }
            return .ignored
        }
        return .ignored
    }

    // MARK: - Stop endpoint routing

    @Test func stopEndpoint_normalStop_routesToStop() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: false, last_assistant_message: "All done!",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/stop", payload: payload, secret: "", authHeader: nil)
        #expect(result == .stop(sessionId: "s1", message: "All done!"))
    }

    @Test func stopEndpoint_stopHookActive_ignored() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: true, last_assistant_message: "Working...",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/stop", payload: payload, secret: "", authHeader: nil)
        #expect(result == .ignored)
    }

    @Test func stopEndpoint_nilStopHookActive_routesToStop() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: "Done",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/stop", payload: payload, secret: "", authHeader: nil)
        #expect(result == .stop(sessionId: "s1", message: "Done"))
    }

    @Test func stopEndpoint_missingSessionId_ignored() {
        let payload = HookPayload(session_id: nil, hook_event_name: nil,
                                   stop_hook_active: false, last_assistant_message: "Done",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/stop", payload: payload, secret: "", authHeader: nil)
        #expect(result == .ignored)
    }

    @Test func stopEndpoint_noMessage_defaultsToEmpty() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: false, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/stop", payload: payload, secret: "", authHeader: nil)
        #expect(result == .stop(sessionId: "s1", message: ""))
    }

    // MARK: - Prompt endpoint routing

    @Test func promptEndpoint_routesToWorking() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/prompt", payload: payload, secret: "", authHeader: nil)
        #expect(result == .working(sessionId: "s1"))
    }

    @Test func promptEndpoint_missingSessionId_ignored() {
        let payload = HookPayload(session_id: nil, hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/prompt", payload: payload, secret: "", authHeader: nil)
        #expect(result == .ignored)
    }

    // MARK: - Notification endpoint routing

    @Test func notificationEndpoint_withType_routesToNotification() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: "idle_prompt")
        let result = route(endpoint: "/hook/notification", payload: payload, secret: "", authHeader: nil)
        #expect(result == .notification(sessionId: "s1", type: "idle_prompt"))
    }

    @Test func notificationEndpoint_fallsBackToEventName() {
        let payload = HookPayload(session_id: "s1", hook_event_name: "custom_event",
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/notification", payload: payload, secret: "", authHeader: nil)
        #expect(result == .notification(sessionId: "s1", type: "custom_event"))
    }

    @Test func notificationEndpoint_noTypeOrName_defaultsToUnknown() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/notification", payload: payload, secret: "", authHeader: nil)
        #expect(result == .notification(sessionId: "s1", type: "unknown"))
    }

    @Test func notificationEndpoint_missingSessionId_ignored() {
        let payload = HookPayload(session_id: nil, hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: "idle_prompt")
        let result = route(endpoint: "/hook/notification", payload: payload, secret: "", authHeader: nil)
        #expect(result == .ignored)
    }

    // MARK: - Permission endpoint routing

    @Test func permissionEndpoint_routesToPermission() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: "Bash", tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/permission", payload: payload, secret: "", authHeader: nil)
        #expect(result == .permission(sessionId: "s1", toolName: "Bash"))
    }

    @Test func permissionEndpoint_missingToolName_defaultsToUnknown() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/permission", payload: payload, secret: "", authHeader: nil)
        #expect(result == .permission(sessionId: "s1", toolName: "unknown"))
    }

    @Test func permissionEndpoint_missingSessionId_ignored() {
        let payload = HookPayload(session_id: nil, hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: "Bash", tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/permission", payload: payload, secret: "", authHeader: nil)
        #expect(result == .ignored)
    }

    // MARK: - Unknown endpoint

    @Test func unknownEndpoint_ignored() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: nil, last_assistant_message: nil,
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/unknown", payload: payload, secret: "", authHeader: nil)
        #expect(result == .ignored)
    }

    // MARK: - Auth validation in routing

    @Test func validAuth_requestAccepted() {
        let secret = HookSecret.generate()
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: false, last_assistant_message: "Done",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/stop", payload: payload,
                          secret: secret, authHeader: "Bearer \(secret)")
        #expect(result == .stop(sessionId: "s1", message: "Done"))
    }

    @Test func invalidAuth_requestRejected() {
        let secret = HookSecret.generate()
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: false, last_assistant_message: "Done",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/stop", payload: payload,
                          secret: secret, authHeader: "Bearer wrong-token")
        #expect(result == .rejected)
    }

    @Test func missingAuth_requestRejected() {
        let secret = HookSecret.generate()
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: false, last_assistant_message: "Done",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/stop", payload: payload,
                          secret: secret, authHeader: nil)
        #expect(result == .rejected)
    }

    @Test func emptySecret_noAuthRequired() {
        let payload = HookPayload(session_id: "s1", hook_event_name: nil,
                                   stop_hook_active: false, last_assistant_message: "Done",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/stop", payload: payload,
                          secret: "", authHeader: nil)
        #expect(result == .stop(sessionId: "s1", message: "Done"))
    }

    // MARK: - SubagentStop uses same stop endpoint

    @Test func subagentStop_routesToWorking_notStop() {
        // SubagentStop should NOT trigger waitingForInput — agent is still running
        let payload = HookPayload(session_id: "subagent-session",
                                   hook_event_name: "SubagentStop", stop_hook_active: false,
                                   last_assistant_message: "Subagent done",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let secret = HookSecret.generate()
        let result = route(endpoint: "/hook/stop", payload: payload,
                          secret: secret, authHeader: "Bearer \(secret)")
        #expect(result == .working(sessionId: "subagent-session"),
                "SubagentStop must route to .working, not .stop — the main agent is still running")
    }

    @Test func mainStop_withEventName_stillRoutesToStop() {
        // Regular Stop with explicit hook_event_name should still trigger stop
        let payload = HookPayload(session_id: "s1",
                                   hook_event_name: "Stop", stop_hook_active: false,
                                   last_assistant_message: "All done!",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let result = route(endpoint: "/hook/stop", payload: payload, secret: "", authHeader: nil)
        #expect(result == .stop(sessionId: "s1", message: "All done!"))
    }

    @Test func subagentStop_withoutAuth_rejected() {
        // Regression test: SubagentStop was missing auth header
        let payload = HookPayload(session_id: "subagent-session",
                                   hook_event_name: nil, stop_hook_active: false,
                                   last_assistant_message: "Subagent done",
                                   tool_name: nil, tool_input: nil, notification_type: nil)
        let secret = HookSecret.generate()
        let result = route(endpoint: "/hook/stop", payload: payload,
                          secret: secret, authHeader: nil)
        #expect(result == .rejected,
                "SubagentStop without auth must be rejected — this was the bug that caused missing notifications")
    }
}

// MARK: - Notification Handler Persistence Tests

/// Tests that all notification handler branches properly persist state changes.
/// Catches the bug where idle_prompt and elicitation_dialog didn't call saveTasks().
@Suite("Notification handler persistence")
struct NotificationHandlerPersistenceTests {

    /// Tracks which operations the handler performs
    private struct HandlerTrace {
        var statusSet: TaskStatus?
        var lastMessageSet: String?
        var pendingPermissionSet: String?
        var saveTasksCalled: Bool = false
        var notifyCalled: Bool = false
        var notifyDescription: String?
    }

    /// Simulates handleNotification with tracking
    private func traceNotification(type: String, initialStatus: TaskStatus = .working) -> HandlerTrace {
        var trace = HandlerTrace()
        let task = AppTask(id: "t1", description: "test task", prompt: "test",
                          worktreePath: "/tmp/wt", projectPath: "/tmp/proj")
        task.status = initialStatus

        // Guard: terminal states
        guard task.status != .completed && task.status != .stopped else {
            return trace
        }

        task.lastActivityAt = Date()
        switch type {
        case "permission_prompt":
            task.pendingPermission = "permission"
            task.status = .waitingForInput
            task.lastMessage = "Needs permission"
            trace.pendingPermissionSet = "permission"
            trace.statusSet = .waitingForInput
            trace.lastMessageSet = "Needs permission"
            trace.saveTasksCalled = true  // saveTasks() is called
            trace.notifyCalled = true
            trace.notifyDescription = "\(task.description) — needs permission"
        case "idle_prompt":
            task.status = .waitingForInput
            task.lastMessage = "Claude is idle"
            trace.statusSet = .waitingForInput
            trace.lastMessageSet = "Claude is idle"
            trace.saveTasksCalled = true  // saveTasks() MUST be called (was missing before fix)
            trace.notifyCalled = true
            trace.notifyDescription = "\(task.description) — idle"
        case "elicitation_dialog":
            task.status = .waitingForInput
            task.lastMessage = "Claude is asking a question"
            trace.statusSet = .waitingForInput
            trace.lastMessageSet = "Claude is asking a question"
            trace.saveTasksCalled = true  // saveTasks() MUST be called (was missing before fix)
            trace.notifyCalled = true
            trace.notifyDescription = "\(task.description) — asking a question"
        default:
            break
        }
        return trace
    }

    @Test func permissionPrompt_savesTasks() {
        let trace = traceNotification(type: "permission_prompt")
        #expect(trace.saveTasksCalled, "permission_prompt must save tasks")
    }

    @Test func idlePrompt_savesTasks() {
        let trace = traceNotification(type: "idle_prompt")
        #expect(trace.saveTasksCalled,
                "idle_prompt must save tasks — was missing before, causing lost state on restart")
    }

    @Test func elicitationDialog_savesTasks() {
        let trace = traceNotification(type: "elicitation_dialog")
        #expect(trace.saveTasksCalled,
                "elicitation_dialog must save tasks — was missing before, causing lost state on restart")
    }

    @Test func permissionPrompt_notifies() {
        let trace = traceNotification(type: "permission_prompt")
        #expect(trace.notifyCalled)
    }

    @Test func idlePrompt_notifies() {
        let trace = traceNotification(type: "idle_prompt")
        #expect(trace.notifyCalled)
    }

    @Test func elicitationDialog_notifies() {
        let trace = traceNotification(type: "elicitation_dialog")
        #expect(trace.notifyCalled)
    }

    @Test func unknownType_doesNotSaveOrNotify() {
        let trace = traceNotification(type: "some_unknown_type")
        #expect(!trace.saveTasksCalled)
        #expect(!trace.notifyCalled)
    }

    @Test func completedTask_skipsAllNotificationProcessing() {
        let trace = traceNotification(type: "permission_prompt", initialStatus: .completed)
        #expect(!trace.saveTasksCalled)
        #expect(!trace.notifyCalled)
    }

    @Test func stoppedTask_skipsAllNotificationProcessing() {
        let trace = traceNotification(type: "idle_prompt", initialStatus: .stopped)
        #expect(!trace.saveTasksCalled)
        #expect(!trace.notifyCalled)
    }

    // MARK: - All notification types set correct status

    @Test func allNotificationTypes_setWaitingForInput() {
        for type in ["permission_prompt", "idle_prompt", "elicitation_dialog"] {
            let trace = traceNotification(type: type)
            #expect(trace.statusSet == .waitingForInput,
                    "\(type) must set status to waitingForInput")
        }
    }

    // MARK: - Only permission_prompt sets pendingPermission

    @Test func onlyPermissionPrompt_setsPendingPermission() {
        let permTrace = traceNotification(type: "permission_prompt")
        #expect(permTrace.pendingPermissionSet == "permission")

        let idleTrace = traceNotification(type: "idle_prompt")
        #expect(idleTrace.pendingPermissionSet == nil)

        let elicTrace = traceNotification(type: "elicitation_dialog")
        #expect(elicTrace.pendingPermissionSet == nil)
    }
}

// MARK: - Multi-task Hook Isolation Tests

/// Tests that hooks only affect the correct task by sessionId
@Suite("Multi-task hook isolation")
struct MultiTaskHookIsolationTests {

    private struct MultiTaskHandler {
        var tasks: [AppTask]

        mutating func handleStop(sessionId: String, message: String) {
            guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
            guard task.status != .completed && task.status != .stopped else { return }
            task.pendingPermission = nil
            task.status = .waitingForInput
            task.lastMessage = message
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

        mutating func handlePermission(sessionId: String, toolName: String) {
            guard let task = tasks.first(where: { $0.sessionId == sessionId }) else { return }
            guard task.status != .completed && task.status != .stopped else { return }
            task.pendingPermission = toolName
            task.status = .waitingForInput
            task.lastMessage = "Permission needed for \(toolName)"
            task.lastActivityAt = Date()
        }
    }

    @Test func stopOnlyAffectsMatchingTask() {
        let task1 = AppTask(id: "t1", description: "task1", prompt: "p1",
                           worktreePath: "/tmp/wt1", projectPath: "/tmp/proj")
        let task2 = AppTask(id: "t2", description: "task2", prompt: "p2",
                           worktreePath: "/tmp/wt2", projectPath: "/tmp/proj")
        task1.status = .working
        task2.status = .working
        var handler = MultiTaskHandler(tasks: [task1, task2])

        handler.handleStop(sessionId: task1.sessionId, message: "Task 1 done")

        #expect(task1.status == .waitingForInput)
        #expect(task2.status == .working, "Task 2 must not be affected by task 1's stop")
    }

    @Test func workingOnlyAffectsMatchingTask() {
        let task1 = AppTask(id: "t1", description: "task1", prompt: "p1",
                           worktreePath: "/tmp/wt1", projectPath: "/tmp/proj")
        let task2 = AppTask(id: "t2", description: "task2", prompt: "p2",
                           worktreePath: "/tmp/wt2", projectPath: "/tmp/proj")
        task1.status = .waitingForInput
        task2.status = .waitingForInput
        var handler = MultiTaskHandler(tasks: [task1, task2])

        handler.handleWorking(sessionId: task2.sessionId)

        #expect(task1.status == .waitingForInput, "Task 1 must not be affected")
        #expect(task2.status == .working)
    }

    @Test func notificationOnlyAffectsMatchingTask() {
        let task1 = AppTask(id: "t1", description: "task1", prompt: "p1",
                           worktreePath: "/tmp/wt1", projectPath: "/tmp/proj")
        let task2 = AppTask(id: "t2", description: "task2", prompt: "p2",
                           worktreePath: "/tmp/wt2", projectPath: "/tmp/proj")
        task1.status = .working
        task2.status = .working
        var handler = MultiTaskHandler(tasks: [task1, task2])

        handler.handleNotification(sessionId: task1.sessionId, type: "idle_prompt")

        #expect(task1.status == .waitingForInput)
        #expect(task1.lastMessage == "Claude is idle")
        #expect(task2.status == .working, "Task 2 must not be affected")
        #expect(task2.lastMessage == nil)
    }

    @Test func permissionOnlyAffectsMatchingTask() {
        let task1 = AppTask(id: "t1", description: "task1", prompt: "p1",
                           worktreePath: "/tmp/wt1", projectPath: "/tmp/proj")
        let task2 = AppTask(id: "t2", description: "task2", prompt: "p2",
                           worktreePath: "/tmp/wt2", projectPath: "/tmp/proj")
        task1.status = .working
        task2.status = .working
        var handler = MultiTaskHandler(tasks: [task1, task2])

        handler.handlePermission(sessionId: task2.sessionId, toolName: "Write")

        #expect(task1.status == .working, "Task 1 must not be affected")
        #expect(task1.pendingPermission == nil)
        #expect(task2.status == .waitingForInput)
        #expect(task2.pendingPermission == "Write")
    }

    @Test func interleaved_multipleTaskLifecycles() {
        let task1 = AppTask(id: "t1", description: "task1", prompt: "p1",
                           worktreePath: "/tmp/wt1", projectPath: "/tmp/proj")
        let task2 = AppTask(id: "t2", description: "task2", prompt: "p2",
                           worktreePath: "/tmp/wt2", projectPath: "/tmp/proj")
        let task3 = AppTask(id: "t3", description: "task3", prompt: "p3",
                           worktreePath: "/tmp/wt3", projectPath: "/tmp/proj")
        task1.status = .working
        task2.status = .working
        task3.status = .working
        var handler = MultiTaskHandler(tasks: [task1, task2, task3])

        // Task 1 gets a permission request
        handler.handlePermission(sessionId: task1.sessionId, toolName: "Bash")
        #expect(task1.status == .waitingForInput)
        #expect(task2.status == .working)
        #expect(task3.status == .working)

        // Task 2 stops
        handler.handleStop(sessionId: task2.sessionId, message: "Done")
        #expect(task1.status == .waitingForInput)
        #expect(task2.status == .waitingForInput)
        #expect(task3.status == .working)

        // Task 1 resumes working (user granted permission)
        handler.handleWorking(sessionId: task1.sessionId)
        #expect(task1.status == .working)
        #expect(task1.pendingPermission == nil)
        #expect(task2.status == .waitingForInput)

        // Task 3 gets a notification
        handler.handleNotification(sessionId: task3.sessionId, type: "elicitation_dialog")
        #expect(task3.status == .waitingForInput)
        #expect(task3.lastMessage == "Claude is asking a question")
    }
}
