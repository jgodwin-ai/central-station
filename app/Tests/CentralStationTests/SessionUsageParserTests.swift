import Testing
@testable import CentralStationCore

@Suite("SessionUsageParser Tests")
struct SessionUsageParserTests {

    @Test("Parse empty content returns zero usage")
    func parseEmpty() {
        let usage = SessionUsageParser.parse(content: "")
        #expect(usage.totalTokens == 0)
        #expect(usage.messageCount == 0)
        #expect(usage.model == nil)
    }

    @Test("Parse single assistant message")
    func parseSingleMessage() {
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-sonnet-4-20250514","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":200,"cache_creation_input_tokens":100}}}
        """
        let usage = SessionUsageParser.parse(content: jsonl)
        #expect(usage.inputTokens == 1000)
        #expect(usage.outputTokens == 500)
        #expect(usage.cacheReadTokens == 200)
        #expect(usage.cacheCreationTokens == 100)
        #expect(usage.totalTokens == 1800)
        #expect(usage.messageCount == 1)
        #expect(usage.model == "claude-sonnet-4-20250514")
    }

    @Test("Parse multiple messages accumulates output tokens, uses last input")
    func parseMultipleMessages() {
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-sonnet-4-20250514","usage":{"input_tokens":500,"output_tokens":100,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        {"type":"user","message":{"role":"user","content":"do more"}}
        {"type":"assistant","message":{"model":"claude-sonnet-4-20250514","usage":{"input_tokens":1500,"output_tokens":300,"cache_read_input_tokens":400,"cache_creation_input_tokens":50}}}
        """
        let usage = SessionUsageParser.parse(content: jsonl)
        // input_tokens should be from last message (current context)
        #expect(usage.inputTokens == 1500)
        // output_tokens should accumulate
        #expect(usage.outputTokens == 400)
        #expect(usage.cacheReadTokens == 400)
        #expect(usage.cacheCreationTokens == 50)
        #expect(usage.messageCount == 2)
    }

    @Test("Skip lines without usage data")
    func skipNonUsageLines() {
        let jsonl = """
        {"type":"system","content":"hello"}
        {"type":"user","message":{"role":"user","content":"test"}}
        {"type":"progress","data":{"type":"hook_progress"}}
        {"type":"assistant","message":{"model":"claude-sonnet-4","usage":{"input_tokens":100,"output_tokens":50}}}
        not json at all
        """
        let usage = SessionUsageParser.parse(content: jsonl)
        #expect(usage.messageCount == 1)
        #expect(usage.inputTokens == 100)
        #expect(usage.outputTokens == 50)
    }

    @Test("Skip synthetic model")
    func skipSyntheticModel() {
        let jsonl = """
        {"type":"assistant","message":{"model":"<synthetic>","usage":{"input_tokens":100,"output_tokens":50}}}
        {"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":200,"output_tokens":75}}}
        """
        let usage = SessionUsageParser.parse(content: jsonl)
        #expect(usage.model == "claude-opus-4-6")
        // But both still count for tokens
        #expect(usage.messageCount == 2)
    }

    @Test("Parse file that doesn't exist returns zero usage")
    func parseNonexistentFile() {
        let usage = SessionUsageParser.parse(filePath: "/nonexistent/path.jsonl")
        #expect(usage.totalTokens == 0)
    }

    @Test("Missing optional cache fields default to zero")
    func missingCacheFields() {
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-sonnet-4","usage":{"input_tokens":1000,"output_tokens":500}}}
        """
        let usage = SessionUsageParser.parse(content: jsonl)
        #expect(usage.cacheReadTokens == 0)
        #expect(usage.cacheCreationTokens == 0)
        #expect(usage.totalTokens == 1500)
    }
}

@Suite("SessionUsage Tests")
struct SessionUsageTests {

    @Test("Formatted tokens - small")
    func formattedTokensSmall() {
        var usage = SessionUsage()
        usage.inputTokens = 500
        #expect(usage.formattedTokens == "500")
    }

    @Test("Formatted tokens - thousands")
    func formattedTokensK() {
        var usage = SessionUsage()
        usage.inputTokens = 5000
        usage.outputTokens = 1200
        #expect(usage.formattedTokens == "6.2K")
    }

    @Test("Formatted tokens - millions")
    func formattedTokensM() {
        var usage = SessionUsage()
        usage.inputTokens = 1_500_000
        #expect(usage.formattedTokens == "1.5M")
    }

    @Test("Cost calculation - Sonnet")
    func costSonnet() {
        var usage = SessionUsage()
        usage.inputTokens = 1_000_000
        usage.outputTokens = 100_000
        usage.model = "claude-sonnet-4-20250514"
        // input: $3.00, output: $1.50
        let cost = usage.estimatedCostUSD
        #expect(cost > 4.4 && cost < 4.6)
    }

    @Test("Cost calculation - Opus")
    func costOpus() {
        var usage = SessionUsage()
        usage.inputTokens = 1_000_000
        usage.outputTokens = 100_000
        usage.model = "claude-opus-4-6"
        // input: $15.00, output: $7.50
        let cost = usage.estimatedCostUSD
        #expect(cost > 22.4 && cost < 22.6)
    }

    @Test("Formatted cost - small")
    func formattedCostSmall() {
        var usage = SessionUsage()
        usage.inputTokens = 1000
        usage.model = "claude-sonnet-4"
        #expect(usage.formattedCost.hasPrefix("$0.00"))
    }

    @Test("Formatted cost - large")
    func formattedCostLarge() {
        var usage = SessionUsage()
        usage.inputTokens = 1_000_000
        usage.outputTokens = 500_000
        usage.model = "claude-sonnet-4"
        // $3 + $7.50 = $10.50
        #expect(usage.formattedCost == "$10.50")
    }

    @Test("Context percentage calculation")
    func contextPercentage() {
        var usage = SessionUsage()
        usage.inputTokens = 100_000
        usage.cacheReadTokens = 50_000
        // (100000 + 50000) / 200000 = 75%
        #expect(usage.contextPercentage == 75)
    }

    @Test("Context percentage capped at 100")
    func contextPercentageCapped() {
        var usage = SessionUsage()
        usage.inputTokens = 250_000
        #expect(usage.contextPercentage == 100)
    }
}

@Suite("ModelPricing Tests")
struct ModelPricingTests {

    @Test("Opus pricing")
    func opusPricing() {
        let pricing = ModelPricing.forModel("claude-opus-4-6")
        #expect(pricing.inputPerMTok == 15.0)
        #expect(pricing.outputPerMTok == 75.0)
    }

    @Test("Sonnet pricing")
    func sonnetPricing() {
        let pricing = ModelPricing.forModel("claude-sonnet-4-20250514")
        #expect(pricing.inputPerMTok == 3.0)
        #expect(pricing.outputPerMTok == 15.0)
    }

    @Test("Haiku pricing")
    func haikuPricing() {
        let pricing = ModelPricing.forModel("claude-haiku-4-5-20251001")
        #expect(pricing.inputPerMTok == 0.80)
        #expect(pricing.outputPerMTok == 4.0)
    }

    @Test("Unknown model defaults to Sonnet")
    func unknownModel() {
        let pricing = ModelPricing.forModel("some-unknown-model")
        #expect(pricing.inputPerMTok == 3.0)
    }
}
