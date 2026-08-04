import Foundation

public enum AccountResponseParser {
    public enum ParseError: LocalizedError {
        case missingPrimaryLimit

        public var errorDescription: String? {
            switch self {
            case .missingPrimaryLimit:
                return "Codex 没有返回可用的主额度窗口。"
            }
        }
    }

    public static func parse(
        rateLimitLine: Data,
        usageLine: Data
    ) throws -> AccountSnapshot {
        let decoder = JSONDecoder()
        let rateResponse = try decoder.decode(RateLimitResponse.self, from: rateLimitLine)
        let usageResponse = try decoder.decode(UsageResponse.self, from: usageLine)

        guard let primary = rateResponse.result.rateLimits.primary else {
            throw ParseError.missingPrimaryLimit
        }

        let quota = QuotaSnapshot(
            usedPercent: primary.usedPercent,
            windowDurationMinutes: primary.windowDurationMins,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(primary.resetsAt))
        )

        return AccountSnapshot(
            quota: quota,
            planType: rateResponse.result.rateLimits.planType ?? "unknown",
            resetCredits: rateResponse.result.rateLimitResetCredits?.availableCount ?? 0,
            lifetimeTokens: usageResponse.result.summary.lifetimeTokens,
            peakDailyTokens: usageResponse.result.summary.peakDailyTokens,
            dailyUsage: usageResponse.result.dailyUsageBuckets.map {
                DailyUsage(date: $0.startDate, tokens: $0.tokens)
            }
        )
    }
}

public enum ProjectUsageParser {
    public static func parse(_ data: Data) throws -> [ProjectUsage] {
        let rows = try JSONDecoder().decode([ProjectRow].self, from: data)
        return rows.map {
            ProjectUsage(
                path: $0.cwd,
                totalTokens: $0.totalTokens,
                sessionCount: $0.sessionCount,
                lastUpdated: Date(timeIntervalSince1970: TimeInterval($0.lastUpdatedMilliseconds) / 1_000)
            )
        }
    }
}

public enum ThreadSourceParser {
    public static func relation(
        from source: String?,
        threadSource: String?
    ) -> ThreadRelation {
        let sourceRelationship = sourceRelationship(from: source)
        guard let threadSource = normalizedThreadSource(threadSource) else {
            return legacyRelation(
                source: source,
                sourceRelationship: sourceRelationship
            )
        }

        switch threadSource {
        case "user":
            return sourceRelationship == .plain ? .main : .background
        case "automation":
            return sourceRelationship == .plain ? .automation : .background
        case "subagent":
            switch sourceRelationship {
            case let .child(parentID):
                return .child(parentID: parentID)
            case .guardian:
                return .guardian(referencedRootIDs: [])
            case .plain, .invalidInternalSubagent:
                return .background
            }
        default:
            return .background
        }
    }

    public static func relation(from source: String?) -> ThreadRelation {
        relation(from: source, threadSource: nil)
    }

    private enum SourceRelationship: Equatable {
        case plain
        case child(parentID: String)
        case guardian
        case invalidInternalSubagent
    }

    private static func normalizedThreadSource(_ threadSource: String?) -> String? {
        guard let threadSource else { return nil }
        let normalized = threadSource
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func sourceRelationship(from source: String?) -> SourceRelationship {
        guard let source else { return .plain }
        guard let data = source.data(using: .utf8) else {
            return source.contains("subagent") ? .invalidInternalSubagent : .plain
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return source.contains("subagent") ? .invalidInternalSubagent : .plain
        }
        guard let payload = object as? [String: Any], payload.keys.contains("subagent") else {
            return .plain
        }
        guard let subagent = payload["subagent"] as? [String: Any] else {
            return .invalidInternalSubagent
        }
        if subagent.keys.contains("thread_spawn"),
           subagent.keys.contains("other") {
            return .invalidInternalSubagent
        }
        if let spawn = subagent["thread_spawn"] as? [String: Any],
           let rawParentID = spawn["parent_thread_id"] as? String {
            let parentID = rawParentID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return parentID.isEmpty
                ? .invalidInternalSubagent
                : .child(parentID: parentID)
        }
        if subagent["other"] as? String == "guardian" {
            return .guardian
        }
        return .invalidInternalSubagent
    }

    private static func legacyRelation(
        source: String?,
        sourceRelationship: SourceRelationship
    ) -> ThreadRelation {
        switch sourceRelationship {
        case let .child(parentID):
            return .child(parentID: parentID)
        case .guardian:
            return .guardian(referencedRootIDs: [])
        case .invalidInternalSubagent:
            return .background
        case .plain:
            switch source {
            case "vscode", "cli", "exec", "mcp":
                return .main
            default:
                return .background
            }
        }
    }
}

public enum RolloutEventParser {
    public static func model(from data: Data) -> String? {
        guard let event = try? JSONDecoder().decode(
            TurnContextEvent.self,
            from: data
        ),
        event.type == "turn_context",
        !event.payload.model.isEmpty
        else {
            return nil
        }
        return event.payload.model
    }

    public static func referencedIDs(
        in data: Data,
        candidates: Set<String>
    ) -> Set<String> {
        Set(candidates.filter { candidate in
            !candidate.isEmpty
                && data.range(of: Data(candidate.utf8)) != nil
        })
    }
}

public struct RolloutReferenceScanner {
    private let candidates: Set<String>
    public private(set) var referencedIDs: Set<String> = []

    public init(candidates: Set<String>) {
        self.candidates = candidates
    }

    public mutating func consume(_ data: Data) {
        referencedIDs.formUnion(
            RolloutEventParser.referencedIDs(
                in: data,
                candidates: candidates
            )
        )
    }
}

private struct RateLimitResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let rateLimits: Limits
        let rateLimitResetCredits: ResetCredits?
    }

    struct Limits: Decodable {
        let primary: Window?
        let planType: String?
    }

    struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int
        let resetsAt: Int64
    }

    struct ResetCredits: Decodable {
        let availableCount: Int
    }
}

private struct UsageResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let summary: Summary
        let dailyUsageBuckets: [Bucket]
    }

    struct Summary: Decodable {
        let lifetimeTokens: Int64
        let peakDailyTokens: Int64
    }

    struct Bucket: Decodable {
        let startDate: String
        let tokens: Int64
    }
}

private struct ProjectRow: Decodable {
    let cwd: String
    let totalTokens: Int64
    let sessionCount: Int
    let lastUpdatedMilliseconds: Int64

    enum CodingKeys: String, CodingKey {
        case cwd
        case totalTokens = "total_tokens"
        case sessionCount = "session_count"
        case lastUpdatedMilliseconds = "last_updated_ms"
    }
}

private struct TurnContextEvent: Decodable {
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let model: String
    }
}
