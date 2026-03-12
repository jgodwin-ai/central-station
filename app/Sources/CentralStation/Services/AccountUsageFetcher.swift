import Foundation
import Security

public struct AccountUsage: Sendable {
    public let fiveHourPercent: Double
    public let sevenDayPercent: Double
    public let fiveHourResetAt: Date?
    public let sevenDayResetAt: Date?

    public var fiveHourFormatted: String {
        String(format: "%.0f%%", fiveHourPercent)
    }

    public var sevenDayFormatted: String {
        String(format: "%.0f%%", sevenDayPercent)
    }

    public var fiveHourResetIn: String? {
        guard let reset = fiveHourResetAt else { return nil }
        return formatTimeRemaining(until: reset)
    }

    public var sevenDayResetIn: String? {
        guard let reset = sevenDayResetAt else { return nil }
        return formatTimeRemaining(until: reset)
    }

    private func formatTimeRemaining(until date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return "now" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

@MainActor
enum AccountUsageFetcher {
    private static var cachedUsage: AccountUsage?
    private static var cachedAt: Date?
    private static let cacheTTL: TimeInterval = 60 // 60 seconds

    static func fetch() async -> AccountUsage? {
        // Check cache
        if let cached = cachedUsage, let at = cachedAt,
           Date().timeIntervalSince(at) < cacheTTL {
            return cached
        }

        guard let token = getOAuthToken() else { return nil }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let usage = parseUsageResponse(json)
        cachedUsage = usage
        cachedAt = Date()
        return usage
    }

    static func clearCache() {
        cachedUsage = nil
        cachedAt = nil
    }

    private static func parseUsageResponse(_ json: [String: Any]) -> AccountUsage {
        let fiveHour = json["five_hour"] as? [String: Any]
        let sevenDay = json["seven_day"] as? [String: Any]

        let fiveHourPct = fiveHour?["utilization"] as? Double ?? 0
        let sevenDayPct = sevenDay?["utilization"] as? Double ?? 0

        let fiveHourReset = parseDate(fiveHour?["reset_at"] as? String)
        let sevenDayReset = parseDate(sevenDay?["reset_at"] as? String)

        return AccountUsage(
            fiveHourPercent: fiveHourPct * 100,
            sevenDayPercent: sevenDayPct * 100,
            fiveHourResetAt: fiveHourReset,
            sevenDayResetAt: sevenDayReset
        )
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// Try to get OAuth token from macOS Keychain (where Claude Code stores it)
    private static func getOAuthToken() -> String? {
        // First try the credentials file
        let credentialsPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/.credentials.json")
        if let data = FileManager.default.contents(atPath: credentialsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["claudeAiOauth"] as? [String: Any],
           let accessToken = token["accessToken"] as? String {
            return accessToken
        }

        // Fall back to Keychain (Claude Code 2.x stores credentials here)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "claude.ai",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["accessToken"] as? String else {
            return nil
        }
        return accessToken
    }
}
