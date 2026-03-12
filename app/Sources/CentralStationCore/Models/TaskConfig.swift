import Foundation

public struct TaskConfig: Codable, Identifiable {
    public let id: String
    public let description: String
    public let prompt: String
    public var permissionMode: String?

    enum CodingKeys: String, CodingKey {
        case id, description, prompt
        case permissionMode = "permission_mode"
    }
}

public struct ProjectConfig: Codable {
    public let project: String
    public let tasks: [TaskConfig]
}
