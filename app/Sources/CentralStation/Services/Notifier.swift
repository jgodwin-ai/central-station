import Foundation

@MainActor
enum Notifier {
    private static var cooldowns: [String: Date] = [:]
    private static let cooldownInterval: TimeInterval = 30

    static func requestPermission() {
        // osascript notifications don't need permission
    }

    static func notify(taskId: String, description: String) {
        let now = Date()
        if let last = cooldowns[taskId], now.timeIntervalSince(last) < cooldownInterval {
            return
        }
        cooldowns[taskId] = now

        let title = "Central Station: \(taskId)"
            .replacingOccurrences(of: "\"", with: "\\\"")
        let message = "\(description) — needs your input"
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "display notification \"\(message)\" with title \"\(title)\" sound name \"Glass\""

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            process.waitUntilExit()
        }
    }
}
