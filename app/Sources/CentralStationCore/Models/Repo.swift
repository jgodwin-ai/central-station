import Foundation

public struct Repo: Identifiable, Codable, Hashable {
    public let id: String
    public let path: String

    public var name: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    public init(path: String) {
        self.id = UUID().uuidString
        self.path = path
    }
}

public struct RepoPersistence: Codable {
    public var repos: [Repo]
    public var nextTaskNumber: Int
    public var requireTaskName: Bool

    public init(repos: [Repo] = [], nextTaskNumber: Int = 1, requireTaskName: Bool = false) {
        self.repos = repos
        self.nextTaskNumber = nextTaskNumber
        self.requireTaskName = requireTaskName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repos = try container.decode([Repo].self, forKey: .repos)
        nextTaskNumber = try container.decode(Int.self, forKey: .nextTaskNumber)
        requireTaskName = try container.decodeIfPresent(Bool.self, forKey: .requireTaskName) ?? false
    }

    public mutating func nextTaskId(customName: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        let number = nextTaskNumber
        nextTaskNumber += 1
        if let name = customName, !name.isEmpty {
            let slug = Validation.sanitizeTaskId(name)
            return "\(date)-\(slug)"
        }
        return "\(date)-task-\(number)"
    }
}
