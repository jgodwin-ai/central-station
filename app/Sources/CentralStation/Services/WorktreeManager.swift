// Local WorktreeManager operations are in CentralStationCore.
// This file adds local operations that require a remote (push/PR).

extension WorktreeManager {
    // MARK: - Local operations requiring a remote

    static func pushBranch(projectPath: String, taskId: String) async throws {
        let branch = "cs/\(taskId)"
        _ = try await ShellHelper.runGit(in: projectPath, args: ["push", "-u", "origin", branch])
    }

    static func createPR(projectPath: String, taskId: String, message: String) async throws -> String {
        let branch = "cs/\(taskId)"
        _ = try await ShellHelper.runGit(in: projectPath, args: ["push", "-u", "origin", branch])
        let firstLine = message.split(separator: "\n").first.map(String.init) ?? "Changes from \(taskId)"
        let result = try await ShellHelper.run("/usr/bin/env", arguments: [
            "gh", "pr", "create",
            "--head", branch,
            "--title", firstLine,
            "--body", message
        ], currentDirectory: projectPath)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
