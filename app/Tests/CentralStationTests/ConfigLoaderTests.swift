import Testing
import Foundation
import Yams
@testable import CentralStationCore

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

    // MARK: - ConfigLoader.load(from:) tests

    @Test func loadFromYamlFile() throws {
        let path = NSTemporaryDirectory() + "test-config-\(UUID().uuidString).yaml"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let yaml = """
        project: /tmp/yaml-repo
        tasks:
          - id: y1
            description: "YAML task"
            prompt: "Run yaml"
        """
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(from: path)
        #expect(config.project == "/tmp/yaml-repo")
        #expect(config.tasks.count == 1)
        #expect(config.tasks[0].id == "y1")
        #expect(config.tasks[0].description == "YAML task")
        #expect(config.tasks[0].prompt == "Run yaml")
    }

    @Test func loadFromJsonFile() throws {
        let path = NSTemporaryDirectory() + "test-config-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let json = """
        {
            "project": "/tmp/json-repo",
            "tasks": [
                {"id": "j1", "description": "JSON task", "prompt": "Run json"}
            ]
        }
        """
        try json.write(toFile: path, atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(from: path)
        #expect(config.project == "/tmp/json-repo")
        #expect(config.tasks.count == 1)
        #expect(config.tasks[0].id == "j1")
        #expect(config.tasks[0].prompt == "Run json")
    }

    @Test func loadFromYmlExtension() throws {
        let path = NSTemporaryDirectory() + "test-config-\(UUID().uuidString).yml"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let yaml = """
        project: /tmp/yml-repo
        tasks:
          - id: yml1
            description: "YML task"
            prompt: "Run yml"
            permission_mode: plan
        """
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(from: path)
        #expect(config.project == "/tmp/yml-repo")
        #expect(config.tasks[0].id == "yml1")
        #expect(config.tasks[0].permissionMode == "plan")
    }

    @Test func loadNonexistentFileThrows() throws {
        let path = NSTemporaryDirectory() + "nonexistent-\(UUID().uuidString).yaml"
        #expect(throws: (any Error).self) {
            _ = try ConfigLoader.load(from: path)
        }
    }
}
