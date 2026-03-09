import Foundation

struct RemoteConfig: Codable, Identifiable, Hashable {
    var id: String  // UUID
    var alias: String  // e.g. "Dev Server"
    var sshHost: String  // e.g. "user@10.0.1.5" or SSH config alias "devbox"
    var defaultDirectory: String?  // last-used or preferred starting directory
}
