import Foundation
import AppKit

@MainActor
enum Notifier {
    private static var lastSound: Date = .distantPast
    static var settings = ChimeSettings.load()

    static func requestPermission() {}

    static func notify(taskId: String, description: String) {
        guard settings.enabled else { return }
        let now = Date()
        if now.timeIntervalSince(lastSound) >= settings.cooldownSeconds {
            lastSound = now
            if let sound = NSSound(named: NSSound.Name(settings.soundName)) {
                sound.volume = settings.volume
                sound.play()
            }
        }
    }

    static func previewSound() {
        if let sound = NSSound(named: NSSound.Name(settings.soundName)) {
            sound.volume = settings.volume
            sound.play()
        }
    }
}
