import XCTest
@testable import CodexOrbCore

final class TaskPresentationTests: XCTestCase {
    func testQuotaFooterFormatsAllocatedTenthsWithoutRedistributingThem() {
        let display = QuotaFooterDisplay(
            mainTenths: 181,
            automationTenths: 26,
            backgroundTenths: 43,
            officialTenths: 250,
            hasUnreconstructedQuota: false
        )

        XCTAssertEqual(display.mainTenths, 181)
        XCTAssertEqual(display.automationTenths, 26)
        XCTAssertEqual(display.backgroundTenths, 43)
        XCTAssertEqual(display.officialTenths, 250)
        XCTAssertEqual(
            display.mainTenths
                + display.automationTenths
                + display.backgroundTenths,
            display.officialTenths
        )
        XCTAssertEqual(display.mainText, "18.1%")
        XCTAssertEqual(display.automationText, "2.6%")
        XCTAssertEqual(display.backgroundText, "4.3%")
        XCTAssertEqual(display.officialText, "25.0%")
        XCTAssertNil(display.unreconstructedText)
    }

    func testQuotaFooterShowsUnreconstructedQuotaAsSeparateDiagnostic() {
        let display = QuotaFooterDisplay(
            mainTenths: 0,
            automationTenths: 0,
            backgroundTenths: 250,
            officialTenths: 250,
            hasUnreconstructedQuota: true
        )

        XCTAssertEqual(display.unreconstructedText, "无法重建消耗 · 25.0%")
    }

    func testTaskDetailUsesRunningDirectoryAndSubtaskCount() {
        XCTAssertEqual(
            TaskDetailFormatter.detail(
                projectPath: "/tmp/codex-fixtures/股票",
                subtaskCount: 2,
                containsEstimatedPricing: false
            ),
            "运行目录：股票 · 已归并 2 个子任务"
        )
    }

    func testTaskDetailUsesUnknownForEmptyPathAndKeepsEstimatedPrefix() {
        XCTAssertEqual(
            TaskDetailFormatter.detail(
                projectPath: "",
                subtaskCount: 1,
                containsEstimatedPricing: false
            ),
            "运行目录：未知 · 已归并 1 个子任务"
        )
        XCTAssertEqual(
            TaskDetailFormatter.detail(
                projectPath: "/tmp/机器人",
                subtaskCount: 3,
                containsEstimatedPricing: true
            ),
            "含估算 · 运行目录：机器人 · 已归并 3 个子任务"
        )
    }

    func testUserAndAutomationArraysStaySeparateForEveryDisplayMetric() {
        let users = [
            makeTask(id: "user-low", quota: 1, tokens: 10, cost: 0.1),
            makeTask(id: "user-high", quota: 2, tokens: 20, cost: 0.2)
        ]
        let automation = [
            makeTask(id: "auto-low", quota: 30, tokens: 300, cost: 3),
            makeTask(id: "auto-high", quota: 40, tokens: 400, cost: 4)
        ]

        for metric in [TaskDisplayMetric.quota, .tokens, .apiCost] {
            XCTAssertEqual(
                TaskDisplayOrdering.sorted(users, by: metric).map(\.id),
                ["user-high", "user-low"]
            )
            XCTAssertEqual(
                TaskDisplayOrdering.sorted(automation, by: metric).map(\.id),
                ["auto-high", "auto-low"]
            )
        }
    }

    func testQuotaOrderingUsesRawPercentWhenVisibleTenthsTie() {
        let tasks = [
            makeTask(
                id: "raw-low",
                quota: 0.051,
                displayUsedTenths: 1,
                tokens: 1,
                cost: 0
            ),
            makeTask(
                id: "raw-high",
                quota: 0.149,
                displayUsedTenths: 1,
                tokens: 1,
                cost: 0
            )
        ]

        XCTAssertEqual(tasks.map(\.displayUsedTenths), [1, 1])
        XCTAssertEqual(
            tasks.map {
                QuotaFooterDisplay(
                    mainTenths: $0.displayUsedTenths,
                    automationTenths: 0,
                    backgroundTenths: 0,
                    officialTenths: $0.displayUsedTenths,
                    hasUnreconstructedQuota: false
                ).mainText
            },
            ["0.1%", "0.1%"]
        )
        XCTAssertEqual(
            TaskDisplayOrdering.sorted(tasks, by: .quota).map(\.id),
            ["raw-high", "raw-low"]
        )
    }

    private func makeTask(
        id: String,
        quota: Double,
        displayUsedTenths: Int? = nil,
        tokens: Int64,
        cost: Double
    ) -> TaskQuotaUsage {
        TaskQuotaUsage(
            id: id,
            title: id,
            projectPath: "/tmp/\(id)",
            usedPercent: quota,
            displayUsedTenths: displayUsedTenths,
            tokenCount: tokens,
            apiEquivalentCostUSD: cost,
            modelLabel: "gpt-5.6-sol",
            subtaskCount: 0,
            lastActive: Date(timeIntervalSince1970: 1_000),
            containsEstimatedPricing: false
        )
    }
}
