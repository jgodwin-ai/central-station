import Testing
import Foundation
@testable import CentralStationCore

@Suite("ensureGitRepo empty repo")
struct EnsureGitRepoTests {
    @Test func ensureGitRepoCreatesInitialCommitOnEmptyRepo() async throws {
        // Regression: repos with .git but no commits caused worktree creation to fail
        let path = NSTemporaryDirectory() + "cs-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        // git init but no commits — like a freshly init'd repo
        _ = try await ShellHelper.runGit(in: path, args: ["init"])

        // Should succeed and create an initial commit
        try await WorktreeManager.ensureGitRepo(at: path)

        // Verify HEAD exists now
        let head = try await ShellHelper.runGit(in: path, args: ["rev-parse", "HEAD"])
        #expect(!head.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func ensureGitRepoDoesNotDoubleCommitOnExistingRepo() async throws {
        let path = NSTemporaryDirectory() + "cs-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        _ = try await ShellHelper.runGit(in: path, args: ["init"])
        _ = try await ShellHelper.runGit(in: path, args: ["config", "user.email", "test@test.com"])
        _ = try await ShellHelper.runGit(in: path, args: ["config", "user.name", "Test"])
        _ = try await ShellHelper.runGit(in: path, args: ["commit", "--allow-empty", "-m", "existing"])

        let beforeCount = try await ShellHelper.runGit(in: path, args: ["rev-list", "--count", "HEAD"])

        try await WorktreeManager.ensureGitRepo(at: path)

        let afterCount = try await ShellHelper.runGit(in: path, args: ["rev-list", "--count", "HEAD"])
        #expect(beforeCount == afterCount, "Should not add extra commits to a repo that already has one")
    }

    @Test func ensureGitRepoThenCreateWorktreeSucceeds() async throws {
        // End-to-end: empty repo → ensureGitRepo → createWorktree should work
        let path = NSTemporaryDirectory() + "cs-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        _ = try await ShellHelper.runGit(in: path, args: ["init"])
        _ = try await ShellHelper.runGit(in: path, args: ["config", "user.email", "test@test.com"])
        _ = try await ShellHelper.runGit(in: path, args: ["config", "user.name", "Test"])

        try await WorktreeManager.ensureGitRepo(at: path)

        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: "test-task-1")
        defer {
            Task { await WorktreeManager.removeWorktree(projectPath: path, taskId: "test-task-1") }
        }

        #expect(FileManager.default.fileExists(atPath: worktreePath))
    }
}
