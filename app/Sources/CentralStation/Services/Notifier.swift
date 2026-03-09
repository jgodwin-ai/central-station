import Foundation
import AppKit

@MainActor
enum Notifier {
    private static var lastSound: Date = .distantPast
    private static let soundCooldown: TimeInterval = 30

    static func requestPermission() {}

    static func notify(taskId: String, description: String) {
        let now = Date()
        if now.timeIntervalSince(lastSound) >= soundCooldown {
            lastSound = now
            NSSound(named: "Glass")?.play()
        }
    }
}
