import Foundation

enum ShellHelper {
    @discardableResult
    static func run(_ command: String, arguments: [String] = [], currentDirectory: String? = nil) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        if let dir = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ShellError.failed(status: process.terminationStatus, output: output)
        }
        return output
    }

    static func runGit(in directory: String, args: [String]) async throws -> String {
        try await run("/usr/bin/git", arguments: ["-C", directory] + args)
    }
}

enum ShellError: LocalizedError {
    case failed(status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .failed(let status, let output):
            "Command failed (exit \(status)): \(output)"
        }
    }
}
