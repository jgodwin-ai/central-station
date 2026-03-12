import Foundation

struct ChimeSettings: Codable {
    var soundName: String = "Glass"
    var volume: Float = 1.0
    var enabled: Bool = true
    var cooldownSeconds: Double = 30

    static let availableSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Glass", "Hero", "Morse", "Ping", "Pop",
        "Purr", "Sosumi", "Submarine", "Tink"
    ]

    private static var settingsPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/central-station-chime.json")
    }

    static func load() -> ChimeSettings {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let settings = try? JSONDecoder().decode(ChimeSettings.self, from: data) else {
            return ChimeSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.settingsPath))
    }
}
