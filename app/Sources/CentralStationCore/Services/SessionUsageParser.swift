import Foundation

public struct SessionUsage: Sendable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var messageCount: Int = 0
    public var model: String?

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    /// Estimated cost in USD based on model pricing
    public var estimatedCostUSD: Double {
        let pricing = ModelPricing.forModel(model ?? "")
        let inputCost = Double(inputTokens) / 1_000_000 * pricing.inputPerMTok
        let outputCost = Double(outputTokens) / 1_000_000 * pricing.outputPerMTok
        let cacheReadCost = Double(cacheReadTokens) / 1_000_000 * pricing.cacheReadPerMTok
        let cacheCreateCost = Double(cacheCreationTokens) / 1_000_000 * pricing.cacheCreatePerMTok
        return inputCost + outputCost + cacheReadCost + cacheCreateCost
    }

    public var formattedCost: String {
        let cost = estimatedCostUSD
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }

    public var formattedTokens: String {
        if totalTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(totalTokens) / 1_000_000)
        } else if totalTokens >= 1_000 {
            return String(format: "%.1fK", Double(totalTokens) / 1_000)
        }
        return "\(totalTokens)"
    }

    /// Rough context window percentage (input + cache tokens vs 200K window)
    public var contextPercentage: Int {
        let contextTokens = inputTokens + cacheReadTokens + cacheCreationTokens
        let windowSize = 200_000
        return min(100, (contextTokens * 100) / max(1, windowSize))
    }
}

public struct ModelPricing: Sendable {
    public let inputPerMTok: Double
    public let outputPerMTok: Double
    public let cacheReadPerMTok: Double
    public let cacheCreatePerMTok: Double

    public static func forModel(_ model: String) -> ModelPricing {
        let m = model.lowercased()
        if m.contains("opus") {
            return ModelPricing(
                inputPerMTok: 15.0, outputPerMTok: 75.0,
                cacheReadPerMTok: 1.5, cacheCreatePerMTok: 18.75
            )
        } else if m.contains("haiku") {
            return ModelPricing(
                inputPerMTok: 0.80, outputPerMTok: 4.0,
                cacheReadPerMTok: 0.08, cacheCreatePerMTok: 1.0
            )
        } else {
            // Default to Sonnet pricing
            return ModelPricing(
                inputPerMTok: 3.0, outputPerMTok: 15.0,
                cacheReadPerMTok: 0.30, cacheCreatePerMTok: 3.75
            )
        }
    }
}

public enum SessionUsageParser {

    /// Parse usage from a JSONL file at the given path
    public static func parse(filePath: String) -> SessionUsage {
        guard let data = FileManager.default.contents(atPath: filePath),
              let content = String(data: data, encoding: .utf8) else {
            return SessionUsage()
        }
        return parse(content: content)
    }

    /// Parse usage from JSONL content string
    public static func parse(content: String) -> SessionUsage {
        var usage = SessionUsage()

        for line in content.split(separator: "\n") where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any] else {
                continue
            }

            // Only count lines that have actual token usage (assistant responses)
            guard let inputTokens = usageDict["input_tokens"] as? Int,
                  let outputTokens = usageDict["output_tokens"] as? Int else {
                continue
            }

            usage.inputTokens = inputTokens  // Last message's input = current context
            usage.outputTokens += outputTokens
            usage.cacheReadTokens = (usageDict["cache_read_input_tokens"] as? Int) ?? 0
            usage.cacheCreationTokens = (usageDict["cache_creation_input_tokens"] as? Int) ?? 0
            usage.messageCount += 1

            if let model = message["model"] as? String, model != "<synthetic>" {
                usage.model = model
            }
        }

        return usage
    }

    /// Find the JSONL file for a given session ID by searching Claude's project directories
    public static func findSessionFile(sessionId: String) -> String? {
        let claudeDirs = [
            (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects"),
            (NSHomeDirectory() as NSString).appendingPathComponent(".config/claude/projects")
        ]

        for baseDir in claudeDirs {
            if let file = findSessionFileIn(directory: baseDir, sessionId: sessionId) {
                return file
            }
        }
        return nil
    }

    /// Parse usage for a session by its ID
    public static func parseForSession(sessionId: String) -> SessionUsage {
        guard let path = findSessionFile(sessionId: sessionId) else {
            return SessionUsage()
        }
        return parse(filePath: path)
    }

    private static func findSessionFileIn(directory: String, sessionId: String) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let target = "\(sessionId).jsonl"
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == target {
                return url.path
            }
        }
        return nil
    }
}
