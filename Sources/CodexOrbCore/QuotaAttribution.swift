import Foundation

public struct QuotaUsageEvent: Equatable, Sendable {
    public let timestamp: Date
    public let conversationID: String
    public let usedPercent: Double
    public let tokenWeight: Int64

    public init(
        timestamp: Date,
        conversationID: String,
        usedPercent: Double,
        tokenWeight: Int64
    ) {
        self.timestamp = timestamp
        self.conversationID = conversationID
        self.usedPercent = max(0, usedPercent)
        self.tokenWeight = max(0, tokenWeight)
    }
}

public struct ConversationMetadata: Equatable, Sendable {
    public let id: String
    public let title: String
    public let projectPath: String
    public let apiEquivalentCostUSD: Double?
    public let modelLabel: String
    public let tokenCount: Int64?

    public init(
        id: String,
        title: String,
        projectPath: String,
        apiEquivalentCostUSD: Double? = nil,
        modelLabel: String = "",
        tokenCount: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.projectPath = projectPath
        self.apiEquivalentCostUSD = apiEquivalentCostUSD
        self.modelLabel = modelLabel
        self.tokenCount = tokenCount
    }
}

public struct ConversationQuotaUsage: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let projectPath: String
    public let usedPercent: Double
    public let tokenWeight: Int64
    public let lastActive: Date
    public let apiEquivalentCostUSD: Double?
    public let modelLabel: String

    public init(
        id: String,
        title: String,
        projectPath: String,
        usedPercent: Double,
        tokenWeight: Int64,
        lastActive: Date,
        apiEquivalentCostUSD: Double? = nil,
        modelLabel: String = ""
    ) {
        self.id = id
        self.title = title
        self.projectPath = projectPath
        self.usedPercent = max(0, usedPercent)
        self.tokenWeight = max(0, tokenWeight)
        self.lastActive = lastActive
        self.apiEquivalentCostUSD = apiEquivalentCostUSD
        self.modelLabel = modelLabel
    }
}

public struct QuotaAttributionResult: Equatable, Sendable {
    public let conversations: [ConversationQuotaUsage]
    public let attributedPercent: Double
    public let unassignedPercent: Double

    public init(
        conversations: [ConversationQuotaUsage],
        attributedPercent: Double,
        unassignedPercent: Double
    ) {
        self.conversations = conversations
        self.attributedPercent = max(0, attributedPercent)
        self.unassignedPercent = max(0, unassignedPercent)
    }
}

public enum QuotaAttribution {
    private struct MutableUsage {
        var usedPercent: Double = 0
        var tokenWeight: Int64 = 0
        var lastActive = Date.distantPast
    }

    public static func attribute(
        events: [QuotaUsageEvent],
        currentUsedPercent: Double,
        metadata: [String: ConversationMetadata]
    ) -> QuotaAttributionResult {
        let currentPercent = min(max(0, currentUsedPercent), 100)
        guard currentPercent > 0, !events.isEmpty else {
            return QuotaAttributionResult(
                conversations: [],
                attributedPercent: 0,
                unassignedPercent: currentPercent
            )
        }

        let sorted = events.enumerated().sorted {
            if $0.element.timestamp == $1.element.timestamp {
                return $0.offset < $1.offset
            }
            return $0.element.timestamp < $1.element.timestamp
        }.map(\.element)

        var usages: [String: MutableUsage] = [:]
        var pending: [QuotaUsageEvent] = []
        var previousPercent = 0.0
        var attributed = 0.0

        for event in sorted {
            pending.append(event)
            guard event.usedPercent > previousPercent else { continue }

            let remaining = max(0, currentPercent - attributed)
            let delta = min(event.usedPercent - previousPercent, remaining)
            if delta > 0 {
                let totalWeight = pending.reduce(0.0) {
                    $0 + Double(max(1, $1.tokenWeight))
                }

                for candidate in pending {
                    let share = delta
                        * Double(max(1, candidate.tokenWeight))
                        / totalWeight
                    var usage = usages[candidate.conversationID] ?? MutableUsage()
                    usage.usedPercent += share
                    usage.tokenWeight += candidate.tokenWeight
                    usage.lastActive = max(
                        usage.lastActive,
                        candidate.timestamp
                    )
                    usages[candidate.conversationID] = usage
                }
                attributed += delta
            }

            pending.removeAll(keepingCapacity: true)
            previousPercent = max(previousPercent, event.usedPercent)
            if attributed >= currentPercent { break }
        }

        let conversations = usages.map { id, usage in
            let details = metadata[id]
            return ConversationQuotaUsage(
                id: id,
                title: normalizedTitle(details?.title),
                projectPath: details?.projectPath ?? "",
                usedPercent: usage.usedPercent,
                tokenWeight: details?.tokenCount ?? usage.tokenWeight,
                lastActive: usage.lastActive,
                apiEquivalentCostUSD: details?.apiEquivalentCostUSD,
                modelLabel: details?.modelLabel ?? ""
            )
        }.sorted {
            if $0.usedPercent == $1.usedPercent {
                return $0.lastActive > $1.lastActive
            }
            return $0.usedPercent > $1.usedPercent
        }

        return QuotaAttributionResult(
            conversations: conversations,
            attributedPercent: attributed,
            unassignedPercent: max(0, currentPercent - attributed)
        )
    }

    private static func normalizedTitle(_ value: String?) -> String {
        let title = value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "未命名对话" : title
    }
}
