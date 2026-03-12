import Foundation

public struct ChimeSettings: Codable {
    public var soundName: String = "Glass"
    public var volume: Float = 1.0
    public var enabled: Bool = true
    public var cooldownSeconds: Double = 30

    public static let availableSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Glass", "Hero", "Morse", "Ping", "Pop",
        "Purr", "Sosumi", "Submarine", "Tink"
    ]

    private static var settingsPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/central-station-chime.json")
    }

    public init(soundName: String = "Glass", volume: Float = 1.0, enabled: Bool = true, cooldownSeconds: Double = 30) {
        self.soundName = soundName
        self.volume = volume
        self.enabled = enabled
        self.cooldownSeconds = cooldownSeconds
    }

    public static func load() -> ChimeSettings {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let settings = try? JSONDecoder().decode(ChimeSettings.self, from: data) else {
            return ChimeSettings()
        }
        return settings
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.settingsPath))
    }
}
