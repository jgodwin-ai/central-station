import Testing
import Foundation
@testable import CentralStationCore

@Suite("ChimeSettings", .serialized)
struct ChimeSettingsTests {

    // MARK: - Init

    @Test func defaultInitHasExpectedValues() {
        let settings = ChimeSettings()
        #expect(settings.soundName == "Glass")
        #expect(settings.volume == 1.0)
        #expect(settings.enabled == true)
        #expect(settings.cooldownSeconds == 30)
    }

    @Test func customInitSetsAllFields() {
        let settings = ChimeSettings(
            soundName: "Ping",
            volume: 0.5,
            enabled: false,
            cooldownSeconds: 10
        )
        #expect(settings.soundName == "Ping")
        #expect(settings.volume == 0.5)
        #expect(settings.enabled == false)
        #expect(settings.cooldownSeconds == 10)
    }

    // MARK: - Codable

    @Test func codableRoundTrip() throws {
        let original = ChimeSettings(
            soundName: "Funk",
            volume: 0.75,
            enabled: false,
            cooldownSeconds: 60
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChimeSettings.self, from: data)

        #expect(decoded.soundName == original.soundName)
        #expect(decoded.volume == original.volume)
        #expect(decoded.enabled == original.enabled)
        #expect(decoded.cooldownSeconds == original.cooldownSeconds)
    }

    @Test func jsonDecodeFromString() throws {
        let json = """
        {
            "soundName": "Submarine",
            "volume": 0.3,
            "enabled": false,
            "cooldownSeconds": 5
        }
        """
        let data = Data(json.utf8)
        let settings = try JSONDecoder().decode(ChimeSettings.self, from: data)

        #expect(settings.soundName == "Submarine")
        #expect(settings.volume == 0.3)
        #expect(settings.enabled == false)
        #expect(settings.cooldownSeconds == 5)
    }

    // MARK: - Available Sounds

    @Test func availableSoundsContainsExpectedEntries() {
        let sounds = ChimeSettings.availableSounds
        #expect(sounds.count == 14)
        #expect(sounds.contains("Glass"))
        #expect(sounds.contains("Basso"))
        #expect(sounds.contains("Tink"))
        #expect(sounds.contains("Sosumi"))
        #expect(sounds.contains("Submarine"))
    }

    // MARK: - Save and Load

    @Test func saveAndLoadRoundTrip() {
        let settingsPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/central-station-chime.json")

        // Back up existing file if present
        let backupPath = settingsPath + ".backup-\(UUID().uuidString)"
        let hadExisting = FileManager.default.fileExists(atPath: settingsPath)
        if hadExisting {
            try? FileManager.default.moveItem(atPath: settingsPath, toPath: backupPath)
        }

        defer {
            try? FileManager.default.removeItem(atPath: settingsPath)
            if hadExisting {
                try? FileManager.default.moveItem(atPath: backupPath, toPath: settingsPath)
            }
        }

        let custom = ChimeSettings(
            soundName: "Pop",
            volume: 0.42,
            enabled: false,
            cooldownSeconds: 99
        )
        custom.save()

        let loaded = ChimeSettings.load()
        #expect(loaded.soundName == "Pop")
        #expect(loaded.volume == 0.42)
        #expect(loaded.enabled == false)
        #expect(loaded.cooldownSeconds == 99)
    }

    @Test func loadReturnsDefaultsWhenFileDoesNotExist() {
        let settingsPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/central-station-chime.json")

        // Back up existing file if present
        let backupPath = settingsPath + ".backup-\(UUID().uuidString)"
        let hadExisting = FileManager.default.fileExists(atPath: settingsPath)
        if hadExisting {
            try? FileManager.default.moveItem(atPath: settingsPath, toPath: backupPath)
        }

        defer {
            try? FileManager.default.removeItem(atPath: settingsPath)
            if hadExisting {
                try? FileManager.default.moveItem(atPath: backupPath, toPath: settingsPath)
            }
        }

        let loaded = ChimeSettings.load()
        #expect(loaded.soundName == "Glass")
        #expect(loaded.volume == 1.0)
        #expect(loaded.enabled == true)
        #expect(loaded.cooldownSeconds == 30)
    }
}
