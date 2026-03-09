import Foundation

enum WorktreeError: LocalizedError {
    case dirtyWorkingTree

    var errorDescription: String? {
        switch self {
        case .dirtyWorkingTree:
            "Your project has uncommitted changes. Please commit or stash them before merging."
        }
    }
}

enum WorktreeManager {
    static func ensureGitRepo(at path: String) async throws {
        do {
            _ = try await ShellHelper.runGit(in: path, args: ["rev-parse", "--git-dir"])
        } catch {
            _ = try await ShellHelper.runGit(in: path, args: ["init"])
            _ = try await ShellHelper.runGit(in: path, args: ["commit", "--allow-empty", "-m", "initial commit"])
        }
    }

    static func createWorktree(projectPath: String, taskId: String) async throws -> String {
        let worktreesDir = (projectPath as NSString).appendingPathComponent(".worktrees")
        let worktreePath = (worktreesDir as NSString).appendingPathComponent(taskId)
        let branchName = "cs/\(taskId)"

        let fm = FileManager.default
        if !fm.fileExists(atPath: worktreesDir) {
            try fm.createDirectory(atPath: worktreesDir, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: worktreePath) {
            return worktreePath
        }

        _ = try await ShellHelper.runGit(in: projectPath, args: [
            "worktree", "add", "-b", branchName, worktreePath
        ])

        return worktreePath
    }

    static func removeWorktree(projectPath: String, taskId: String) async {
        let worktreePath = (projectPath as NSString)
            .appendingPathComponent(".worktrees")
            .appending("/\(taskId)")
        _ = try? await ShellHelper.runGit(in: projectPath, args: [
            "worktree", "remove", worktreePath, "--force"
        ])
    }

    static func getDiff(worktreePath: String) async -> String {
        do {
            let stat = try await ShellHelper.runGit(in: worktreePath, args: ["diff", "HEAD", "--stat"])
            let diff = try await ShellHelper.runGit(in: worktreePath, args: ["diff", "HEAD"])

            if stat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let status = try await ShellHelper.runGit(in: worktreePath, args: ["status", "--short"])
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

    struct ChangedFile: Identifiable, Hashable {
        let id: String
        let path: String
        let status: String // "M", "A", "D", "??"

        var statusLabel: String {
            switch status {
            case "M": "Modified"
            case "A": "Added"
            case "D": "Deleted"
            case "??": "New"
            default: status
            }
        }
    }

    static func getChangedFiles(worktreePath: String) async -> [ChangedFile] {
        do {
            let diffNames = try await ShellHelper.runGit(in: worktreePath, args: ["diff", "HEAD", "--name-status"])
            let untracked = try await ShellHelper.runGit(in: worktreePath, args: ["ls-files", "--others", "--exclude-standard"])

            var files: [ChangedFile] = []
            for line in diffNames.split(separator: "\n") where !line.isEmpty {
                let parts = line.split(separator: "\t", maxSplits: 1)
                if parts.count == 2 {
                    let status = String(parts[0])
                    let path = String(parts[1])
                    files.append(ChangedFile(id: path, path: path, status: status))
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

    static func getFileDiff(worktreePath: String, filePath: String) async -> String {
        do {
            let diff = try await ShellHelper.runGit(in: worktreePath, args: ["diff", "HEAD", "--", filePath])
            if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let fullPath = (worktreePath as NSString).appendingPathComponent(filePath)
                if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "+\($0)" }.joined(separator: "\n")
                    return "New file: \(filePath)\n\(lines)"
                }
                return "No diff available."
            }
            return diff
        } catch {
            return "Unable to get diff."
        }
    }

    static func commitAndMerge(worktreePath: String, projectPath: String, taskId: String, message: String) async throws {
        // Check for uncommitted changes in the main working tree
        let status = try await ShellHelper.runGit(in: projectPath, args: ["status", "--porcelain"])
        if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WorktreeError.dirtyWorkingTree
        }

        // Commit changes in the worktree branch
        _ = try await ShellHelper.runGit(in: worktreePath, args: ["add", "-A"])
        _ = try? await ShellHelper.runGit(in: worktreePath, args: ["commit", "-m", message, "--allow-empty"])

        let taskBranch = "cs/\(taskId)"
        _ = try await ShellHelper.runGit(in: projectPath, args: ["merge", taskBranch, "--no-ff", "-m", "Merge \(taskBranch): \(message)"])
    }

    static func pushBranch(projectPath: String, taskId: String) async throws {
        let taskBranch = "cs/\(taskId)"
        _ = try await ShellHelper.runGit(in: projectPath, args: ["push", "-u", "origin", taskBranch])
    }

    static func createPR(projectPath: String, taskId: String, message: String) async throws -> String {
        let taskBranch = "cs/\(taskId)"
        // Push first
        _ = try await ShellHelper.runGit(in: projectPath, args: ["push", "-u", "origin", taskBranch])
        // Create PR via gh CLI
        let firstLine = message.split(separator: "\n").first.map(String.init) ?? "Changes from \(taskId)"
        let result = try await ShellHelper.run("/usr/bin/env", arguments: [
            "gh", "pr", "create",
            "--head", taskBranch,
            "--title", firstLine,
            "--body", message
        ], currentDirectory: projectPath)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
