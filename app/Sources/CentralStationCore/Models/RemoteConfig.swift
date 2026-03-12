import Foundation

public struct RemoteConfig: Codable, Identifiable, Hashable {
    public var id: String
    public var alias: String
    public var sshHost: String
    public var defaultDirectory: String?

    public init(id: String, alias: String, sshHost: String, defaultDirectory: String? = nil) {
        self.id = id
        self.alias = alias
        self.sshHost = sshHost
        self.defaultDirectory = defaultDirectory
    }
}
