// Local WorktreeManager operations are in CentralStationCore.
// This file adds remote operations that depend on RemoteShell.

extension WorktreeManager {
    // MARK: - Local operations requiring a remote

    static func pushBranch(projectPath: String, taskId: String) async throws {
        let taskBranch = "cs/\(taskId)"
        _ = try await ShellHelper.runGit(in: projectPath, args: ["push", "-u", "origin", taskBranch])
    }

    static func createPR(projectPath: String, taskId: String, message: String) async throws -> String {
        let taskBranch = "cs/\(taskId)"
        _ = try await ShellHelper.runGit(in: projectPath, args: ["push", "-u", "origin", taskBranch])
        let firstLine = message.split(separator: "\n").first.map(String.init) ?? "Changes from \(taskId)"
        let result = try await ShellHelper.run("/usr/bin/env", arguments: [
            "gh", "pr", "create",
            "--head", taskBranch,
            "--title", firstLine,
            "--body", message
        ], currentDirectory: projectPath)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Remote operations

    static func ensureGitRepoRemote(host: String, at path: String) async throws {
        do {
            _ = try await RemoteShell.runGit(host: host, inDirectory: path, args: ["rev-parse", "--git-dir"])
        } catch {
            _ = try await RemoteShell.runGit(host: host, inDirectory: path, args: ["init"])
            _ = try await RemoteShell.runGit(host: host, inDirectory: path, args: ["commit", "--allow-empty", "-m", "initial commit"])
        }
    }

    static func createWorktreeRemote(host: String, projectPath: String, taskId: String) async throws -> String {
        let worktreesDir = projectPath + "/.worktrees"
        let worktreePath = worktreesDir + "/" + taskId
        let branchName = "cs/\(taskId)"

        _ = try? await RemoteShell.run(host: host, command: "mkdir -p \(RemoteShell.shellEscape(worktreesDir))")

        if try await RemoteShell.pathExists(host: host, path: worktreePath) {
            return worktreePath
        }

        _ = try await RemoteShell.runGit(host: host, inDirectory: projectPath, args: [
            "worktree", "add", "-b", branchName, worktreePath
        ])
        return worktreePath
    }

    static func removeWorktreeRemote(host: String, projectPath: String, taskId: String) async {
        let worktreePath = projectPath + "/.worktrees/" + taskId
        _ = try? await RemoteShell.runGit(host: host, inDirectory: projectPath, args: [
            "worktree", "remove", worktreePath, "--force"
        ])
    }

    static func getDiffRemote(host: String, worktreePath: String) async -> String {
        do {
            let stat = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["diff", "HEAD", "--stat"])
            let diff = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["diff", "HEAD"])
            if stat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let status = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["status", "--short"])
                if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "Untracked/new files:\n\(status)"
                }
                return "No changes yet."
            }
            return stat + "\n" + diff
        } catch {
            return "Unable to get diff."
        }
    }

    static func getChangedFilesRemote(host: String, worktreePath: String) async -> [ChangedFile] {
        do {
            let diffNames = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["diff", "HEAD", "--name-status"])
            let untracked = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["ls-files", "--others", "--exclude-standard"])
            var files: [ChangedFile] = []
            for line in diffNames.split(separator: "\n") where !line.isEmpty {
                let parts = line.split(separator: "\t", maxSplits: 1)
                if parts.count == 2 {
                    files.append(ChangedFile(id: String(parts[1]), path: String(parts[1]), status: String(parts[0])))
                }
            }
            for line in untracked.split(separator: "\n") where !line.isEmpty {
                let path = String(line)
                if !files.contains(where: { $0.path == path }) {
                    files.append(ChangedFile(id: path, path: path, status: "??"))
                }
            }
            return files
        } catch {
            return []
        }
    }

    static func getFileDiffRemote(host: String, worktreePath: String, filePath: String) async -> String {
        do {
            let diff = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["diff", "HEAD", "--", filePath])
            if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let escapedPath = "'" + (worktreePath + "/" + filePath).replacingOccurrences(of: "'", with: "'\\''") + "'"
                let content = try await RemoteShell.run(host: host, command: "cat \(escapedPath) 2>/dev/null || echo '(binary or empty)'")
                let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "+\($0)" }.joined(separator: "\n")
                return "New file: \(filePath)\n\(lines)"
            }
            return diff
        } catch {
            return "Unable to get diff."
        }
    }

    static func commitWorktreeRemote(host: String, worktreePath: String, message: String) async throws {
        _ = try await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["add", "-A"])
        _ = try? await RemoteShell.runGit(host: host, inDirectory: worktreePath, args: ["commit", "-m", message, "--allow-empty"])
    }

    static func mergeToMainRemote(host: String, projectPath: String, taskId: String, message: String) async throws {
        let status = try await RemoteShell.runGit(host: host, inDirectory: projectPath, args: ["status", "--porcelain"])
        if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WorktreeError.dirtyWorkingTree(status.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let taskBranch = "cs/\(taskId)"
        _ = try await RemoteShell.runGit(host: host, inDirectory: projectPath, args: ["merge", taskBranch, "--no-ff", "-m", "Merge \(taskBranch): \(message)"])
    }

    static func pushBranchRemote(host: String, projectPath: String, taskId: String) async throws {
        let taskBranch = "cs/\(taskId)"
        _ = try await RemoteShell.runGit(host: host, inDirectory: projectPath, args: ["push", "-u", "origin", taskBranch])
    }

    static func createPRRemote(host: String, projectPath: String, taskId: String, message: String) async throws -> String {
        let taskBranch = "cs/\(taskId)"
        _ = try await RemoteShell.runGit(host: host, inDirectory: projectPath, args: ["push", "-u", "origin", taskBranch])
        let firstLine = message.split(separator: "\n").first.map(String.init) ?? "Changes from \(taskId)"
        let escapedPath = "'" + projectPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let escapedBranch = "'" + taskBranch.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let escapedTitle = "'" + firstLine.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let escapedMessage = "'" + message.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let result = try await RemoteShell.run(host: host, command: "cd \(escapedPath) && gh pr create --head \(escapedBranch) --title \(escapedTitle) --body \(escapedMessage)")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
