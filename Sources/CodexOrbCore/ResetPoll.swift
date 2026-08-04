import Foundation

public struct ResetProbabilitySnapshot: Equatable, Sendable {
    public let model24h: Double?
    public let model48h: Double?
    public let community24h: Double?
    public let communityVoteCount: Int
    public let communityUnlocked: Bool
    public let fetchedAt: Date

    public init(
        model24h: Double?,
        model48h: Double?,
        community24h: Double?,
        communityVoteCount: Int,
        communityUnlocked: Bool,
        fetchedAt: Date
    ) {
        self.model24h = Self.clamp(model24h)
        self.model48h = Self.clamp(model48h)
        self.community24h = Self.clamp(community24h)
        self.communityVoteCount = max(0, communityVoteCount)
        self.communityUnlocked = communityUnlocked
        self.fetchedAt = fetchedAt
    }

    public var preferred24h: Double? {
        model24h ?? community24h
    }

    public var preferredSourceLabel: String {
        if model24h != nil {
            return "模型预测"
        }
        if community24h != nil {
            return "社区投票"
        }
        return "暂无预测"
    }

    private static func clamp(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 100)
    }
}

public enum ResetPollParser {
    public enum ParseError: LocalizedError {
        case invalidResponse

        public var errorDescription: String? {
            "重置预测接口返回了无法识别的数据。"
        }
    }

    public static func parse(
        _ data: Data,
        fetchedAt: Date = Date()
    ) throws -> ResetProbabilitySnapshot {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ParseError.invalidResponse
        }

        let community24h = response.tally?.buckets.first {
            $0.id == "within_24h"
        }?.share

        guard response.model?.rounded24h != nil
            || community24h != nil
            || response.tally != nil
        else {
            throw ParseError.invalidResponse
        }

        return ResetProbabilitySnapshot(
            model24h: response.model?.rounded24h,
            model48h: response.model?.rounded48h,
            community24h: community24h,
            communityVoteCount: response.tally?.totalVotes ?? 0,
            communityUnlocked: response.tally?.unlocked ?? false,
            fetchedAt: fetchedAt
        )
    }
}

private struct Response: Decodable {
    let tally: Tally?
    let model: Model?

    struct Tally: Decodable {
        let totalVotes: Int
        let unlocked: Bool
        let buckets: [Bucket]

        enum CodingKeys: String, CodingKey {
            case totalVotes = "total_votes"
            case unlocked
            case buckets
        }
    }

    struct Bucket: Decodable {
        let id: String
        let share: Double?
    }

    struct Model: Decodable {
        let rounded24h: Double?
        let rounded48h: Double?

        enum CodingKeys: String, CodingKey {
            case rounded24h = "rounded_24h"
            case rounded48h = "rounded_48h"
        }
    }
}
