import Foundation

public enum ThreadRelation: Equatable, Sendable {
    case main
    case automation
    case child(parentID: String)
    case guardian(referencedRootIDs: Set<String>)
    case background
}

public struct ThreadTaskUsage: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let projectPath: String
    public let relation: ThreadRelation
    public let tokenCount: Int64
    public let apiEquivalentCostUSD: Double?
    public let modelLabel: String
    public let lastActive: Date
    public let isActiveInCycle: Bool

    public init(
        id: String,
        title: String,
        projectPath: String,
        relation: ThreadRelation,
        tokenCount: Int64,
        apiEquivalentCostUSD: Double?,
        modelLabel: String,
        lastActive: Date,
        isActiveInCycle: Bool = true
    ) {
        self.id = id
        self.title = title
        self.projectPath = projectPath
        self.relation = relation
        self.tokenCount = max(0, tokenCount)
        self.apiEquivalentCostUSD = apiEquivalentCostUSD
        self.modelLabel = modelLabel
        self.lastActive = lastActive
        self.isActiveInCycle = isActiveInCycle
    }
}

public struct TaskQuotaUsage: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let projectPath: String
    public let usedPercent: Double
    public let displayUsedTenths: Int
    public let tokenCount: Int64
    public let apiEquivalentCostUSD: Double
    public let modelLabel: String
    public let subtaskCount: Int
    public let lastActive: Date
    public let containsEstimatedPricing: Bool

    public init(
        id: String,
        title: String,
        projectPath: String,
        usedPercent: Double,
        displayUsedTenths: Int? = nil,
        tokenCount: Int64,
        apiEquivalentCostUSD: Double,
        modelLabel: String,
        subtaskCount: Int,
        lastActive: Date,
        containsEstimatedPricing: Bool
    ) {
        self.id = id
        self.title = title
        self.projectPath = projectPath
        self.usedPercent = max(0, usedPercent)
        self.displayUsedTenths = max(0, displayUsedTenths ?? Int((max(0, usedPercent) * 10).rounded()))
        self.tokenCount = max(0, tokenCount)
        self.apiEquivalentCostUSD = max(0, apiEquivalentCostUSD)
        self.modelLabel = modelLabel
        self.subtaskCount = max(0, subtaskCount)
        self.lastActive = lastActive
        self.containsEstimatedPricing = containsEstimatedPricing
    }
}

public struct TaskAggregationResult: Equatable, Sendable {
    public let tasks: [TaskQuotaUsage]
    public let automationTasks: [TaskQuotaUsage]
    public let officialUsedPercent: Double
    public let officialDisplayTenths: Int
    public let backgroundUsedPercent: Double
    public let backgroundDisplayTenths: Int
    public let hasUnreconstructedQuota: Bool
    public let backgroundTokenCount: Int64
    public let backgroundAPICostUSD: Double
    public let backgroundThreadCount: Int

    public init(
        tasks: [TaskQuotaUsage],
        automationTasks: [TaskQuotaUsage],
        officialUsedPercent: Double,
        officialDisplayTenths: Int,
        backgroundUsedPercent: Double,
        backgroundDisplayTenths: Int,
        hasUnreconstructedQuota: Bool,
        backgroundTokenCount: Int64,
        backgroundAPICostUSD: Double,
        backgroundThreadCount: Int
    ) {
        self.tasks = tasks
        self.automationTasks = automationTasks
        self.officialUsedPercent = max(0, officialUsedPercent)
        self.officialDisplayTenths = max(0, officialDisplayTenths)
        self.backgroundUsedPercent = max(0, backgroundUsedPercent)
        self.backgroundDisplayTenths = max(0, backgroundDisplayTenths)
        self.hasUnreconstructedQuota = hasUnreconstructedQuota
        self.backgroundTokenCount = max(0, backgroundTokenCount)
        self.backgroundAPICostUSD = max(0, backgroundAPICostUSD)
        self.backgroundThreadCount = max(0, backgroundThreadCount)
    }
}

public enum TaskUsageAggregator {
    private static let fallbackDollarsPerToken = 1.0 / 1_000_000
    private static let displayRemainderScale = 1_000_000_000_000.0

    private enum RootKind {
        case user
        case automation
    }

    private struct RootUsageData {
        let root: ThreadTaskUsage
        let kind: RootKind
        let tokenCount: Int64
        let apiEquivalentCostUSD: Double
        let subtaskCount: Int
        let lastActive: Date
        let containsEstimatedPricing: Bool
    }

    private enum DisplayKey: Hashable {
        case root(String)
        case background
    }

    private struct DisplayEntry {
        let key: DisplayKey
        let floorTenths: Int
        let remainderSortKey: Int64
    }

    private struct DisplayAllocation {
        let officialTenths: Int
        let rootTenths: [String: Int]
        let backgroundTenths: Int
    }

    public static func aggregate(
        records: [ThreadTaskUsage],
        currentUsedPercent: Double
    ) -> TaskAggregationResult {
        let officialUsedPercent = min(max(0, currentUsedPercent), 100)
        let uniqueRecords = deduplicated(records)
        let recordsByID = Dictionary(uniqueKeysWithValues: uniqueRecords.map { ($0.id, $0) })

        var rootKinds: [String: RootKind] = [:]
        for record in uniqueRecords {
            switch record.relation {
            case .main:
                rootKinds[record.id] = .user
            case .automation:
                rootKinds[record.id] = .automation
            case .child, .guardian, .background:
                break
            }
        }

        let activeRecords = uniqueRecords.filter(\.isActiveInCycle)
        let knownCostRecords = activeRecords.compactMap { record -> (cost: Double, tokens: Int64)? in
            guard let cost = record.apiEquivalentCostUSD else { return nil }
            return (max(0, cost), record.tokenCount)
        }
        let knownCost = knownCostRecords.reduce(0.0) { $0 + $1.cost }
        let knownTokens = knownCostRecords.reduce(Int64(0)) { $0 + $1.tokens }
        let globalDollarsPerToken = knownTokens > 0
            ? knownCost / Double(knownTokens)
            : fallbackDollarsPerToken
        let costForRecord: (ThreadTaskUsage) -> Double = { record in
            if let cost = record.apiEquivalentCostUSD {
                return max(0, cost)
            }
            return Double(record.tokenCount) * globalDollarsPerToken
        }

        var recordsByRootID: [String: [ThreadTaskUsage]] = [:]
        var backgroundRecords: [ThreadTaskUsage] = []
        for record in activeRecords {
            if let rootID = resolvedRootID(
                for: record,
                recordsByID: recordsByID,
                rootIDs: Set(rootKinds.keys),
                visited: []
            ) {
                recordsByRootID[rootID, default: []].append(record)
            } else {
                backgroundRecords.append(record)
            }
        }

        let allRootData = uniqueRecords.compactMap { root -> RootUsageData? in
            guard let kind = rootKinds[root.id] else { return nil }
            let members = recordsByRootID[root.id] ?? []
            let tokenCount = members.reduce(Int64(0)) { $0 + $1.tokenCount }
            let apiEquivalentCostUSD = members.reduce(0.0) { $0 + costForRecord($1) }
            let lastActive = members.map(\.lastActive).max() ?? root.lastActive
            return RootUsageData(
                root: root,
                kind: kind,
                tokenCount: tokenCount,
                apiEquivalentCostUSD: apiEquivalentCostUSD,
                subtaskCount: members.filter { $0.id != root.id }.count,
                lastActive: lastActive,
                containsEstimatedPricing: members.contains { $0.apiEquivalentCostUSD == nil }
            )
        }

        let userRootData = allRootData.filter { data in
            data.kind == .user && !(recordsByRootID[data.root.id] ?? []).isEmpty
        }
        let automationRootData = allRootData.filter { data in
            data.kind == .automation
                && (data.tokenCount > 0 || data.apiEquivalentCostUSD > 0)
        }
        let visibleRootData = userRootData + automationRootData

        let backgroundTokenCount = backgroundRecords.reduce(Int64(0)) { $0 + $1.tokenCount }
        let backgroundAPICostUSD = backgroundRecords.reduce(0.0) { $0 + costForRecord($1) }
        let totalAPICost = visibleRootData.reduce(backgroundAPICostUSD) {
            $0 + $1.apiEquivalentCostUSD
        }
        let totalTokens = visibleRootData.reduce(backgroundTokenCount) {
            $0 + $1.tokenCount
        }

        let usedPercentByRootID: [String: Double]
        let backgroundUsedPercent: Double
        let hasUnreconstructedQuota: Bool
        if totalAPICost > 0 {
            usedPercentByRootID = Dictionary(uniqueKeysWithValues: visibleRootData.map { data in
                (data.root.id, officialUsedPercent * data.apiEquivalentCostUSD / totalAPICost)
            })
            backgroundUsedPercent = officialUsedPercent * backgroundAPICostUSD / totalAPICost
            hasUnreconstructedQuota = false
        } else if totalTokens > 0 {
            usedPercentByRootID = Dictionary(uniqueKeysWithValues: visibleRootData.map { data in
                (data.root.id, officialUsedPercent * Double(data.tokenCount) / Double(totalTokens))
            })
            backgroundUsedPercent = officialUsedPercent * Double(backgroundTokenCount) / Double(totalTokens)
            hasUnreconstructedQuota = false
        } else {
            usedPercentByRootID = Dictionary(uniqueKeysWithValues: visibleRootData.map { ($0.root.id, 0) })
            backgroundUsedPercent = officialUsedPercent
            hasUnreconstructedQuota = officialUsedPercent > 0
        }

        let displayAllocation = allocateDisplayTenths(
            rootShares: visibleRootData.map { data in
                (id: data.root.id, usedPercent: usedPercentByRootID[data.root.id] ?? 0)
            },
            backgroundUsedPercent: backgroundUsedPercent,
            officialUsedPercent: officialUsedPercent
        )

        let makeTask: (RootUsageData) -> TaskQuotaUsage = { data in
            TaskQuotaUsage(
                id: data.root.id,
                title: data.root.title,
                projectPath: data.root.projectPath,
                usedPercent: usedPercentByRootID[data.root.id] ?? 0,
                displayUsedTenths: displayAllocation.rootTenths[data.root.id] ?? 0,
                tokenCount: data.tokenCount,
                apiEquivalentCostUSD: data.apiEquivalentCostUSD,
                modelLabel: data.root.modelLabel,
                subtaskCount: data.subtaskCount,
                lastActive: data.lastActive,
                containsEstimatedPricing: data.containsEstimatedPricing
            )
        }
        let sortTasks: (TaskQuotaUsage, TaskQuotaUsage) -> Bool = { lhs, rhs in
            if lhs.lastActive == rhs.lastActive {
                return lhs.id < rhs.id
            }
            return lhs.lastActive > rhs.lastActive
        }
        let tasks = userRootData.map(makeTask).sorted(by: sortTasks)
        let automationTasks = automationRootData.map(makeTask).sorted(by: sortTasks)

        return TaskAggregationResult(
            tasks: tasks,
            automationTasks: automationTasks,
            officialUsedPercent: officialUsedPercent,
            officialDisplayTenths: displayAllocation.officialTenths,
            backgroundUsedPercent: backgroundUsedPercent,
            backgroundDisplayTenths: displayAllocation.backgroundTenths,
            hasUnreconstructedQuota: hasUnreconstructedQuota,
            backgroundTokenCount: backgroundTokenCount,
            backgroundAPICostUSD: backgroundAPICostUSD,
            backgroundThreadCount: backgroundRecords.count
        )
    }

    private static func deduplicated(_ records: [ThreadTaskUsage]) -> [ThreadTaskUsage] {
        var recordsByID: [String: [ThreadTaskUsage]] = [:]
        for record in records {
            recordsByID[record.id, default: []].append(record)
        }

        return recordsByID.keys.sorted().compactMap { id in
            guard let candidates = recordsByID[id], !candidates.isEmpty else { return nil }
            let chosen = candidates.sorted(by: isPreferredDuplicate).first!
            let relationSignatures = Set(candidates.map { canonicalRelationSignature($0.relation) })
            guard relationSignatures.count > 1 else { return chosen }

            return ThreadTaskUsage(
                id: chosen.id,
                title: chosen.title,
                projectPath: chosen.projectPath,
                relation: .background,
                tokenCount: chosen.tokenCount,
                apiEquivalentCostUSD: chosen.apiEquivalentCostUSD,
                modelLabel: chosen.modelLabel,
                lastActive: chosen.lastActive,
                isActiveInCycle: chosen.isActiveInCycle
            )
        }
    }

    private static func isPreferredDuplicate(
        _ lhs: ThreadTaskUsage,
        _ rhs: ThreadTaskUsage
    ) -> Bool {
        if lhs.isActiveInCycle != rhs.isActiveInCycle {
            return lhs.isActiveInCycle
        }
        if lhs.lastActive != rhs.lastActive {
            return lhs.lastActive > rhs.lastActive
        }
        return canonicalSignature(lhs) < canonicalSignature(rhs)
    }

    private static func canonicalSignature(_ record: ThreadTaskUsage) -> String {
        let costSignature = record.apiEquivalentCostUSD.map { String($0.bitPattern) } ?? "nil"
        return [
            record.title,
            record.projectPath,
            canonicalRelationSignature(record.relation),
            String(record.tokenCount),
            costSignature,
            record.modelLabel,
            String(record.isActiveInCycle),
            String(record.lastActive.timeIntervalSinceReferenceDate.bitPattern)
        ]
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
    }

    private static func canonicalRelationSignature(_ relation: ThreadRelation) -> String {
        switch relation {
        case .main:
            return "main"
        case .automation:
            return "automation"
        case let .child(parentID):
            return "child:\(parentID.utf8.count):\(parentID)"
        case let .guardian(referencedRootIDs):
            return "guardian:" + referencedRootIDs.sorted().map { "\($0.utf8.count):\($0)" }.joined(separator: ",")
        case .background:
            return "background"
        }
    }

    private static func resolvedRootID(
        for record: ThreadTaskUsage,
        recordsByID: [String: ThreadTaskUsage],
        rootIDs: Set<String>,
        visited: Set<String>
    ) -> String? {
        guard !visited.contains(record.id) else { return nil }

        var visited = visited
        visited.insert(record.id)

        switch record.relation {
        case .main, .automation:
            return rootIDs.contains(record.id) ? record.id : nil
        case let .child(parentID):
            guard let parent = recordsByID[parentID] else { return nil }
            return resolvedRootID(
                for: parent,
                recordsByID: recordsByID,
                rootIDs: rootIDs,
                visited: visited
            )
        case let .guardian(referencedRootIDs):
            let confirmedRootIDs = referencedRootIDs.intersection(rootIDs)
            return confirmedRootIDs.count == 1 ? confirmedRootIDs.first : nil
        case .background:
            return nil
        }
    }

    private static func allocateDisplayTenths(
        rootShares: [(id: String, usedPercent: Double)],
        backgroundUsedPercent: Double,
        officialUsedPercent: Double
    ) -> DisplayAllocation {
        let officialTenths = max(0, Int((max(0, officialUsedPercent) * 10).rounded()))
        let rawEntries = rootShares.map { share in
            (key: DisplayKey.root(share.id), rawTenths: max(0, share.usedPercent) * 10)
        } + [(key: DisplayKey.background, rawTenths: max(0, backgroundUsedPercent) * 10)]
        let entries = rawEntries.map { entry -> DisplayEntry in
            let floorTenths = Int(floor(entry.rawTenths))
            let remainder = entry.rawTenths - Double(floorTenths)
            return DisplayEntry(
                key: entry.key,
                floorTenths: floorTenths,
                remainderSortKey: Int64((remainder * displayRemainderScale).rounded())
            )
        }

        var assigned = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.floorTenths) })
        let floorTotal = entries.reduce(0) { $0 + $1.floorTenths }
        let unitsToDistribute = max(0, officialTenths - floorTotal)
        let rankedEntries = entries.sorted { lhs, rhs in
            if lhs.remainderSortKey != rhs.remainderSortKey {
                return lhs.remainderSortKey > rhs.remainderSortKey
            }
            switch (lhs.key, rhs.key) {
            case let (.root(lhsID), .root(rhsID)):
                return lhsID < rhsID
            case (.root, .background):
                return true
            case (.background, .root):
                return false
            case (.background, .background):
                return false
            }
        }
        if !rankedEntries.isEmpty {
            for offset in 0..<unitsToDistribute {
                let key = rankedEntries[offset % rankedEntries.count].key
                assigned[key, default: 0] += 1
            }
        }

        var rootTenths: [String: Int] = [:]
        for share in rootShares {
            rootTenths[share.id] = assigned[.root(share.id)] ?? 0
        }
        return DisplayAllocation(
            officialTenths: officialTenths,
            rootTenths: rootTenths,
            backgroundTenths: assigned[.background] ?? 0
        )
    }
}
