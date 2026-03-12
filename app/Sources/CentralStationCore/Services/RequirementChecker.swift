import Foundation

public enum RequirementChecker {
    public enum Importance: String, Sendable {
        case essential
        case recommended
    }

    public struct Requirement: Sendable {
        public let name: String
        public let command: String
        public let importance: Importance
        public let installHint: String

        public init(name: String, command: String, importance: Importance, installHint: String) {
            self.name = name
            self.command = command
            self.importance = importance
            self.installHint = installHint
        }
    }

    public struct Result: Sendable {
        public let missingEssential: [Requirement]
        public let missingRecommended: [Requirement]

        public var allSatisfied: Bool { missingEssential.isEmpty && missingRecommended.isEmpty }
        public var canStart: Bool { missingEssential.isEmpty }
    }

    public static let defaultRequirements: [Requirement] = [
        Requirement(
            name: "Git",
            command: "git",
            importance: .essential,
            installHint: "Install Xcode Command Line Tools: xcode-select --install"
        ),
        Requirement(
            name: "Claude Code",
            command: "claude",
            importance: .essential,
            installHint: "Install via npm: npm install -g @anthropic-ai/claude-code"
        ),
        Requirement(
            name: "GitHub CLI",
            command: "gh",
            importance: .recommended,
            installHint: "Install via Homebrew: brew install gh"
        ),
    ]

    public static func check(
        requirements: [Requirement] = defaultRequirements,
        isAvailable: (String) -> Bool = commandExists
    ) -> Result {
        var missingEssential: [Requirement] = []
        var missingRecommended: [Requirement] = []

        for req in requirements {
            if !isAvailable(req.command) {
                switch req.importance {
                case .essential:
                    missingEssential.append(req)
                case .recommended:
                    missingRecommended.append(req)
                }
            }
        }

        return Result(
            missingEssential: missingEssential,
            missingRecommended: missingRecommended
        )
    }

    public static func commandExists(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public static func formatEssentialError(_ missing: [Requirement]) -> String {
        var lines = ["Central Station requires the following to run:\n"]
        for req in missing {
            lines.append("  \u{2717} \(req.name) — \(req.installHint)")
        }
        lines.append("\nPlease install the missing dependencies and relaunch.")
        return lines.joined(separator: "\n")
    }

    public static func formatRecommendedWarning(_ missing: [Requirement]) -> String {
        let items = missing.map { "\($0.name) (\($0.installHint))" }
        return "Optional tools not found: " + items.joined(separator: ", ")
            + ". Some features like PR creation may not work."
    }
}
