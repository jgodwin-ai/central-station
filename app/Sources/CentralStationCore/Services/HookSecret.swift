import Foundation

public enum HookSecret {
    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func validate(header: String, expected: String) -> Bool {
        guard header.hasPrefix("Bearer ") else { return false }
        let token = String(header.dropFirst("Bearer ".count))
        guard token.count == expected.count else { return false }
        var result: UInt8 = 0
        for (a, b) in zip(token.utf8, expected.utf8) {
            result |= a ^ b
        }
        return result == 0
    }
}
