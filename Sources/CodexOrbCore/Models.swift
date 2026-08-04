import Foundation

public enum QuotaSeverity: String, Equatable, Sendable {
    case normal
    case warning
    case critical

    public init(remainingPercent: Double) {
        if remainingPercent < 15 {
            self = .critical
        } else if remainingPercent < 30 {
            self = .warning
        } else {
            self = .normal
        }
    }
}

public struct QuotaSnapshot: Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMinutes: Int
    public let resetsAt: Date

    public init(usedPercent: Double, windowDurationMinutes: Int, resetsAt: Date) {
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }

    public var severity: QuotaSeverity {
        QuotaSeverity(remainingPercent: remainingPercent)
    }
}

public struct DailyUsage: Equatable, Sendable {
    public let date: String
    public let tokens: Int64

    public init(date: String, tokens: Int64) {
        self.date = date
        self.tokens = tokens
    }
}

public struct AccountSnapshot: Equatable, Sendable {
    public let quota: QuotaSnapshot
    public let planType: String
    public let resetCredits: Int
    public let lifetimeTokens: Int64
    public let peakDailyTokens: Int64
    public let dailyUsage: [DailyUsage]

    public init(
        quota: QuotaSnapshot,
        planType: String,
        resetCredits: Int,
        lifetimeTokens: Int64,
        peakDailyTokens: Int64,
        dailyUsage: [DailyUsage]
    ) {
        self.quota = quota
        self.planType = planType
        self.resetCredits = resetCredits
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.dailyUsage = dailyUsage
    }
}

public struct ProjectUsage: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let totalTokens: Int64
    public let sessionCount: Int
    public let lastUpdated: Date

    public init(
        path: String,
        name: String? = nil,
        totalTokens: Int64,
        sessionCount: Int,
        lastUpdated: Date
    ) {
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.totalTokens = totalTokens
        self.sessionCount = sessionCount
        self.lastUpdated = lastUpdated
    }

    public func tokensSince(_ baseline: [String: Int64]) -> Int64 {
        max(0, totalTokens - (baseline[path] ?? totalTokens))
    }
}
