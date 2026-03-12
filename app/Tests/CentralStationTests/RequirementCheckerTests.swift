import Testing
import Foundation
@testable import CentralStationCore

@Suite("RequirementChecker")
struct RequirementCheckerTests {
    @Test func allSatisfiedWhenEverythingPresent() {
        let result = RequirementChecker.check(
            requirements: RequirementChecker.defaultRequirements,
            isAvailable: { _ in true }
        )
        #expect(result.allSatisfied)
        #expect(result.canStart)
        #expect(result.missingEssential.isEmpty)
        #expect(result.missingRecommended.isEmpty)
    }

    @Test func cannotStartWhenEssentialMissing() {
        let result = RequirementChecker.check(
            requirements: RequirementChecker.defaultRequirements,
            isAvailable: { _ in false }
        )
        #expect(!result.canStart)
        #expect(!result.allSatisfied)
        #expect(result.missingEssential.count == 2) // git, claude
        #expect(result.missingRecommended.count == 1) // gh
    }

    @Test func canStartWithOnlyRecommendedMissing() {
        let result = RequirementChecker.check(
            requirements: RequirementChecker.defaultRequirements,
            isAvailable: { command in command != "gh" }
        )
        #expect(result.canStart)
        #expect(!result.allSatisfied)
        #expect(result.missingEssential.isEmpty)
        #expect(result.missingRecommended.count == 1)
        #expect(result.missingRecommended.first?.name == "GitHub CLI")
    }

    @Test func blocksOnMissingGit() {
        let result = RequirementChecker.check(
            requirements: RequirementChecker.defaultRequirements,
            isAvailable: { command in command != "git" }
        )
        #expect(!result.canStart)
        #expect(result.missingEssential.count == 1)
        #expect(result.missingEssential.first?.name == "Git")
    }

    @Test func blocksOnMissingClaude() {
        let result = RequirementChecker.check(
            requirements: RequirementChecker.defaultRequirements,
            isAvailable: { command in command != "claude" }
        )
        #expect(!result.canStart)
        #expect(result.missingEssential.count == 1)
        #expect(result.missingEssential.first?.name == "Claude Code")
    }

    @Test func emptyRequirementsAllSatisfied() {
        let result = RequirementChecker.check(
            requirements: [],
            isAvailable: { _ in false }
        )
        #expect(result.allSatisfied)
        #expect(result.canStart)
    }

    @Test func customRequirements() {
        let reqs = [
            RequirementChecker.Requirement(
                name: "Node.js", command: "node",
                importance: .recommended, installHint: "brew install node"
            ),
        ]
        let result = RequirementChecker.check(
            requirements: reqs,
            isAvailable: { _ in false }
        )
        #expect(result.canStart)
        #expect(result.missingRecommended.count == 1)
        #expect(result.missingRecommended.first?.command == "node")
    }

    @Test func formatEssentialErrorIncludesAllMissing() {
        let missing = [
            RequirementChecker.Requirement(
                name: "Git", command: "git",
                importance: .essential, installHint: "xcode-select --install"
            ),
            RequirementChecker.Requirement(
                name: "Claude Code", command: "claude",
                importance: .essential, installHint: "npm install -g @anthropic-ai/claude-code"
            ),
        ]
        let message = RequirementChecker.formatEssentialError(missing)
        #expect(message.contains("Git"))
        #expect(message.contains("Claude Code"))
        #expect(message.contains("xcode-select --install"))
        #expect(message.contains("npm install"))
        #expect(message.contains("\u{2717}"))
    }

    @Test func formatRecommendedWarningIncludesHints() {
        let missing = [
            RequirementChecker.Requirement(
                name: "GitHub CLI", command: "gh",
                importance: .recommended, installHint: "brew install gh"
            ),
        ]
        let message = RequirementChecker.formatRecommendedWarning(missing)
        #expect(message.contains("GitHub CLI"))
        #expect(message.contains("brew install gh"))
        #expect(message.contains("PR creation"))
    }

    @Test func commandExistsFindsRealCommand() {
        // Use "which" itself — it's at /usr/bin/which and always findable
        #expect(RequirementChecker.commandExists("which"))
    }

    @Test func commandExistsReturnsFalseForFake() {
        #expect(!RequirementChecker.commandExists("not-a-real-command-xyz-123"))
    }

    @Test func defaultRequirementsHaveCorrectImportance() {
        let essentials = RequirementChecker.defaultRequirements.filter { $0.importance == .essential }
        let recommended = RequirementChecker.defaultRequirements.filter { $0.importance == .recommended }
        #expect(essentials.count == 2)
        #expect(recommended.count == 1)
        #expect(essentials.contains { $0.command == "git" })
        #expect(essentials.contains { $0.command == "claude" })
        #expect(recommended.contains { $0.command == "gh" })
    }
}
