import XCTest
@testable import CodexOrbCore

final class TaskAggregationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testAggregatesNestedChildrenAndUniqueGuardiansIntoUserAndAutomationRoots() throws {
        let records = [
            record(id: "user", relation: .main, tokens: 100, cost: 1),
            record(id: "child", relation: .child(parentID: "user"), tokens: 200, cost: 2),
            record(id: "grandchild", relation: .child(parentID: "child"), tokens: 300, cost: 3),
            record(id: "user-guardian", relation: .guardian(referencedRootIDs: ["user"]), tokens: 40, cost: 0.4),
            record(id: "automation", relation: .automation, tokens: 50, cost: 0.5),
            record(id: "automation-child", relation: .child(parentID: "automation"), tokens: 60, cost: 0.6),
            record(id: "automation-guardian", relation: .guardian(referencedRootIDs: ["automation"]), tokens: 30, cost: 0.3)
        ]

        let result = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 7.8)

        let user = try XCTUnwrap(result.tasks.first { $0.id == "user" })
        XCTAssertEqual(user.tokenCount, 640)
        XCTAssertEqual(user.apiEquivalentCostUSD, 6.4, accuracy: 0.000_001)
        XCTAssertEqual(user.subtaskCount, 3)
        XCTAssertEqual(user.usedPercent, 6.4, accuracy: 0.000_001)

        let automation = try XCTUnwrap(result.automationTasks.first { $0.id == "automation" })
        XCTAssertEqual(automation.tokenCount, 140)
        XCTAssertEqual(automation.apiEquivalentCostUSD, 1.4, accuracy: 0.000_001)
        XCTAssertEqual(automation.subtaskCount, 2)
        XCTAssertEqual(automation.usedPercent, 1.4, accuracy: 0.000_001)

        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.automationTasks.count, 1)
        XCTAssertEqual(result.backgroundThreadCount, 0)
        XCTAssertEqual(result.backgroundTokenCount, 0)
        XCTAssertEqual(result.backgroundAPICostUSD, 0, accuracy: 0.000_001)
    }

    func testPlacesMissingParentsCyclesAndMultiRootGuardiansInBackground() {
        let records = [
            record(id: "user", relation: .main, tokens: 0, cost: 0),
            record(id: "automation", relation: .automation, tokens: 0, cost: 0),
            record(id: "missing", relation: .child(parentID: "unknown"), tokens: 10, cost: 1),
            record(id: "cycle-a", relation: .child(parentID: "cycle-b"), tokens: 20, cost: 2),
            record(id: "cycle-b", relation: .child(parentID: "cycle-a"), tokens: 30, cost: 3),
            record(
                id: "multi-root-guardian",
                relation: .guardian(referencedRootIDs: ["user", "automation"]),
                tokens: 40,
                cost: 4
            )
        ]

        let result = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 10)

        XCTAssertEqual(result.tasks.map(\.id), ["user"])
        XCTAssertTrue(result.automationTasks.isEmpty)
        XCTAssertEqual(result.backgroundThreadCount, 4)
        XCTAssertEqual(result.backgroundTokenCount, 100)
        XCTAssertEqual(result.backgroundAPICostUSD, 10, accuracy: 0.000_001)
        XCTAssertEqual(result.backgroundUsedPercent, 10, accuracy: 0.000_001)
    }

    func testDeduplicatesIdenticalIDsAndConservesCurrentCycleTotals() throws {
        let user = record(id: "user", relation: .main, tokens: 100, cost: 1)
        let child = record(id: "child", relation: .child(parentID: "user"), tokens: 200, cost: nil)
        let automation = record(id: "automation", relation: .automation, tokens: 50, cost: 0.5)
        let background = record(id: "background", relation: .background, tokens: 25, cost: nil)
        let records = [user, user, child, child, automation, background, background]

        let result = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 15)

        let userTask = try XCTUnwrap(result.tasks.first { $0.id == "user" })
        let automationTask = try XCTUnwrap(result.automationTasks.first { $0.id == "automation" })
        XCTAssertEqual(userTask.tokenCount, 300)
        XCTAssertEqual(userTask.apiEquivalentCostUSD, 3, accuracy: 0.000_001)
        XCTAssertEqual(automationTask.tokenCount, 50)
        XCTAssertEqual(automationTask.apiEquivalentCostUSD, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(result.backgroundThreadCount, 1)
        XCTAssertEqual(result.backgroundTokenCount, 25)
        XCTAssertEqual(result.backgroundAPICostUSD, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(
            result.tasks.reduce(Int64(0)) { $0 + $1.tokenCount }
                + result.automationTasks.reduce(Int64(0)) { $0 + $1.tokenCount }
                + result.backgroundTokenCount,
            375
        )
        XCTAssertEqual(
            result.tasks.reduce(0) { $0 + $1.apiEquivalentCostUSD }
                + result.automationTasks.reduce(0) { $0 + $1.apiEquivalentCostUSD }
                + result.backgroundAPICostUSD,
            3.75,
            accuracy: 0.000_001
        )
    }

    func testConflictingDuplicatesUseDeterministicPreferenceAndAreForcedToBackground() {
        let root = record(id: "root", relation: .main, tokens: 0, cost: 0)
        let activePreferred = [
            record(id: "active-preferred", relation: .child(parentID: "root"), tokens: 20, cost: 2, active: true, lastActive: 100),
            record(id: "active-preferred", relation: .background, tokens: 900, cost: 90, active: false, lastActive: 300)
        ]
        let laterPreferred = [
            record(id: "later-preferred", relation: .background, tokens: 300, cost: 30, active: true, lastActive: 100),
            record(id: "later-preferred", relation: .child(parentID: "root"), tokens: 40, cost: 4, active: true, lastActive: 200)
        ]
        let canonicalPreferred = [
            record(id: "canonical-preferred", title: "A", relation: .child(parentID: "root"), tokens: 50, cost: 5, active: true, lastActive: 200),
            record(id: "canonical-preferred", title: "B", relation: .background, tokens: 60, cost: 6, active: true, lastActive: 200)
        ]
        let records = [root] + activePreferred + laterPreferred + canonicalPreferred

        let forward = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 11)
        let reversed = TaskUsageAggregator.aggregate(records: Array(records.reversed()), currentUsedPercent: 11)

        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.tasks.map(\.id), ["root"])
        XCTAssertEqual(forward.backgroundThreadCount, 3)
        XCTAssertEqual(forward.backgroundTokenCount, 110)
        XCTAssertEqual(forward.backgroundAPICostUSD, 11, accuracy: 0.000_001)
        XCTAssertEqual(forward.backgroundUsedPercent, 11, accuracy: 0.000_001)
    }

    func testInactiveAncestorsOnlyResolveRelationshipsAndVisibilityRequiresActiveConsumption() {
        let records = [
            record(id: "inactive-alone", relation: .main, tokens: 999, cost: 99, active: false),
            record(id: "inactive-orphan", relation: .child(parentID: "missing"), tokens: 999, cost: 99, active: false),
            record(id: "live-root", relation: .main, tokens: 999, cost: 99, active: false),
            record(id: "inactive-ancestor", relation: .child(parentID: "live-root"), tokens: 999, cost: 99, active: false),
            record(id: "active-descendant", relation: .child(parentID: "inactive-ancestor"), tokens: 10, cost: 1),
            record(id: "active-zero-root", relation: .main, tokens: 0, cost: 0),
            record(id: "inactive-automation", relation: .automation, tokens: 999, cost: 99, active: false),
            record(id: "automation-child", relation: .child(parentID: "inactive-automation"), tokens: 5, cost: 0.5),
            record(id: "zero-automation", relation: .automation, tokens: 0, cost: 0),
            record(id: "cost-only-automation", relation: .automation, tokens: 0, cost: 0.25)
        ]

        let result = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 17.5)

        XCTAssertEqual(Set(result.tasks.map(\.id)), ["live-root", "active-zero-root"])
        XCTAssertEqual(Set(result.automationTasks.map(\.id)), ["inactive-automation", "cost-only-automation"])
        XCTAssertFalse(result.tasks.contains { $0.id == "inactive-alone" })
        XCTAssertFalse(result.automationTasks.contains { $0.id == "zero-automation" })
        XCTAssertEqual(result.tasks.first { $0.id == "live-root" }?.tokenCount, 10)
        XCTAssertEqual(result.tasks.first { $0.id == "live-root" }?.subtaskCount, 1)
        XCTAssertEqual(result.tasks.first { $0.id == "active-zero-root" }?.usedPercent, 0)
        XCTAssertEqual(result.backgroundThreadCount, 0)
        XCTAssertEqual(
            result.tasks.reduce(Int64(0)) { $0 + $1.tokenCount }
                + result.automationTasks.reduce(Int64(0)) { $0 + $1.tokenCount }
                + result.backgroundTokenCount,
            15
        )
        XCTAssertEqual(
            result.tasks.reduce(0) { $0 + $1.apiEquivalentCostUSD }
                + result.automationTasks.reduce(0) { $0 + $1.apiEquivalentCostUSD }
                + result.backgroundAPICostUSD,
            1.75,
            accuracy: 0.000_001
        )
    }

    func testAllocatesByAPICostBeforeTokenCounts() throws {
        let records = [
            record(id: "user", relation: .main, tokens: 1_000, cost: 1),
            record(id: "automation", relation: .automation, tokens: 1, cost: 3),
            record(id: "background", relation: .background, tokens: 5_000, cost: 6)
        ]

        let result = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 20)

        XCTAssertEqual(try XCTUnwrap(result.tasks.first).usedPercent, 2, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(result.automationTasks.first).usedPercent, 6, accuracy: 0.000_001)
        XCTAssertEqual(result.backgroundUsedPercent, 12, accuracy: 0.000_001)
        XCTAssertFalse(result.hasUnreconstructedQuota)
    }

    func testFallsBackToTokenWeightsWhenAllAPICostsAreZero() throws {
        let records = [
            record(id: "user", relation: .main, tokens: 100, cost: 0),
            record(id: "automation", relation: .automation, tokens: 300, cost: 0),
            record(id: "background", relation: .background, tokens: 600, cost: 0)
        ]

        let result = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 20)

        XCTAssertEqual(try XCTUnwrap(result.tasks.first).usedPercent, 2, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(result.automationTasks.first).usedPercent, 6, accuracy: 0.000_001)
        XCTAssertEqual(result.backgroundUsedPercent, 12, accuracy: 0.000_001)
        XCTAssertFalse(result.hasUnreconstructedQuota)
    }

    func testFallsBackEntirelyToBackgroundWhenNoLocalWeightsExist() {
        let records = [
            record(id: "a", relation: .main, tokens: 0, cost: 0),
            record(id: "b", relation: .main, tokens: 0, cost: 0),
            record(id: "hidden-automation", relation: .automation, tokens: 0, cost: 0)
        ]

        let result = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 25)
        let zeroOfficial = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 0)

        XCTAssertEqual(result.tasks.map(\.usedPercent), [0, 0])
        XCTAssertTrue(result.automationTasks.isEmpty)
        XCTAssertEqual(result.backgroundUsedPercent, 25, accuracy: 0.000_001)
        XCTAssertTrue(result.hasUnreconstructedQuota)
        XCTAssertEqual(result.officialDisplayTenths, 250)
        XCTAssertEqual(result.backgroundDisplayTenths, 250)
        XCTAssertFalse(zeroOfficial.hasUnreconstructedQuota)
    }

    func testLargestRemainderAllocatesDisplayedTenthsOnceWithStableTieBreaks() {
        let records = [
            record(id: "a", relation: .main, tokens: 0, cost: 1),
            record(id: "b", relation: .automation, tokens: 0, cost: 1),
            record(id: "unresolved", relation: .background, tokens: 0, cost: 1)
        ]

        let result = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 1.0)

        XCTAssertEqual(result.officialDisplayTenths, 10)
        XCTAssertEqual(result.tasks.first { $0.id == "a" }?.displayUsedTenths, 4)
        XCTAssertEqual(result.automationTasks.first { $0.id == "b" }?.displayUsedTenths, 3)
        XCTAssertEqual(result.backgroundDisplayTenths, 3)
        XCTAssertEqual(
            result.tasks.reduce(0) { $0 + $1.displayUsedTenths }
                + result.automationTasks.reduce(0) { $0 + $1.displayUsedTenths }
                + result.backgroundDisplayTenths,
            result.officialDisplayTenths
        )
    }

    func testLargestRemainderQuantizesMathematicalTiesBeforeRootIDOrdering() throws {
        let records = [
            record(id: "a", relation: .main, tokens: 0, cost: 1),
            record(id: "b", relation: .automation, tokens: 0, cost: 3),
            record(id: "unresolved", relation: .background, tokens: 0, cost: 0)
        ]

        let result = TaskUsageAggregator.aggregate(records: records, currentUsedPercent: 0.2)
        let user = try XCTUnwrap(result.tasks.first { $0.id == "a" })
        let automation = try XCTUnwrap(result.automationTasks.first { $0.id == "b" })

        XCTAssertEqual(user.usedPercent, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(automation.usedPercent, 0.15, accuracy: 0.000_001)
        XCTAssertEqual(result.officialDisplayTenths, 2)
        XCTAssertEqual(user.displayUsedTenths, 1)
        XCTAssertEqual(automation.displayUsedTenths, 1)
        XCTAssertEqual(result.backgroundDisplayTenths, 0)
    }

    private func record(
        id: String,
        title: String? = nil,
        relation: ThreadRelation,
        tokens: Int64,
        cost: Double?,
        active: Bool = true,
        lastActive: TimeInterval = 1_000
    ) -> ThreadTaskUsage {
        ThreadTaskUsage(
            id: id,
            title: title ?? id,
            projectPath: "/\(id)",
            relation: relation,
            tokenCount: tokens,
            apiEquivalentCostUSD: cost,
            modelLabel: "gpt-5.6-sol",
            lastActive: Date(timeIntervalSince1970: lastActive),
            isActiveInCycle: active
        )
    }
}
