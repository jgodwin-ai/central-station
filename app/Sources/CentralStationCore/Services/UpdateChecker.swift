import Foundation

public enum UpdateChecker {
    public static let currentVersion = "0.1.0"

    struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }

    public struct UpdateInfo: Sendable {
        public let version: String
        public let url: String
    }

    /// Parse release JSON and return UpdateInfo if newer than current version.
    public static func parseRelease(data: Data) -> UpdateInfo? {
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
            return nil
        }
        let remote = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        if isNewer(remote: remote, local: currentVersion) {
            return UpdateInfo(version: remote, url: release.html_url)
        }
        return nil
    }

    public static func isNewer(remote: String, local: String) -> Bool {
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
