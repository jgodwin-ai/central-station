import Foundation

@Observable
@MainActor
final class RemoteStore {
    var remotes: [RemoteConfig] = []

    private static var persistencePath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/central-station-remotes.json")
    }

    func load() {
        guard let data = FileManager.default.contents(atPath: Self.persistencePath),
              let decoded = try? JSONDecoder().decode([RemoteConfig].self, from: data) else { return }
        remotes = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(remotes) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.persistencePath))
    }

    func add(_ remote: RemoteConfig) {
        remotes.append(remote)
        save()
    }

    func update(_ remote: RemoteConfig) {
        if let idx = remotes.firstIndex(where: { $0.id == remote.id }) {
            remotes[idx] = remote
            save()
        }
    }

    func delete(_ remote: RemoteConfig) {
        remotes.removeAll { $0.id == remote.id }
        save()
    }

    func testConnection(remote: RemoteConfig) async -> Result<String, Error> {
        do {
            let output = try await ShellHelper.run("/usr/bin/ssh", arguments: [
                "-o", "ConnectTimeout=5",
                "-o", "BatchMode=yes",
                remote.sshHost,
                "echo connected && hostname"
            ])
            return .success(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .failure(error)
        }
    }
}
