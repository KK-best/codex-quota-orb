import Foundation

public struct TokenUsageBreakdown: Equatable, Sendable {
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let cacheWriteInputTokens: Int64
    public let outputTokens: Int64

    public init(
        inputTokens: Int64,
        cachedInputTokens: Int64,
        cacheWriteInputTokens: Int64,
        outputTokens: Int64
    ) {
        self.inputTokens = max(0, inputTokens)
        self.cachedInputTokens = max(0, cachedInputTokens)
        self.cacheWriteInputTokens = max(0, cacheWriteInputTokens)
        self.outputTokens = max(0, outputTokens)
    }

    public static let zero = TokenUsageBreakdown(
        inputTokens: 0,
        cachedInputTokens: 0,
        cacheWriteInputTokens: 0,
        outputTokens: 0
    )

    public static func - (
        lhs: TokenUsageBreakdown,
        rhs: TokenUsageBreakdown
    ) -> TokenUsageBreakdown {
        TokenUsageBreakdown(
            inputTokens: max(0, lhs.inputTokens - rhs.inputTokens),
            cachedInputTokens: max(
                0,
                lhs.cachedInputTokens - rhs.cachedInputTokens
            ),
            cacheWriteInputTokens: max(
                0,
                lhs.cacheWriteInputTokens - rhs.cacheWriteInputTokens
            ),
            outputTokens: max(0, lhs.outputTokens - rhs.outputTokens)
        )
    }
}

public enum APICostEstimator {
    private struct RateCard {
        let input: Double
        let cachedInput: Double
        let cacheWrite: Double?
        let output: Double
    }

    public static func usesLongContextPricing(
        inputTokens: Int64
    ) -> Bool {
        inputTokens > 272_000
    }

    public static func estimateUSD(
        usage: TokenUsageBreakdown,
        model: String,
        usesLongContextPricing: Bool
    ) -> Double? {
        guard let rates = rateCard(
            model: model,
            longContext: usesLongContextPricing
        ) else {
            return nil
        }

        let cached = min(usage.cachedInputTokens, usage.inputTokens)
        let cacheWrites = min(
            usage.cacheWriteInputTokens,
            max(0, usage.inputTokens - cached)
        )
        let uncached = max(0, usage.inputTokens - cached - cacheWrites)
        let writeRate = rates.cacheWrite ?? rates.input

        return (
            Double(uncached) * rates.input
                + Double(cached) * rates.cachedInput
                + Double(cacheWrites) * writeRate
                + Double(usage.outputTokens) * rates.output
        ) / 1_000_000
    }

    private static func rateCard(
        model: String,
        longContext: Bool
    ) -> RateCard? {
        switch model.lowercased() {
        case "gpt-5.6-sol":
            return longContext
                ? RateCard(
                    input: 10,
                    cachedInput: 1,
                    cacheWrite: 12.5,
                    output: 45
                )
                : RateCard(
                    input: 5,
                    cachedInput: 0.5,
                    cacheWrite: 6.25,
                    output: 30
                )
        case "gpt-5.6-terra":
            return longContext
                ? RateCard(
                    input: 5,
                    cachedInput: 0.5,
                    cacheWrite: 6.25,
                    output: 22.5
                )
                : RateCard(
                    input: 2.5,
                    cachedInput: 0.25,
                    cacheWrite: 3.125,
                    output: 15
                )
        case "gpt-5.6-luna":
            return longContext
                ? RateCard(
                    input: 2,
                    cachedInput: 0.2,
                    cacheWrite: 2.5,
                    output: 9
                )
                : RateCard(
                    input: 1,
                    cachedInput: 0.1,
                    cacheWrite: 1.25,
                    output: 6
                )
        case "gpt-5.5":
            return longContext
                ? RateCard(
                    input: 10,
                    cachedInput: 1,
                    cacheWrite: nil,
                    output: 45
                )
                : RateCard(
                    input: 5,
                    cachedInput: 0.5,
                    cacheWrite: nil,
                    output: 30
                )
        case "gpt-5.4":
            return longContext
                ? RateCard(
                    input: 5,
                    cachedInput: 0.5,
                    cacheWrite: nil,
                    output: 22.5
                )
                : RateCard(
                    input: 2.5,
                    cachedInput: 0.25,
                    cacheWrite: nil,
                    output: 15
                )
        case "gpt-5.4-mini":
            return RateCard(
                input: 0.75,
                cachedInput: 0.075,
                cacheWrite: nil,
                output: 4.5
            )
        case "gpt-5.3-codex":
            return RateCard(
                input: 1.75,
                cachedInput: 0.175,
                cacheWrite: nil,
                output: 14
            )
        case "gpt-5.2-codex":
            return RateCard(
                input: 1.75,
                cachedInput: 0.175,
                cacheWrite: nil,
                output: 14
            )
        case "gpt-5.1-codex-max", "gpt-5.1-codex", "gpt-5-codex":
            return RateCard(
                input: 1.25,
                cachedInput: 0.125,
                cacheWrite: nil,
                output: 10
            )
        case "gpt-5.1-codex-mini":
            return RateCard(
                input: 0.25,
                cachedInput: 0.025,
                cacheWrite: nil,
                output: 2
            )
        case "codex-mini-latest":
            return RateCard(
                input: 1.5,
                cachedInput: 0.375,
                cacheWrite: nil,
                output: 6
            )
        default:
            return nil
        }
    }
}
