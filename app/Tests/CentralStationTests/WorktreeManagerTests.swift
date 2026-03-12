import Testing
import Foundation
@testable import CentralStationCore

@Suite("WorktreeManager")
struct WorktreeManagerTests {

    private func makeTempRepo() async throws -> String {
        let path = NSTemporaryDirectory() + "cs-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        _ = try await ShellHelper.runGit(in: path, args: ["init"])
        _ = try await ShellHelper.runGit(in: path, args: ["config", "user.email", "test@test.com"])
        _ = try await ShellHelper.runGit(in: path, args: ["config", "user.name", "Test"])
        try "hello".write(toFile: path + "/file.txt", atomically: true, encoding: .utf8)
        _ = try await ShellHelper.runGit(in: path, args: ["add", "-A"])
        _ = try await ShellHelper.runGit(in: path, args: ["commit", "-m", "initial"])
        return path
    }

    /// Remove worktree via git before filesystem cleanup so git doesn't complain.
    private func cleanupWorktree(projectPath: String, taskId: String) async {
        await WorktreeManager.removeWorktree(projectPath: projectPath, taskId: taskId)
    }

    @Test func ensureGitRepoOnNewDir() async throws {
        let path = NSTemporaryDirectory() + "cs-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        try await WorktreeManager.ensureGitRepo(at: path)

        let gitDir = (path as NSString).appendingPathComponent(".git")
        #expect(FileManager.default.fileExists(atPath: gitDir))
    }

    @Test func ensureGitRepoOnExistingRepo() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try await WorktreeManager.ensureGitRepo(at: path)

        let gitDir = (path as NSString).appendingPathComponent(".git")
        #expect(FileManager.default.fileExists(atPath: gitDir))
    }

    @Test func createAndRemoveWorktree() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let taskId = "test-task"
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)

        #expect(FileManager.default.fileExists(atPath: worktreePath))

        await WorktreeManager.removeWorktree(projectPath: path, taskId: taskId)

        #expect(!FileManager.default.fileExists(atPath: worktreePath))
    }

    @Test func createWorktreeIdempotent() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let taskId = "idem-task"
        let first = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)
        let second = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)

        #expect(first == second)

        await cleanupWorktree(projectPath: path, taskId: taskId)
    }

    @Test func getDiffNoChanges() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let taskId = "diff-none"
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)
        let diff = await WorktreeManager.getDiff(worktreePath: worktreePath)

        #expect(diff == "No changes yet.")

        await cleanupWorktree(projectPath: path, taskId: taskId)
    }

    @Test func getDiffWithChanges() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let taskId = "diff-yes"
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)
        try "modified".write(toFile: worktreePath + "/file.txt", atomically: true, encoding: .utf8)

        let diff = await WorktreeManager.getDiff(worktreePath: worktreePath)

        #expect(diff != "No changes yet.")
        #expect(diff.contains("file.txt"))

        await cleanupWorktree(projectPath: path, taskId: taskId)
    }

    @Test func getChangedFilesModified() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let taskId = "cf-mod"
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)
        try "changed".write(toFile: worktreePath + "/file.txt", atomically: true, encoding: .utf8)
        _ = try await ShellHelper.runGit(in: worktreePath, args: ["add", "file.txt"])

        let files = await WorktreeManager.getChangedFiles(worktreePath: worktreePath)

        #expect(files.count == 1)
        #expect(files[0].status == "M")
        #expect(files[0].path == "file.txt")

        await cleanupWorktree(projectPath: path, taskId: taskId)
    }

    @Test func getChangedFilesUntracked() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let taskId = "cf-new"
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)
        try "brand new".write(toFile: worktreePath + "/newfile.txt", atomically: true, encoding: .utf8)

        let files = await WorktreeManager.getChangedFiles(worktreePath: worktreePath)

        let newFile = files.first { $0.path == "newfile.txt" }
        #expect(newFile != nil)
        #expect(newFile?.status == "??")

        await cleanupWorktree(projectPath: path, taskId: taskId)
    }

    @Test func getFileDiffModified() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let taskId = "fd-mod"
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)
        try "changed content".write(toFile: worktreePath + "/file.txt", atomically: true, encoding: .utf8)
        _ = try await ShellHelper.runGit(in: worktreePath, args: ["add", "file.txt"])

        let diff = await WorktreeManager.getFileDiff(worktreePath: worktreePath, filePath: "file.txt")

        #expect(diff.contains("file.txt"))
        #expect(diff.contains("changed content"))

        await cleanupWorktree(projectPath: path, taskId: taskId)
    }

    @Test func getFileDiffNewFile() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let taskId = "fd-new"
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)
        try "new content".write(toFile: worktreePath + "/brand_new.txt", atomically: true, encoding: .utf8)

        let diff = await WorktreeManager.getFileDiff(worktreePath: worktreePath, filePath: "brand_new.txt")

        #expect(diff.contains("New file:"))
        #expect(diff.contains("new content"))

        await cleanupWorktree(projectPath: path, taskId: taskId)
    }

    @Test func commitWorktree() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let taskId = "commit-t"
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)
        try "committed".write(toFile: worktreePath + "/file.txt", atomically: true, encoding: .utf8)

        try await WorktreeManager.commitWorktree(worktreePath: worktreePath, message: "test commit")

        let status = try await ShellHelper.runGit(in: worktreePath, args: ["status", "--porcelain"])
        #expect(status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        await cleanupWorktree(projectPath: path, taskId: taskId)
    }

    @Test func mergeToMain() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Ensure .worktrees dir is ignored so it doesn't dirty the working tree
        try ".worktrees/\n".write(toFile: path + "/.gitignore", atomically: true, encoding: .utf8)
        _ = try await ShellHelper.runGit(in: path, args: ["add", ".gitignore"])
        _ = try await ShellHelper.runGit(in: path, args: ["commit", "-m", "add gitignore"])

        let taskId = "merge-t"
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)
        try "merged content".write(toFile: worktreePath + "/file.txt", atomically: true, encoding: .utf8)
        try await WorktreeManager.commitWorktree(worktreePath: worktreePath, message: "worktree change")

        try await WorktreeManager.mergeToMain(projectPath: path, taskId: taskId, message: "merge it")

        let content = try String(contentsOfFile: path + "/file.txt", encoding: .utf8)
        #expect(content == "merged content")

        await cleanupWorktree(projectPath: path, taskId: taskId)
    }

    @Test func mergeToMainDirtyThrows() async throws {
        let path = try await makeTempRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let taskId = "merge-dirty"
        let worktreePath = try await WorktreeManager.createWorktree(projectPath: path, taskId: taskId)
        try "wt change".write(toFile: worktreePath + "/file.txt", atomically: true, encoding: .utf8)
        try await WorktreeManager.commitWorktree(worktreePath: worktreePath, message: "wt commit")

        // Dirty the main working tree
        try "dirty".write(toFile: path + "/dirty.txt", atomically: true, encoding: .utf8)

        await #expect(throws: WorktreeError.self) {
            try await WorktreeManager.mergeToMain(projectPath: path, taskId: taskId, message: "should fail")
        }

        await cleanupWorktree(projectPath: path, taskId: taskId)
    }

    @Test func changedFileStatusLabels() {
        let modified = WorktreeManager.ChangedFile(id: "a", path: "a", status: "M")
        #expect(modified.statusLabel == "Modified")

        let added = WorktreeManager.ChangedFile(id: "b", path: "b", status: "A")
        #expect(added.statusLabel == "Added")

        let deleted = WorktreeManager.ChangedFile(id: "c", path: "c", status: "D")
        #expect(deleted.statusLabel == "Deleted")

        let new = WorktreeManager.ChangedFile(id: "d", path: "d", status: "??")
        #expect(new.statusLabel == "New")

        let unknown = WorktreeManager.ChangedFile(id: "e", path: "e", status: "R")
        #expect(unknown.statusLabel == "R")
    }

    @Test func worktreeErrorDescription() {
        let error = WorktreeError.dirtyWorkingTree("M file.txt")
        let desc = error.errorDescription ?? ""

        #expect(desc.contains("M file.txt"))
        #expect(desc.contains("uncommitted changes"))
    }
}
