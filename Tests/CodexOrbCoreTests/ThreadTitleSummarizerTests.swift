import XCTest
@testable import CodexOrbCore

final class ThreadTitleSummarizerTests: XCTestCase {
    private func makeCacheURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("thread-titles.json")
    }

    func testCacheReusesStableTitleAndPersistsIt() throws {
        let url = try makeCacheURL()
        var cache = ThreadTitleCache(algorithmVersion: 1)
        let first = cache.title(for: "thread-a") { "网站基座" }
        let second = cache.title(for: "thread-a") { "不应替换" }
        try cache.save(to: url)
        let restored = ThreadTitleCache.load(from: url, algorithmVersion: 1)

        XCTAssertEqual(first, "网站基座")
        XCTAssertEqual(second, "网站基座")
        XCTAssertEqual(restored.titles["thread-a"], "网站基座")
    }

    func testCacheInvalidatesDifferentAlgorithmVersion() throws {
        let url = try makeCacheURL()
        var cache = ThreadTitleCache(algorithmVersion: 1)
        _ = cache.title(for: "thread-a") { "网站基座" }
        try cache.save(to: url)

        XCTAssertTrue(
            ThreadTitleCache.load(from: url, algorithmVersion: 2).titles.isEmpty
        )
    }

    func testVersionTwoCacheIsInvalidatedByCurrentTitleAlgorithm() throws {
        let url = try makeCacheURL()
        var cache = ThreadTitleCache(algorithmVersion: 2)
        _ = cache.title(for: "thread-a") { "地平线股票" }
        try cache.save(to: url)

        XCTAssertTrue(
            ThreadTitleCache.load(
                from: url,
                algorithmVersion: ThreadTitleSummarizer.algorithmVersion
            ).titles.isEmpty
        )
    }

    func testVersionThreeCacheIsInvalidatedByCurrentTitleAlgorithm() throws {
        let url = try makeCacheURL()
        var cache = ThreadTitleCache(algorithmVersion: 3)
        _ = cache.title(for: "thread-a") { "网站项目优化" }
        try cache.save(to: url)

        XCTAssertTrue(
            ThreadTitleCache.load(
                from: url,
                algorithmVersion: ThreadTitleSummarizer.algorithmVersion
            ).titles.isEmpty
        )
    }

    func testCorruptCacheFallsBackToEmptyCache() throws {
        let url = try makeCacheURL()
        try Data("not-json".utf8).write(to: url)
        XCTAssertTrue(
            ThreadTitleCache.load(from: url, algorithmVersion: 1).titles.isEmpty
        )
    }

    func testCacheRejectsNonNormalizedPersistedTitle() throws {
        let url = try makeCacheURL()
        try Data(
            #"{"algorithmVersion":1,"titles":{"thread-a":"A - B"}}"#.utf8
        ).write(to: url)

        let restored = ThreadTitleCache.load(from: url, algorithmVersion: 1)
        var regeneratedCache = restored
        let regenerated = regeneratedCache.title(for: "thread-a") { "A - B" }

        XCTAssertNil(restored.titles["thread-a"])
        XCTAssertEqual(regenerated, "AB")
        XCTAssertLessThanOrEqual(regenerated.count, 8)
    }

    func testSummarizesConcreteSidebarConversations() {
        let cases = [
            ("制作 Codex 额度监控小球", "Codex额度球"),
            ("拆解AI篮球训练机成本", "篮球机成本"),
            ("设计非人形环境适配机器人", "环境机器人"),
            ("收集 WAIC 2026 信息", "WAIC信息"),
            ("分析汽车智能驾驶能力排行", "智能驾驶排行"),
            ("重构 image2.0 视频工作流", "视频工作流"),
            ("构建知识框架提升思维能力", "知识框架"),
            ("全面分析小米 SkyNomad 车辆成本", "小米车型成本")
        ]

        for (source, expected) in cases {
            let actual = ThreadTitleSummarizer.summarize(
                title: source,
                firstMessage: "",
                cwd: "/tmp/projects/example"
            )
            XCTAssertEqual(actual, expected, source)
            XCTAssertLessThanOrEqual(actual.count, 8, source)
        }
    }

    func testSummarizesHorizonStockPromptAsStockAnalysis() {
        let actual = ThreadTitleSummarizer.summarize(
            title: "请全面分析地平线机器人股票",
            firstMessage: "",
            cwd: "/tmp/projects/stocks"
        )

        XCTAssertEqual(actual, "股票分析")
        XCTAssertLessThanOrEqual(actual.count, 8)
    }

    func testRemovesSkillLinkAndFallsBackToFirstMessage() {
        let actual = ThreadTitleSummarizer.summarize(
            title: "[$skill](app://skill)\n",
            firstMessage: "分析医药零售AI影响趋势",
            cwd: "/tmp/projects/macro"
        )
        XCTAssertEqual(actual, "医药AI趋势")
    }

    func testRemovesGreetingBeforeSelectingEntityAndTopic() {
        let actual = ThreadTitleSummarizer.summarize(
            title: "你好，帮我分析 GitHub 项目",
            firstMessage: "",
            cwd: "/tmp/projects/code"
        )

        XCTAssertEqual(actual, "GitHub项目")
    }

    func testUsesUsefulFirstMessageWhenTitleIsPlaceholder() {
        let actual = ThreadTitleSummarizer.summarize(
            title: "新对话",
            firstMessage: "请帮我重构 image2.0 视频工作流",
            cwd: "/tmp/projects/video"
        )

        XCTAssertEqual(actual, "视频工作流")
    }

    func testPrefersInformativeFirstMessageOverGenericTitle() {
        let actual = ThreadTitleSummarizer.summarize(
            title: "帮我看看",
            firstMessage: "整理客户访谈结论",
            cwd: "/tmp/projects/work"
        )

        XCTAssertEqual(actual, "客户访谈结论")
    }

    func testSummaryUsesOnlyRootTextAndNeverCWD() {
        let summaries = [
            "/tmp/projects/stocks",
            "/tmp/projects/design",
            ""
        ].map { cwd in
            ThreadTitleSummarizer.summarize(
                title: "优化项目",
                firstMessage: "请继续优化项目",
                cwd: cwd
            )
        }

        XCTAssertEqual(summaries, ["优化项目", "优化项目", "优化项目"])
        XCTAssertTrue(summaries.allSatisfy { $0.count <= 8 })
    }

    func testDoesNotStripLowInformationSubstringInsideConcreteTitle() {
        let cases = [
            ("处理器性能", "整理待办清单"),
            ("搞笑视频", "整理课程笔记"),
            ("弄堂文化", "整理待办清单")
        ]

        for (title, firstMessage) in cases {
            let actual = ThreadTitleSummarizer.summarize(
                title: title,
                firstMessage: firstMessage,
                cwd: "/tmp/projects/work"
            )

            XCTAssertEqual(actual, title, title)
        }
    }

    func testOverlappingLowInformationPhrasesFinishWithinBoundedTime() {
        let title = String(repeating: "处理一下", count: 20)
            + "处理器性能"
        let clock = ContinuousClock()
        let start = clock.now

        let actual = ThreadTitleSummarizer.summarize(
            title: title,
            firstMessage: "整理待办清单",
            cwd: "/tmp/projects/work"
        )
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(actual, "处理一下处理一下")
        XCTAssertLessThan(
            elapsed,
            .milliseconds(250),
            "Overlapping phrase classification took \(elapsed)"
        )
    }

    func testPrefersEntityAndCoreTopicFromLongUnmatchedPrompt() {
        let actual = ThreadTitleSummarizer.summarize(
            title: "请帮我详细研究 GitHub 项目的权限安全治理方案",
            firstMessage: "",
            cwd: "/tmp/projects/code"
        )

        XCTAssertEqual(actual, "GitHub安全")
    }

    func testEveryFallbackIsNonEmptyAndAtMostEightCharacters() {
        let inputs = [
            "这是一个没有命中主题规则但非常非常长的具体对话",
            "GitHub项目",
            "Saltwind",
            ""
        ]
        for input in inputs {
            let result = ThreadTitleSummarizer.summarize(
                title: input,
                firstMessage: "",
                cwd: ""
            )
            XCTAssertFalse(result.isEmpty)
            XCTAssertLessThanOrEqual(result.count, 8)
        }
    }

    func testRemovesASCIIFullwidthAndUnicodeSeparatorsFromFallbackTitles() {
        let cases = [
            ("分析 A-B/C(D)[E]\"F\"'G'", "ABCDEFG"),
            ("分析 A&B", "AB"),
            ("分析 A（B）［C］“D”‘E’", "ABCDE"),
            ("分析 A—B…C、D", "ABCD"),
            ("分析 image2.0-CLI", "image2.0")
        ]

        for (source, expected) in cases {
            let actual = ThreadTitleSummarizer.summarize(
                title: source,
                firstMessage: "",
                cwd: ""
            )
            XCTAssertEqual(actual, expected, source)
        }
    }
}
