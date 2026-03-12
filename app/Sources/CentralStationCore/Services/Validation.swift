import Foundation

public enum Validation {
    /// Sanitize a task ID: lowercase, strip non-alphanumeric except hyphens,
    /// replace spaces with hyphens, trim hyphens from edges, max 50 chars.
    public static func sanitizeTaskId(_ raw: String) -> String {
        var result = raw.lowercased()
        result = result.replacingOccurrences(of: " ", with: "-")
        result = result.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-"
        }.map { String($0) }.joined()
        // Collapse consecutive hyphens
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        // Trim leading/trailing hyphens
        while result.hasPrefix("-") { result.removeFirst() }
        while result.hasSuffix("-") { result.removeLast() }
        // Truncate to 50 characters
        if result.count > 50 {
            result = String(result.prefix(50))
        }
        return result
    }

    /// Validate that a URL is a valid update URL (must be under the official repo).
    public static func isValidUpdateURL(_ urlString: String) -> Bool {
        urlString.hasPrefix("https://github.com/jgodwin-ai/central-station/")
    }

    /// Validate that a PR URL is a valid GitHub PR URL over HTTPS.
    public static func isValidPRURL(_ urlString: String) -> Bool {
        urlString.hasPrefix("https://github.com/")
    }
}
