import Foundation

public enum TaskDisplayMetric {
    case quota
    case tokens
    case apiCost
}

public enum TaskDisplayOrdering {
    public static func sorted(
        _ tasks: [TaskQuotaUsage],
        by metric: TaskDisplayMetric
    ) -> [TaskQuotaUsage] {
        tasks.sorted { lhs, rhs in
            let lhsMetric = value(of: lhs, for: metric)
            let rhsMetric = value(of: rhs, for: metric)

            if lhsMetric != rhsMetric {
                return lhsMetric > rhsMetric
            }
            if lhs.lastActive != rhs.lastActive {
                return lhs.lastActive > rhs.lastActive
            }
            return lhs.id < rhs.id
        }
    }

    private static func value(
        of task: TaskQuotaUsage,
        for metric: TaskDisplayMetric
    ) -> Double {
        switch metric {
        case .quota:
            return task.usedPercent
        case .tokens:
            return Double(task.tokenCount)
        case .apiCost:
            return task.apiEquivalentCostUSD
        }
    }
}
