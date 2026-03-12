import Foundation

enum UpdateChecker {
    static let currentVersion = "0.1.0"
    private static let releasesURL = "https://api.github.com/repos/jgodwin-ai/claude-central-station/releases/latest"

    struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    struct UpdateInfo: Sendable {
        let version: String
        let url: String
    }

    static func check() async -> UpdateInfo? {
        guard let url = URL(string: releasesURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data) else {
            return nil
        }

        let remote = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        if isNewer(remote: remote, local: currentVersion) {
            return UpdateInfo(version: remote, url: release.html_url)
        }
        return nil
    }

    static func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
