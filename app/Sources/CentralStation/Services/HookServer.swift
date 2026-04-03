import Foundation
import Network

struct HookPayload: Decodable {
    let session_id: String?
    let hook_event_name: String?
    let stop_hook_active: Bool?
    let last_assistant_message: String?
    let tool_name: String?
    let tool_input: [String: String]?
    let notification_type: String?
}

@Observable
final class HookServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 19280

    private var listener: NWListener?
    private(set) var port: UInt16 = defaultPort
    var secret: String = ""
    var onStop: ((String, String) -> Void)?
    var onWorking: ((String) -> Void)? // (sessionId) — Claude is actively working
    var onPermissionRequest: ((String, String) -> Void)?
    var onNotification: ((String, String) -> Void)? // (sessionId, notificationType)
    var onSessionEnd: ((String) -> Void)? // (sessionId) — user exited the session

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: Self.defaultPort)!
        )
        let listener = try NWListener(using: params)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = listener.port {
                self?.port = port.rawValue
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            if let remote = connection.currentPath?.remoteEndpoint,
               case let .hostPort(host, _) = remote {
                let hostStr = "\(host)"
                if hostStr != "127.0.0.1" && hostStr != "::1" {
                    connection.cancel()
                    return
                }
            }
            self?.handleConnection(connection)
        }

        listener.start(queue: .global(qos: .userInitiated))

        Thread.sleep(forTimeInterval: 0.1)
        if let assignedPort = listener.port {
            self.port = assignedPort.rawValue
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveAccumulated(connection: connection, buffer: Data())
    }

    private func receiveAccumulated(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            var accumulated = buffer
            if let data { accumulated.append(data) }

            let raw = String(data: accumulated, encoding: .utf8) ?? ""

            if let headerEnd = raw.range(of: "\r\n\r\n") {
                let headers = String(raw[..<headerEnd.lowerBound])
                let body = String(raw[headerEnd.upperBound...])

                var expectedLength = 0
                for line in headers.split(separator: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        expectedLength = Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
                    }
                }

                if body.utf8.count >= expectedLength || isComplete || error != nil {
                    self?.processRequest(connection: connection, raw: raw, body: body)
                    return
                }
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            self?.receiveAccumulated(connection: connection, buffer: accumulated)
        }
    }

    private func processRequest(connection: NWConnection, raw: String, body: String) {
        // Validate authorization if a secret is configured
        if !secret.isEmpty {
            var authValue = ""
            if let headerEnd = raw.range(of: "\r\n\r\n") {
                let headerSection = String(raw[..<headerEnd.lowerBound])
                for line in headerSection.split(separator: "\r\n") {
                    if line.lowercased().hasPrefix("authorization:") {
                        authValue = String(line.dropFirst("authorization:".count)).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
            }
            if !HookSecret.validate(header: authValue, expected: secret) {
                let reject = "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n"
                connection.send(content: reject.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
        }

        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        let firstLine = raw.split(separator: "\r\n").first.map(String.init) ?? ""

        guard let jsonData = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(HookPayload.self, from: jsonData) else {
            return
        }

        // Routing logic is mirrored in HookEndToEndTests.dispatch — update both together
        if firstLine.contains("/hook/stop") {
            if payload.stop_hook_active == true {
                // This stop was triggered by the hook itself — ignore to prevent loops
                return
            }
            if let sessionId = payload.session_id {
                if payload.hook_event_name == "SubagentStop" {
                    // Subagent finished but main agent is still running — keep task as working
                    DispatchQueue.main.async {
                        self.onWorking?(sessionId)
                    }
                } else {
                    let message = payload.last_assistant_message ?? ""
                    DispatchQueue.main.async {
                        self.onStop?(sessionId, message)
                    }
                }
            }
        } else if firstLine.contains("/hook/prompt") {
            if let sessionId = payload.session_id {
                DispatchQueue.main.async {
                    self.onWorking?(sessionId)
                }
            }
        } else if firstLine.contains("/hook/notification") {
            if let sessionId = payload.session_id {
                let notifType = payload.notification_type ?? payload.hook_event_name ?? "unknown"
                DispatchQueue.main.async {
                    self.onNotification?(sessionId, notifType)
                }
            }
        } else if firstLine.contains("/hook/permission") {
            if let sessionId = payload.session_id {
                let toolName = payload.tool_name ?? "unknown"
                DispatchQueue.main.async {
                    self.onPermissionRequest?(sessionId, toolName)
                }
            }
        } else if firstLine.contains("/hook/session-end") {
            if let sessionId = payload.session_id {
                DispatchQueue.main.async {
                    self.onSessionEnd?(sessionId)
                }
            }
        }
    }
}
