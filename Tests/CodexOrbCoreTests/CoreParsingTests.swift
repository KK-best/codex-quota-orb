import XCTest
@testable import CodexOrbCore

final class CoreParsingTests: XCTestCase {
    func testReverseJSONLReaderPreservesLongCrossChunkLineWithoutQuadraticCopies() throws {
        let longLine = Data(repeating: 0x78, count: 1_048_576)
        let expected = [
            Data("first".utf8),
            Data("middle".utf8),
            longLine,
            Data("last-without-newline".utf8)
        ]
        let url = try makeTemporaryJSONLFile(lines: expected, trailingNewline: false)
        defer { try? FileManager.default.removeItem(at: url) }

        var received: [Data] = []
        let metrics = try ReverseJSONLLineReader.readLines(
            at: url,
            chunkSize: 4 * 1_024
        ) { line in
            received.append(line)
            return false
        }

        XCTAssertEqual(received, expected.reversed())
        XCTAssertEqual(metrics.fileBytesRead, 1_048_576 + 5 + 6 + 20 + 3)
        XCTAssertEqual(metrics.lineAssemblyBytes, 1_048_576 + 5 + 6 + 20)
    }

    func testReverseJSONLReaderStopsBeforeReadingEarlierChunks() throws {
        let url = try makeTemporaryJSONLFile(
            lines: [Data(repeating: 0x61, count: 16_384), Data("last".utf8)],
            trailingNewline: false
        )
        defer { try? FileManager.default.removeItem(at: url) }

        var received: [Data] = []
        let metrics = try ReverseJSONLLineReader.readLines(
            at: url,
            chunkSize: 1_024
        ) { line in
            received.append(line)
            return true
        }

        XCTAssertEqual(received, [Data("last".utf8)])
        XCTAssertEqual(metrics.fileBytesRead, 1_024)
    }

    private func makeTemporaryJSONLFile(
        lines: [Data],
        trailingNewline: Bool
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codex-orb-reverse-jsonl-\(UUID().uuidString)"
        )
        var data = Data()
        for (index, line) in lines.enumerated() {
            data.append(line)
            if index < lines.endIndex - 1 || trailingNewline {
                data.append(0x0A)
            }
        }
        try data.write(to: url)
        return url
    }

    func testParsesOfficialRateLimitAndUsageResponses() throws {
        let rateJSON = """
        {
          "id": 7,
          "result": {
            "rateLimits": {
              "limitId": "codex",
              "primary": {
                "usedPercent": 24,
                "windowDurationMins": 10080,
                "resetsAt": 1786012680
              },
              "secondary": null,
              "credits": {"hasCredits": false, "unlimited": false, "balance": "0"},
              "planType": "pro"
            },
            "rateLimitResetCredits": {"availableCount": 2, "credits": []}
          }
        }
        """
        let usageJSON = """
        {
          "id": 9,
          "result": {
            "summary": {
              "lifetimeTokens": 19183753663,
              "peakDailyTokens": 1226659279,
              "longestRunningTurnSec": 110274,
              "currentStreakDays": 32,
              "longestStreakDays": 34
            },
            "dailyUsageBuckets": [
              {"startDate": "2026-07-29", "tokens": 967781386}
            ]
          }
        }
        """

        let account = try AccountResponseParser.parse(
            rateLimitLine: Data(rateJSON.utf8),
            usageLine: Data(usageJSON.utf8)
        )

        XCTAssertEqual(account.quota.usedPercent, 24)
        XCTAssertEqual(account.quota.remainingPercent, 76)
        XCTAssertEqual(account.quota.windowDurationMinutes, 10_080)
        XCTAssertEqual(account.planType, "pro")
        XCTAssertEqual(account.resetCredits, 2)
        XCTAssertEqual(account.lifetimeTokens, 19_183_753_663)
        XCTAssertEqual(account.dailyUsage.last?.tokens, 967_781_386)
    }

    func testQuotaSeverityUsesAppleStyleThresholds() {
        XCTAssertEqual(QuotaSeverity(remainingPercent: 65), .normal)
        XCTAssertEqual(QuotaSeverity(remainingPercent: 29), .warning)
        XCTAssertEqual(QuotaSeverity(remainingPercent: 14), .critical)
    }

    func testParsesProjectAggregationRows() throws {
        let json = """
        [
          {
            "cwd": "/tmp/codex-fixtures/机器人🤖",
            "total_tokens": 1497125,
            "session_count": 37,
            "last_updated_ms": 1785408927894
          }
        ]
        """

        let projects = try ProjectUsageParser.parse(Data(json.utf8))

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "机器人🤖")
        XCTAssertEqual(projects[0].totalTokens, 1_497_125)
        XCTAssertEqual(projects[0].sessionCount, 37)
    }

    func testParsesResetPollModelAndCommunityProbability() throws {
        let json = """
        {
          "open": true,
          "tally": {
            "total_votes": 14,
            "min_votes": 5,
            "unlocked": true,
            "buckets": [
              {"id": "within_24h", "votes": 2, "share": 14},
              {"id": "in_1_3_days", "votes": 9, "share": 64}
            ]
          },
          "model": {
            "rounded_24h": 20,
            "rounded_48h": 30,
            "confidence": "medium"
          }
        }
        """
        let fetchedAt = Date(timeIntervalSince1970: 1_786_000_000)

        let snapshot = try ResetPollParser.parse(
            Data(json.utf8),
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(snapshot.model24h, 20)
        XCTAssertEqual(snapshot.model48h, 30)
        XCTAssertEqual(snapshot.community24h, 14)
        XCTAssertEqual(snapshot.communityVoteCount, 14)
        XCTAssertTrue(snapshot.communityUnlocked)
        XCTAssertEqual(snapshot.preferred24h, 20)
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testResetPollFallsBackToCommunityProbability() throws {
        let json = """
        {
          "tally": {
            "total_votes": 6,
            "unlocked": true,
            "buckets": [
              {"id": "within_24h", "votes": 3, "share": 50}
            ]
          }
        }
        """

        let snapshot = try ResetPollParser.parse(Data(json.utf8))

        XCTAssertNil(snapshot.model24h)
        XCTAssertEqual(snapshot.community24h, 50)
        XCTAssertEqual(snapshot.preferred24h, 50)
        XCTAssertEqual(snapshot.preferredSourceLabel, "社区投票")
    }

    func testFormatsTokenCountsCompactly() {
        XCTAssertEqual(TokenFormatter.compact(980), "980")
        XCTAssertEqual(TokenFormatter.compact(1_497_125), "1.5M")
        XCTAssertEqual(TokenFormatter.compact(19_183_753_663), "19.2B")
    }

    func testFormatsQuotaWindowAndResetDistance() {
        XCTAssertEqual(TokenFormatter.windowLabel(minutes: 10_080), "7 天额度")
        XCTAssertEqual(TokenFormatter.windowLabel(minutes: 300), "5 小时额度")

        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let reset = Date(timeIntervalSince1970: 1_786_012_600)
        XCTAssertEqual(TokenFormatter.resetLabel(resetAt: reset, now: now), "3 小时 30 分后重置")
    }

    func testQuotaFooterDisplayPreservesVisibleTenthsEquality() {
        let display = QuotaFooterDisplay(
            mainTenths: 280,
            automationTenths: 0,
            backgroundTenths: 1,
            officialTenths: 281,
            hasUnreconstructedQuota: false
        )

        XCTAssertEqual(display.mainText, "28.0%")
        XCTAssertEqual(display.automationText, "0.0%")
        XCTAssertEqual(display.backgroundText, "0.1%")
        XCTAssertEqual(display.officialText, "28.1%")
        XCTAssertEqual(
            display.mainTenths
                + display.automationTenths
                + display.backgroundTenths,
            display.officialTenths
        )
    }

    func testAccountLineCollectorWaitsForBothResponses() throws {
        var collector = AccountLineCollector()

        XCTAssertEqual(
            try collector.ingest(Data(#"{"id":0,"result":{"userAgent":"Codex"}}"#.utf8)),
            .requestAccountData
        )
        XCTAssertEqual(
            try collector.ingest(Data(#"{"method":"remoteControl/status/changed","params":{}}"#.utf8)),
            .none
        )
        XCTAssertEqual(
            try collector.ingest(Data(#"{"id":7,"result":{"rateLimits":{}}}"#.utf8)),
            .none
        )

        let completion = try collector.ingest(
            Data(#"{"id":9,"result":{"summary":{},"dailyUsageBuckets":[]}}"#.utf8)
        )

        guard case let .complete(rateData, usageData) = completion else {
            return XCTFail("Expected both account responses")
        }
        XCTAssertTrue(String(decoding: rateData, as: UTF8.self).contains(#""id":7"#))
        XCTAssertTrue(String(decoding: usageData, as: UTF8.self).contains(#""id":9"#))
    }

    func testAttributesQuotaPercentAcrossConversationEventsByTokenWeight() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let events = [
            QuotaUsageEvent(
                timestamp: start,
                conversationID: "a",
                usedPercent: 0,
                tokenWeight: 100
            ),
            QuotaUsageEvent(
                timestamp: start.addingTimeInterval(1),
                conversationID: "b",
                usedPercent: 1,
                tokenWeight: 300
            ),
            QuotaUsageEvent(
                timestamp: start.addingTimeInterval(2),
                conversationID: "a",
                usedPercent: 1,
                tokenWeight: 100
            ),
            QuotaUsageEvent(
                timestamp: start.addingTimeInterval(3),
                conversationID: "a",
                usedPercent: 2,
                tokenWeight: 100
            )
        ]
        let metadata = [
            "a": ConversationMetadata(
                id: "a",
                title: "额度球",
                projectPath: "/tmp/a"
            ),
            "b": ConversationMetadata(
                id: "b",
                title: "网页项目",
                projectPath: "/tmp/b"
            )
        ]

        let result = QuotaAttribution.attribute(
            events: events,
            currentUsedPercent: 2,
            metadata: metadata
        )

        XCTAssertEqual(result.attributedPercent, 2, accuracy: 0.001)
        XCTAssertEqual(result.unassignedPercent, 0, accuracy: 0.001)
        let conversationA = try XCTUnwrap(
            result.conversations.first { $0.id == "a" }
        )
        let conversationB = try XCTUnwrap(
            result.conversations.first { $0.id == "b" }
        )
        XCTAssertEqual(conversationA.usedPercent, 1.25, accuracy: 0.001)
        XCTAssertEqual(conversationB.usedPercent, 0.75, accuracy: 0.001)
    }

    func testAggregatesChildrenAndUniqueGuardianIntoMainTasks() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let records = [
            ThreadTaskUsage(
                id: "main-a",
                title: "额度球",
                projectPath: "/a",
                relation: .main,
                tokenCount: 100,
                apiEquivalentCostUSD: 1,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "child-a",
                title: "实现",
                projectPath: "/a",
                relation: .child(parentID: "main-a"),
                tokenCount: 200,
                apiEquivalentCostUSD: 2,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "grandchild-a",
                title: "复核",
                projectPath: "/a",
                relation: .child(parentID: "child-a"),
                tokenCount: 300,
                apiEquivalentCostUSD: 3,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "guardian-a",
                title: "守护",
                projectPath: "/a",
                relation: .guardian(referencedRootIDs: ["main-a"]),
                tokenCount: 50,
                apiEquivalentCostUSD: nil,
                modelLabel: "codex-auto-review",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "main-b",
                title: "研究台",
                projectPath: "/b",
                relation: .main,
                tokenCount: 400,
                apiEquivalentCostUSD: 4,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "guardian-ambiguous",
                title: "多任务守护",
                projectPath: "/",
                relation: .guardian(
                    referencedRootIDs: ["main-a", "main-b"]
                ),
                tokenCount: 25,
                apiEquivalentCostUSD: nil,
                modelLabel: "codex-auto-review",
                lastActive: now
            )
        ]

        let result = TaskUsageAggregator.aggregate(
            records: records,
            currentUsedPercent: 20
        )

        XCTAssertEqual(result.tasks.count, 2)
        let taskA = try XCTUnwrap(result.tasks.first { $0.id == "main-a" })
        XCTAssertEqual(taskA.subtaskCount, 3)
        XCTAssertEqual(taskA.tokenCount, 650)
        XCTAssertEqual(result.backgroundThreadCount, 1)
        XCTAssertEqual(result.backgroundTokenCount, 25)
        XCTAssertEqual(
            result.tasks.reduce(0) { $0 + $1.usedPercent }
                + result.backgroundUsedPercent,
            20,
            accuracy: 0.000_001
        )
    }

    func testLeavesCircularChildParentChainInBackground() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let records = [
            ThreadTaskUsage(
                id: "main",
                title: "主任务",
                projectPath: "/main",
                relation: .main,
                tokenCount: 0,
                apiEquivalentCostUSD: 0,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "cycle-a",
                title: "循环 A",
                projectPath: "/main",
                relation: .child(parentID: "cycle-b"),
                tokenCount: 10,
                apiEquivalentCostUSD: 1,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "cycle-b",
                title: "循环 B",
                projectPath: "/main",
                relation: .child(parentID: "cycle-a"),
                tokenCount: 30,
                apiEquivalentCostUSD: 1,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            )
        ]

        let result = TaskUsageAggregator.aggregate(
            records: records,
            currentUsedPercent: 10
        )

        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.tasks[0].id, "main")
        XCTAssertEqual(result.tasks[0].tokenCount, 0)
        XCTAssertEqual(result.backgroundThreadCount, 2)
        XCTAssertEqual(result.backgroundTokenCount, 40)
        XCTAssertEqual(result.backgroundUsedPercent, 10, accuracy: 0.000_001)
    }

    func testLeavesZeroWeightMainTasksAtZeroAndAttributesOfficialUsageToBackground() {
        let now = Date(timeIntervalSince1970: 1_000)
        let records = [
            ThreadTaskUsage(
                id: "main-a",
                title: "任务 A",
                projectPath: "/a",
                relation: .main,
                tokenCount: 0,
                apiEquivalentCostUSD: 0,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "main-b",
                title: "任务 B",
                projectPath: "/b",
                relation: .main,
                tokenCount: 0,
                apiEquivalentCostUSD: 0,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            )
        ]

        let result = TaskUsageAggregator.aggregate(
            records: records,
            currentUsedPercent: 30
        )

        XCTAssertEqual(result.tasks.count, 2)
        XCTAssertEqual(result.tasks.map(\.usedPercent), [0, 0])
        XCTAssertEqual(result.backgroundUsedPercent, 30, accuracy: 0.000_001)
        XCTAssertTrue(result.hasUnreconstructedQuota)
    }

    func testKeepsDistinctMainConversationsInSameProjectPath() {
        let now = Date(timeIntervalSince1970: 1_000)
        let records = [
            ThreadTaskUsage(
                id: "thread-a",
                title: "网站基座",
                projectPath: "/same/project",
                relation: .main,
                tokenCount: 100,
                apiEquivalentCostUSD: 1,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "thread-b",
                title: "视频工作流",
                projectPath: "/same/project",
                relation: .main,
                tokenCount: 200,
                apiEquivalentCostUSD: 2,
                modelLabel: "gpt-5.6-sol",
                lastActive: now.addingTimeInterval(1)
            )
        ]

        let result = TaskUsageAggregator.aggregate(
            records: records,
            currentUsedPercent: 30
        )

        XCTAssertEqual(Set(result.tasks.map(\.id)), ["thread-a", "thread-b"])
        XCTAssertEqual(Set(result.tasks.map(\.title)), ["网站基座", "视频工作流"])
    }

    func testAttributesAllOfficialUsageToBackgroundWhenNoMainTaskHasWeight() {
        let record = ThreadTaskUsage(
            id: "orphan",
            title: "孤儿子任务",
            projectPath: "/",
            relation: .child(parentID: "missing-main"),
            tokenCount: 0,
            apiEquivalentCostUSD: 0,
            modelLabel: "gpt-5.6-sol",
            lastActive: Date(timeIntervalSince1970: 1_000)
        )

        let result = TaskUsageAggregator.aggregate(
            records: [record],
            currentUsedPercent: 25
        )

        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertEqual(result.backgroundThreadCount, 1)
        XCTAssertEqual(result.backgroundUsedPercent, 25, accuracy: 0.000_001)
    }

    func testConservesTokenAndAPICostAcrossTasksAndBackground() {
        let now = Date(timeIntervalSince1970: 1_000)
        let records = [
            ThreadTaskUsage(
                id: "main",
                title: "主任务",
                projectPath: "/main",
                relation: .main,
                tokenCount: 100,
                apiEquivalentCostUSD: 1,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "child",
                title: "子任务",
                projectPath: "/main",
                relation: .child(parentID: "main"),
                tokenCount: 200,
                apiEquivalentCostUSD: nil,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "guardian",
                title: "守护",
                projectPath: "/main",
                relation: .guardian(referencedRootIDs: ["main"]),
                tokenCount: 50,
                apiEquivalentCostUSD: 0.6,
                modelLabel: "codex-auto-review",
                lastActive: now
            ),
            ThreadTaskUsage(
                id: "orphan",
                title: "后台",
                projectPath: "/",
                relation: .child(parentID: "missing-main"),
                tokenCount: 40,
                apiEquivalentCostUSD: nil,
                modelLabel: "gpt-5.6-sol",
                lastActive: now
            )
        ]

        let result = TaskUsageAggregator.aggregate(
            records: records,
            currentUsedPercent: 20
        )
        let totalTokens = records.reduce(Int64(0)) { $0 + $1.tokenCount }
        let expectedCost = 1.6 + Double(240) * 1.6 / 150

        XCTAssertEqual(
            result.tasks.reduce(Int64(0)) { $0 + $1.tokenCount }
                + result.backgroundTokenCount,
            totalTokens
        )
        XCTAssertEqual(
            result.tasks.reduce(0) { $0 + $1.apiEquivalentCostUSD }
                + result.backgroundAPICostUSD,
            expectedCost,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            result.tasks.reduce(0) { $0 + $1.usedPercent }
                + result.backgroundUsedPercent,
            20,
            accuracy: 0.000_001
        )
    }

    func testIgnoresStaleRateLimitSnapshotDecreasesInsideOfficialCycle() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let events = [
            QuotaUsageEvent(
                timestamp: start,
                conversationID: "a",
                usedPercent: 29,
                tokenWeight: 100
            ),
            QuotaUsageEvent(
                timestamp: start.addingTimeInterval(1),
                conversationID: "b",
                usedPercent: 28,
                tokenWeight: 100
            ),
            QuotaUsageEvent(
                timestamp: start.addingTimeInterval(2),
                conversationID: "c",
                usedPercent: 30,
                tokenWeight: 100
            )
        ]

        let result = QuotaAttribution.attribute(
            events: events,
            currentUsedPercent: 30,
            metadata: [:]
        )

        XCTAssertNotNil(result.conversations.first { $0.id == "a" })
        XCTAssertNotNil(result.conversations.first { $0.id == "b" })
        XCTAssertNotNil(result.conversations.first { $0.id == "c" })
        XCTAssertEqual(result.attributedPercent, 30, accuracy: 0.000_001)
    }

    func testEstimatesAPIEquivalentUsingUncachedCachedAndOutputRates() throws {
        let usage = TokenUsageBreakdown(
            inputTokens: 1_000_000,
            cachedInputTokens: 800_000,
            cacheWriteInputTokens: 0,
            outputTokens: 100_000
        )

        let cost = try XCTUnwrap(
            APICostEstimator.estimateUSD(
                usage: usage,
                model: "gpt-5.6-sol",
                usesLongContextPricing: false
            )
        )

        XCTAssertEqual(cost, 4.4, accuracy: 0.000_001)
        XCTAssertNil(
            APICostEstimator.estimateUSD(
                usage: usage,
                model: "private-unknown-model",
                usesLongContextPricing: false
            )
        )
    }

    func testLongContextPricingStartsOnlyAbove272KInputTokens() {
        XCTAssertFalse(
            APICostEstimator.usesLongContextPricing(
                inputTokens: 272_000
            )
        )
        XCTAssertTrue(
            APICostEstimator.usesLongContextPricing(
                inputTokens: 272_001
            )
        )
    }

    func testParsesModelFromOuterTurnContextEventType() {
        let line = Data(
            #"{"timestamp":"2026-07-30T10:52:43.592Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}"#
                .utf8
        )

        XCTAssertEqual(
            RolloutEventParser.model(from: line),
            "gpt-5.6-sol"
        )
    }

    func testFindsOnlyCandidateMainThreadIDsInRolloutLine() {
        let data = Data(
            #"{"text":"parent 019f-main-a and unrelated 019f-other"}"#
                .utf8
        )

        XCTAssertEqual(
            RolloutEventParser.referencedIDs(
                in: data,
                candidates: ["019f-main-a", "019f-main-b"]
            ),
            ["019f-main-a"]
        )
    }

    func testFindsMultipleCandidateMainThreadIDsForGuardianBackgroundHandling() {
        let data = Data(
            #"{"text":"parents 019f-main-a, 019f-main-b, and 019f-unrelated"}"#
                .utf8
        )

        XCTAssertEqual(
            RolloutEventParser.referencedIDs(
                in: data,
                candidates: ["019f-main-a", "019f-main-b"]
            ),
            ["019f-main-a", "019f-main-b"]
        )
    }

    func testStreamsGuardianReferencesBeyondCycleBaselineAndModelContext() {
        var scanner = RolloutReferenceScanner(
            candidates: ["019f-main-a", "019f-main-b"]
        )

        scanner.consume(
            Data(#"{"timestamp":"2026-07-30T11:00:00Z","type":"token_count"}"#.utf8)
        )
        scanner.consume(
            Data(#"{"timestamp":"2026-07-30T10:00:00Z","type":"token_count"}"#.utf8)
        )
        scanner.consume(
            Data(#"{"timestamp":"2026-07-30T09:59:00Z","type":"turn_context"}"#.utf8)
        )
        scanner.consume(
            Data(#"{"timestamp":"2026-07-30T09:58:00Z","text":"parent 019f-main-a"}"#.utf8)
        )

        XCTAssertEqual(scanner.referencedIDs, ["019f-main-a"])
    }

    func testSortsTasksBySelectedDisplayMetric() {
        let sharedDate = Date(timeIntervalSince1970: 600)
        let tasks = [
            makeTask(id: "alpha", quota: 90, tokens: 100, cost: 1, lastActive: 100),
            makeTask(id: "beta", quota: 80, tokens: 300, cost: 2, lastActive: 200),
            makeTask(id: "gamma", quota: 70, tokens: 200, cost: 3, lastActive: 300),
            makeTask(id: "zeta", quota: 60, tokens: 50, cost: 0, lastActive: 400),
            makeTask(id: "delta", quota: 60, tokens: 40, cost: 0, lastActive: 500),
            makeTask(id: "omega", quota: 50, tokens: 25, cost: 0.25, lastActive: sharedDate),
            makeTask(id: "kappa", quota: 50, tokens: 25, cost: 0.25, lastActive: sharedDate)
        ]

        XCTAssertEqual(
            TaskDisplayOrdering.sorted(tasks, by: .quota).map(\.id),
            ["alpha", "beta", "gamma", "delta", "zeta", "kappa", "omega"]
        )
        XCTAssertEqual(
            TaskDisplayOrdering.sorted(tasks, by: .tokens).map(\.id),
            ["beta", "gamma", "alpha", "zeta", "delta", "kappa", "omega"]
        )
        XCTAssertEqual(
            TaskDisplayOrdering.sorted(tasks, by: .apiCost).map(\.id),
            ["gamma", "beta", "alpha", "kappa", "omega", "delta", "zeta"]
        )
    }

    private func makeTask(
        id: String,
        quota: Double,
        tokens: Int64,
        cost: Double,
        lastActive: TimeInterval
    ) -> TaskQuotaUsage {
        makeTask(
            id: id,
            quota: quota,
            tokens: tokens,
            cost: cost,
            lastActive: Date(timeIntervalSince1970: lastActive)
        )
    }

    private func makeTask(
        id: String,
        quota: Double,
        tokens: Int64,
        cost: Double,
        lastActive: Date
    ) -> TaskQuotaUsage {
        TaskQuotaUsage(
            id: id,
            title: id,
            projectPath: "/\(id)",
            usedPercent: quota,
            tokenCount: tokens,
            apiEquivalentCostUSD: cost,
            modelLabel: "gpt-5.6-sol",
            subtaskCount: 0,
            lastActive: lastActive,
            containsEstimatedPricing: false
        )
    }
}
