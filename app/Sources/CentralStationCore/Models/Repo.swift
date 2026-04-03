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

    public init(repos: [Repo] = [], nextTaskNumber: Int = 1) {
        self.repos = repos
        self.nextTaskNumber = nextTaskNumber
    }

    public mutating func nextTaskId() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        let id = "\(date)-task-\(nextTaskNumber)"
        nextTaskNumber += 1
        return id
    }
}
