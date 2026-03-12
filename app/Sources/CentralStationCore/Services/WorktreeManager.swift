import Foundation

public enum WorktreeError: LocalizedError {
    case dirtyWorkingTree(String)

    public var errorDescription: String? {
        switch self {
        case .dirtyWorkingTree(let files):
            "Your main branch has uncommitted changes. Please commit or stash them before merging.\n\n\(files)"
        }
    }
}

public enum WorktreeManager {
    public static func ensureGitRepo(at path: String) async throws {
        do {
            _ = try await ShellHelper.runGit(in: path, args: ["rev-parse", "--git-dir"])
        } catch {
            _ = try await ShellHelper.runGit(in: path, args: ["init"])
            _ = try await ShellHelper.runGit(in: path, args: ["commit", "--allow-empty", "-m", "initial commit"])
        }
    }

    public static func createWorktree(projectPath: String, taskId: String) async throws -> String {
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

    public static func removeWorktree(projectPath: String, taskId: String) async {
        let worktreePath = (projectPath as NSString)
            .appendingPathComponent(".worktrees")
            .appending("/\(taskId)")
        _ = try? await ShellHelper.runGit(in: projectPath, args: [
            "worktree", "remove", worktreePath, "--force"
        ])
    }

    public static func getDiff(worktreePath: String) async -> String {
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

    public struct ChangedFile: Identifiable, Hashable {
        public let id: String
        public let path: String
        public let status: String

        public var statusLabel: String {
            switch status {
            case "M": "Modified"
            case "A": "Added"
            case "D": "Deleted"
            case "??": "New"
            default: status
            }
        }

        public init(id: String, path: String, status: String) {
            self.id = id
            self.path = path
            self.status = status
        }
    }

    public static func getChangedFiles(worktreePath: String) async -> [ChangedFile] {
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

    public static func getFileDiff(worktreePath: String, filePath: String) async -> String {
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

    public static func commitWorktree(worktreePath: String, message: String) async throws {
        _ = try await ShellHelper.runGit(in: worktreePath, args: ["add", "-A"])
        _ = try? await ShellHelper.runGit(in: worktreePath, args: ["commit", "-m", message, "--allow-empty"])
    }

    public static func mergeToMain(projectPath: String, taskId: String, message: String) async throws {
        let status = try await ShellHelper.runGit(in: projectPath, args: ["status", "--porcelain"])
        if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WorktreeError.dirtyWorkingTree(status.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let taskBranch = "cs/\(taskId)"
        _ = try await ShellHelper.runGit(in: projectPath, args: ["merge", taskBranch, "--no-ff", "-m", "Merge \(taskBranch): \(message)"])
    }

}
