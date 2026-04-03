import Testing
import Foundation
@testable import CentralStationCore

@Suite("Repo model")
struct RepoTests {
    @Test func repoNameDerivedFromPath() {
        let repo = Repo(path: "/Users/me/projects/central-station")
        #expect(repo.name == "central-station")
        #expect(!repo.id.isEmpty)
    }

    @Test func repoNameFromTrailingSlash() {
        let repo = Repo(path: "/Users/me/projects/my-app/")
        #expect(repo.name == "my-app")
    }

    @Test func repoRoundTrip() throws {
        let repo = Repo(path: "/Users/me/projects/test")
        let data = try JSONEncoder().encode(repo)
        let decoded = try JSONDecoder().decode(Repo.self, from: data)
        #expect(decoded.id == repo.id)
        #expect(decoded.path == repo.path)
    }
}

@Suite("Repo persistence")
struct RepoPersistenceTests {
    @Test func generateTaskIdIncrementsCounter() {
        var persistence = RepoPersistence(repos: [], nextTaskNumber: 1)
        let id1 = persistence.nextTaskId()
        let id2 = persistence.nextTaskId()

        #expect(id1.hasSuffix("-task-1"))
        #expect(id2.hasSuffix("-task-2"))
        #expect(persistence.nextTaskNumber == 3)
    }

    @Test func generateTaskIdIncludesDate() {
        var persistence = RepoPersistence(repos: [], nextTaskNumber: 1)
        let id = persistence.nextTaskId()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        #expect(id.hasPrefix(today))
    }

    @Test func persistenceRoundTrip() throws {
        let repos = [Repo(path: "/Users/me/proj1"), Repo(path: "/Users/me/proj2")]
        let persistence = RepoPersistence(repos: repos, nextTaskNumber: 5)
        let data = try JSONEncoder().encode(persistence)
        let decoded = try JSONDecoder().decode(RepoPersistence.self, from: data)

        #expect(decoded.repos.count == 2)
        #expect(decoded.nextTaskNumber == 5)
        #expect(decoded.repos[0].path == "/Users/me/proj1")
    }

    @Test func counterPersistsAcrossDays() {
        var persistence = RepoPersistence(repos: [], nextTaskNumber: 7)
        let id = persistence.nextTaskId()
        #expect(id.hasSuffix("-task-7"))
        #expect(persistence.nextTaskNumber == 8)
    }

    @Test func customNameUsedInTaskId() {
        var persistence = RepoPersistence(repos: [], nextTaskNumber: 1)
        let id = persistence.nextTaskId(customName: "Fix Auth Bug")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        #expect(id == "\(today)-fix-auth-bug")
        #expect(persistence.nextTaskNumber == 2)
    }

    @Test func emptyCustomNameFallsBackToCounter() {
        var persistence = RepoPersistence(repos: [], nextTaskNumber: 3)
        let id = persistence.nextTaskId(customName: "")
        #expect(id.hasSuffix("-task-3"))
    }

    @Test func requireTaskNameDefaultsFalse() {
        let persistence = RepoPersistence()
        #expect(persistence.requireTaskName == false)
    }

    @Test func requireTaskNameRoundTrip() throws {
        let persistence = RepoPersistence(repos: [], nextTaskNumber: 1, requireTaskName: true)
        let data = try JSONEncoder().encode(persistence)
        let decoded = try JSONDecoder().decode(RepoPersistence.self, from: data)
        #expect(decoded.requireTaskName == true)
    }
}
