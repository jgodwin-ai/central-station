import Testing
@testable import CentralStationCore

@Suite("Input validation")
struct ValidationTests {
    // MARK: - sanitizeTaskId

    @Test func simpleIdPassesThrough() {
        #expect(Validation.sanitizeTaskId("my-task") == "my-task")
    }

    @Test func uppercaseGetsLowercased() {
        #expect(Validation.sanitizeTaskId("My-Task") == "my-task")
    }

    @Test func spacesBecomeHyphens() {
        #expect(Validation.sanitizeTaskId("my task name") == "my-task-name")
    }

    @Test func shellMetacharsStripped() {
        #expect(Validation.sanitizeTaskId("'; rm -rf /") == "rm-rf")
    }

    @Test func emptyStringStaysEmpty() {
        #expect(Validation.sanitizeTaskId("") == "")
    }

    @Test func longIdTruncatedTo50() {
        let long = String(repeating: "a", count: 80)
        let result = Validation.sanitizeTaskId(long)
        #expect(result.count == 50)
    }

    @Test func leadingTrailingHyphensStripped() {
        #expect(Validation.sanitizeTaskId("--hello--") == "hello")
    }

    @Test func onlySpecialCharsBecomesEmpty() {
        #expect(Validation.sanitizeTaskId("$!@#%^&*()") == "")
    }

    @Test func mixedContentSanitized() {
        #expect(Validation.sanitizeTaskId("  Fix Bug #123  ") == "fix-bug-123")
    }

    // MARK: - isValidUpdateURL

    @Test func validUpdateURL() {
        #expect(Validation.isValidUpdateURL("https://github.com/jgodwin-ai/central-station/releases/tag/v1.0.0"))
    }

    @Test func invalidUpdateURLWrongRepo() {
        #expect(!Validation.isValidUpdateURL("https://github.com/evil/repo/releases"))
    }

    @Test func invalidUpdateURLHttp() {
        #expect(!Validation.isValidUpdateURL("http://github.com/jgodwin-ai/central-station/releases"))
    }

    @Test func invalidUpdateURLArbitrary() {
        #expect(!Validation.isValidUpdateURL("https://evil.com/payload"))
    }

    // MARK: - isValidPRURL

    @Test func validPRURL() {
        #expect(Validation.isValidPRURL("https://github.com/jgodwin-ai/central-station/pull/42"))
    }

    @Test func invalidPRURLHttp() {
        #expect(!Validation.isValidPRURL("http://github.com/org/repo/pull/1"))
    }

    @Test func invalidPRURLArbitrary() {
        #expect(!Validation.isValidPRURL("https://evil.com/something"))
    }
}
