import Testing
@testable import CentralStationCore

@Suite("HookSecret")
struct HookServerSecurityTests {
    @Test func secretIsNonEmpty() {
        let secret = HookSecret.generate()
        #expect(!secret.isEmpty)
    }

    @Test func secretIsReasonableLength() {
        let secret = HookSecret.generate()
        #expect(secret.count >= 32)
    }

    @Test func secretsAreDifferent() {
        let a = HookSecret.generate()
        let b = HookSecret.generate()
        #expect(a != b)
    }

    @Test func validateCorrectSecret() {
        let secret = HookSecret.generate()
        let header = "Bearer \(secret)"
        #expect(HookSecret.validate(header: header, expected: secret))
    }

    @Test func validateWrongSecret() {
        let secret = HookSecret.generate()
        let wrong = HookSecret.generate()
        let header = "Bearer \(wrong)"
        #expect(!HookSecret.validate(header: header, expected: secret))
    }

    @Test func validateMissingBearer() {
        let secret = HookSecret.generate()
        #expect(!HookSecret.validate(header: secret, expected: secret))
    }

    @Test func validateEmptyHeader() {
        let secret = HookSecret.generate()
        #expect(!HookSecret.validate(header: "", expected: secret))
    }
}
