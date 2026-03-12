import Testing
import Foundation
@testable import CentralStationCore

@Suite("ShellHelper")
struct ShellHelperTests {
    @Test func runEchoCommand() async throws {
        let output = try await ShellHelper.run("/bin/echo", arguments: ["hello"])
        #expect(output.contains("hello"))
    }

    @Test func runWithCurrentDirectory() async throws {
        let output = try await ShellHelper.run("/bin/pwd", currentDirectory: "/tmp")
        #expect(output.contains("/tmp") || output.contains("/private/tmp"))
    }

    @Test func runFailingCommandThrows() async throws {
        await #expect(throws: ShellError.self) {
            try await ShellHelper.run("/usr/bin/false")
        }
    }

    @Test func runGitVersion() async throws {
        let output = try await ShellHelper.runGit(in: "/tmp", args: ["--version"])
        #expect(output.contains("git version"))
    }

    @Test func runGitInvalidCommandThrows() async throws {
        await #expect(throws: (any Error).self) {
            try await ShellHelper.runGit(in: "/tmp", args: ["not-a-real-command"])
        }
    }

    @Test func launchDetachedDoesNotBlock() throws {
        try ShellHelper.launchDetached("/bin/sleep", arguments: ["0"])
    }

    @Test func shellErrorDescription() {
        let error = ShellError.failed(status: 42, output: "oops")
        let description = error.errorDescription ?? ""
        #expect(description.contains("42"))
        #expect(description.contains("oops"))
    }

    @Test func runReturnsOutput() async throws {
        let output = try await ShellHelper.run("/usr/bin/printf", arguments: ["abc"])
        #expect(output == "abc")
    }
}
