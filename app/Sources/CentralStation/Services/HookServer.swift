import Foundation
import Network

struct HookPayload: Decodable {
    let session_id: String?
    let hook_event_name: String?
    let stop_hook_active: Bool?
    let last_assistant_message: String?
    let tool_name: String?
    let tool_input: [String: String]?
}

@Observable
final class HookServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 19280

    private var listener: NWListener?
    private(set) var port: UInt16 = defaultPort
    var onStop: ((String, String) -> Void)?
    var onPermissionRequest: ((String, String) -> Void)? // (sessionId, toolName)

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
            // Reject connections not from localhost
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

        // Wait briefly for port assignment
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

            // Check if we have the full HTTP request (headers + body)
            if let headerEnd = raw.range(of: "\r\n\r\n") {
                let headers = String(raw[..<headerEnd.lowerBound])
                let body = String(raw[headerEnd.upperBound...])

                // Parse Content-Length
                var expectedLength = 0
                for line in headers.split(separator: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        expectedLength = Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
                    }
                }

                if body.utf8.count >= expectedLength || isComplete || error != nil {
                    // We have the full request — process it
                    self?.processRequest(connection: connection, raw: raw, body: body)
                    return
                }
            }

            if isComplete || error != nil {
                // Connection closed before we got a full request
                connection.cancel()
                return
            }

            // Keep reading
            self?.receiveAccumulated(connection: connection, buffer: accumulated)
        }
    }

    private func processRequest(connection: NWConnection, raw: String, body: String) {
        // Send HTTP 200 response
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        let firstLine = raw.split(separator: "\r\n").first.map(String.init) ?? ""
        NSLog("[HookServer] request: \(firstLine)")
        NSLog("[HookServer] body: \(body.prefix(500))")

        guard let jsonData = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(HookPayload.self, from: jsonData) else {
            NSLog("[HookServer] failed to decode JSON")
            return
        }

        NSLog("[HookServer] session_id=\(payload.session_id ?? "nil") tool=\(payload.tool_name ?? "nil")")

        if firstLine.contains("/hook/stop") {
            if payload.stop_hook_active == true { return }
            if let sessionId = payload.session_id {
                let message = payload.last_assistant_message ?? ""
                DispatchQueue.main.async {
                    self.onStop?(sessionId, message)
                }
            }
        } else if firstLine.contains("/hook/permission") {
            if let sessionId = payload.session_id {
                let toolName = payload.tool_name ?? "unknown"
                NSLog("[HookServer] permission request: session=\(sessionId) tool=\(toolName)")
                DispatchQueue.main.async {
                    self.onPermissionRequest?(sessionId, toolName)
                }
            }
        }
    }
}
