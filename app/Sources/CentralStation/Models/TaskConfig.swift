import Foundation

struct TaskConfig: Codable, Identifiable {
    let id: String
    let description: String
    let prompt: String
    var permissionMode: String?

    enum CodingKeys: String, CodingKey {
        case id, description, prompt
        case permissionMode = "permission_mode"
    }
}

struct ProjectConfig: Codable {
    let project: String
    let tasks: [TaskConfig]
}
