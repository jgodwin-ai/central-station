import Foundation

enum RemoteShell {
    /// Run an arbitrary command on a remote host via SSH.
    @discardableResult
    static func run(host: String, command: String) async throws -> String {
        try await ShellHelper.run("/usr/bin/ssh", arguments: [
            "-o", "ConnectTimeout=10",
            host,
            command
        ])
    }

    /// Run a git command on a remote host in a specific directory.
    @discardableResult
    static func runGit(host: String, inDirectory directory: String, args: [String]) async throws -> String {
        let gitArgs = ["git", "-C", shellEscape(directory)] + args.map { shellEscape($0) }
        return try await run(host: host, command: gitArgs.joined(separator: " "))
    }

    /// List directories at a given path on the remote.
    static func listDirectories(host: String, path: String) async throws -> [String] {
        let output = try await run(host: host, command: "ls -1p \(shellEscape(path)) 2>/dev/null | grep '/$'")
        return output.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
    }

    /// Get the home directory on the remote.
    static func homeDirectory(host: String) async throws -> String {
        let output = try await run(host: host, command: "echo $HOME")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if a path exists on the remote.
    static func pathExists(host: String, path: String) async throws -> Bool {
        do {
            _ = try await run(host: host, command: "test -d \(shellEscape(path)) && echo yes")
            return true
        } catch {
            return false
        }
    }

    /// Check if a path is a git repo on the remote.
    static func isGitRepo(host: String, path: String) async throws -> Bool {
        do {
            _ = try await runGit(host: host, inDirectory: path, args: ["rev-parse", "--git-dir"])
            return true
        } catch {
            return false
        }
    }

    static func shellEscape(_ str: String) -> String {
        "'" + str.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
