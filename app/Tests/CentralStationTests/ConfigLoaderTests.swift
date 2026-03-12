import Testing
import Foundation
import Yams

private struct TaskConfig: Codable {
    let id: String
    let description: String
    let prompt: String
    var permissionMode: String?

    enum CodingKeys: String, CodingKey {
        case id, description, prompt
        case permissionMode = "permission_mode"
    }
}

private struct ProjectConfig: Codable {
    let project: String
    let tasks: [TaskConfig]
}

@Suite("Config loading")
struct ConfigLoaderTests {
    @Test func parseYaml() throws {
        let yaml = """
        project: /tmp/test-repo
        tasks:
          - id: task-1
            description: "First task"
            prompt: "Do something"
          - id: task-2
            description: "Second task"
            prompt: "Do another thing"
            permission_mode: auto
        """
        let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml)
        #expect(config.project == "/tmp/test-repo")
        #expect(config.tasks.count == 2)
        #expect(config.tasks[0].id == "task-1")
        #expect(config.tasks[0].prompt == "Do something")
        #expect(config.tasks[1].permissionMode == "auto")
    }

    @Test func parseJson() throws {
        let json = """
        {
            "project": "/tmp/test-repo",
            "tasks": [
                {"id": "t1", "description": "Desc", "prompt": "Go"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(ProjectConfig.self, from: data)
        #expect(config.project == "/tmp/test-repo")
        #expect(config.tasks.count == 1)
        #expect(config.tasks[0].id == "t1")
    }

    @Test func emptyPrompt() throws {
        let yaml = """
        project: /tmp/repo
        tasks:
          - id: interactive
            description: "Interactive session"
            prompt: ""
        """
        let config = try YAMLDecoder().decode(ProjectConfig.self, from: yaml)
        #expect(config.tasks[0].prompt == "")
    }
}
