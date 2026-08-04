import CodexOrbCore
import Foundation
import XCTest
@testable import CodexOrb

final class TaskQuotaStoreIntegrationTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let databaseURL: URL
        let cacheURL: URL
        let includesThreadSource: Bool
    }

    private func makeFixture(
        includesThreadSource: Bool = true
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fixture = Fixture(
            directory: directory,
            databaseURL: directory.appendingPathComponent("state_1.sqlite"),
            cacheURL: directory.appendingPathComponent("thread-titles.json"),
            includesThreadSource: includesThreadSource
        )
        var columnDefinitions = [
            "id TEXT PRIMARY KEY",
            "rollout_path TEXT",
            "cwd TEXT NOT NULL",
            "source TEXT"
        ]
        if includesThreadSource {
            columnDefinitions.append("thread_source TEXT")
        }
        columnDefinitions.append(contentsOf: [
            "title TEXT",
            "first_user_message TEXT",
            "updated_at_ms INTEGER NOT NULL"
        ])
        try runSQLite(
            databaseURL: fixture.databaseURL,
            query: """
            CREATE TABLE threads (
                \(columnDefinitions.joined(separator: ",\n    "))
            );
            """
        )
        return fixture
    }

    private func runSQLite(
        databaseURL: URL,
        query: String
    ) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, query]
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let error = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            XCTFail("sqlite3 fixture setup failed: \(error)")
            return
        }
    }

    private func insertThread(
        into fixture: Fixture,
        id: String,
        rolloutPath: String?,
        source: String?,
        threadSource: String? = nil,
        title: String,
        firstMessage: String,
        updatedAtMilliseconds: Int64,
        cwd: String = "/tmp/project"
    ) throws {
        var columns = ["id", "rollout_path", "cwd", "source"]
        var values = [
            sqlLiteral(id),
            rolloutPath.map(sqlLiteral) ?? "NULL",
            sqlLiteral(cwd),
            source.map(sqlLiteral) ?? "NULL"
        ]
        if fixture.includesThreadSource {
            columns.append("thread_source")
            values.append(threadSource.map(sqlLiteral) ?? "NULL")
        }
        columns.append(contentsOf: [
            "title",
            "first_user_message",
            "updated_at_ms"
        ])
        values.append(contentsOf: [
            sqlLiteral(title),
            sqlLiteral(firstMessage),
            String(updatedAtMilliseconds)
        ])
        try runSQLite(
            databaseURL: fixture.databaseURL,
            query: """
            INSERT INTO threads (
                \(columns.joined(separator: ",\n    "))
            ) VALUES (
                \(values.joined(separator: ",\n    "))
            );
            """
        )
    }

    private func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func quota(cycleStart: Date) -> QuotaSnapshot {
        QuotaSnapshot(
            usedPercent: 37,
            windowDurationMinutes: 60,
            resetsAt: cycleStart.addingTimeInterval(60 * 60)
        )
    }

    private func writeRollout(
        _ lines: [String],
        to url: URL
    ) throws {
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter.string(from: date)
    }

    private func tokenLine(
        at date: Date,
        inputTokens: Int64,
        outputTokens: Int64
    ) -> String {
        """
        {"timestamp":"\(timestamp(date))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(inputTokens),"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":\(outputTokens)},"last_token_usage":{"input_tokens":\(inputTokens),"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":\(outputTokens)}}}}
        """
    }

    private func referenceLine(
        at date: Date,
        threadIDs: [String]
    ) -> String {
        """
        {"timestamp":"\(timestamp(date))","type":"event_msg","payload":{"type":"review","text":"main threads \(threadIDs.joined(separator: " "))"}}
        """
    }

    private func sessionMetaLine(
        mainID: String,
        guardianID: String,
        parentID: String
    ) -> String {
        """
        {"type":"session_meta","payload":{"session_id":"\(mainID)","id":"\(guardianID)","parent_thread_id":"\(parentID)","source":{"subagent":{"other":"guardian"}}}}
        """
    }

    private func embeddedMemoryLine(
        at date: Date,
        unrelatedThreadID: String
    ) -> String {
        """
        {"timestamp":"\(timestamp(date))","type":"event_msg","payload":{"type":"memory","text":"historical rollout \(unrelatedThreadID)"}}
        """
    }

    private func childSource(parentID: String) -> String {
        #"{"subagent":{"thread_spawn":{"parent_thread_id":"\#(parentID)"}}}"#
    }

    private func guardianSource() -> String {
        #"{"subagent":{"other":"guardian"}}"#
    }

    private func writeTokenRollout(
        at url: URL,
        cycleStart: Date,
        inputTokens: Int64,
        outputTokens: Int64
    ) throws {
        try writeRollout(
            [
                tokenLine(
                    at: cycleStart.addingTimeInterval(10),
                    inputTokens: inputTokens,
                    outputTokens: outputTokens
                )
            ],
            to: url
        )
    }

    private func assertCompleteResult(
        _ result: TaskAggregationResult,
        userIDs: Set<String>,
        automationIDs: Set<String>,
        backgroundCount: Int,
        totalTokens: Int64,
        totalAPICostUSD: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            Set(result.tasks.map(\.id)),
            userIDs,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(result.automationTasks.map(\.id)),
            automationIDs,
            file: file,
            line: line
        )
        XCTAssertEqual(
            result.backgroundThreadCount,
            backgroundCount,
            file: file,
            line: line
        )

        let observedTokens = result.tasks.reduce(Int64(0)) {
            $0 + $1.tokenCount
        } + result.automationTasks.reduce(Int64(0)) {
            $0 + $1.tokenCount
        } + result.backgroundTokenCount
        XCTAssertEqual(observedTokens, totalTokens, file: file, line: line)

        let observedAPICost = result.tasks.reduce(0.0) {
            $0 + $1.apiEquivalentCostUSD
        } + result.automationTasks.reduce(0.0) {
            $0 + $1.apiEquivalentCostUSD
        } + result.backgroundAPICostUSD
        XCTAssertEqual(
            observedAPICost,
            totalAPICostUSD,
            accuracy: 0.000_000_000_001,
            file: file,
            line: line
        )

        let observedUsedPercent = result.tasks.reduce(0.0) {
            $0 + $1.usedPercent
        } + result.automationTasks.reduce(0.0) {
            $0 + $1.usedPercent
        } + result.backgroundUsedPercent
        XCTAssertEqual(
            observedUsedPercent,
            result.officialUsedPercent,
            accuracy: 0.000_000_001,
            file: file,
            line: line
        )

        let observedDisplayTenths = result.tasks.reduce(0) {
            $0 + $1.displayUsedTenths
        } + result.automationTasks.reduce(0) {
            $0 + $1.displayUsedTenths
        } + result.backgroundDisplayTenths
        XCTAssertEqual(
            observedDisplayTenths,
            result.officialDisplayTenths,
            file: file,
            line: line
        )
    }

    private func fetchWithoutSuppressingFailure(
        fixture: Fixture,
        cycleStart: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> TaskAggregationResult? {
        do {
            return try await TaskQuotaStore(
                databaseURL: fixture.databaseURL,
                titleCacheURL: fixture.cacheURL
            ).fetchTasks(quota: quota(cycleStart: cycleStart))
        } catch {
            XCTFail(
                "A single unreadable rollout must not fail refresh: \(error)",
                file: file,
                line: line
            )
            return nil
        }
    }

    func testZeroActiveRowsReturnsEmptyQuotaResult() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let store = TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        )

        let result = try await store.fetchTasks(quota: quota(cycleStart: cycleStart))

        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertEqual(result.officialUsedPercent, 37)
        XCTAssertEqual(result.backgroundThreadCount, 0)
    }

    func testMissingParentRowDoesNotBlockQuotaResult() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        try insertThread(
            into: fixture,
            id: "child",
            rolloutPath: fixture.directory
                .appendingPathComponent("missing-rollout.jsonl").path,
            source: #"{"subagent":{"thread_spawn":{"parent_thread_id":"missing'parent"}}}"#,
            title: "子任务",
            firstMessage: "",
            updatedAtMilliseconds:
                Int64(cycleStart.timeIntervalSince1970 * 1_000) + 1
        )
        let store = TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        )

        let result = try await store.fetchTasks(quota: quota(cycleStart: cycleStart))

        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertEqual(result.officialUsedPercent, 37)
        XCTAssertEqual(result.backgroundThreadCount, 1)
    }

    func testActiveGuardianAttributesToReferencedInactiveMain() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let mainID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be59"
        let guardianID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be60"
        let guardianRollout = fixture.directory
            .appendingPathComponent("guardian.jsonl")
        try writeRollout(
            [
                referenceLine(
                    at: cycleStart.addingTimeInterval(10),
                    threadIDs: [mainID]
                ),
                tokenLine(
                    at: cycleStart.addingTimeInterval(20),
                    inputTokens: 80,
                    outputTokens: 20
                )
            ],
            to: guardianRollout
        )
        try insertThread(
            into: fixture,
            id: mainID,
            rolloutPath: fixture.directory
                .appendingPathComponent("inactive-main.jsonl").path,
            source: "vscode",
            title: "分析 GitHub 项目安全",
            firstMessage: "",
            updatedAtMilliseconds:
                Int64(cycleStart.timeIntervalSince1970 * 1_000) - 1
        )
        try insertThread(
            into: fixture,
            id: guardianID,
            rolloutPath: guardianRollout.path,
            source: #"{"subagent":{"other":"guardian"}}"#,
            title: "guardian",
            firstMessage: "",
            updatedAtMilliseconds:
                Int64(cycleStart.timeIntervalSince1970 * 1_000) + 1
        )
        let store = TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        )

        let result = try await store.fetchTasks(quota: quota(cycleStart: cycleStart))
        let task = try XCTUnwrap(result.tasks.first { $0.id == mainID })

        XCTAssertEqual(result.tasks.map(\.id), [mainID])
        XCTAssertEqual(task.tokenCount, 100)
        XCTAssertEqual(task.subtaskCount, 1)
        XCTAssertEqual(result.backgroundThreadCount, 0)
    }

    func testGuardianWithMultipleConfirmedInactiveRootsStaysBackground() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let firstMainID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be61"
        let secondMainID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be62"
        let guardianID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be63"
        let guardianRollout = fixture.directory
            .appendingPathComponent("ambiguous-guardian.jsonl")
        try writeRollout(
            [
                referenceLine(
                    at: cycleStart.addingTimeInterval(10),
                    threadIDs: [firstMainID, secondMainID]
                ),
                tokenLine(
                    at: cycleStart.addingTimeInterval(20),
                    inputTokens: 60,
                    outputTokens: 40
                )
            ],
            to: guardianRollout
        )
        for (id, title) in [
            (firstMainID, "主对话甲"),
            (secondMainID, "主对话乙")
        ] {
            try insertThread(
                into: fixture,
                id: id,
                rolloutPath: fixture.directory
                    .appendingPathComponent("\(id).jsonl").path,
                source: "vscode",
                title: title,
                firstMessage: "",
                updatedAtMilliseconds:
                    Int64(cycleStart.timeIntervalSince1970 * 1_000) - 1
            )
        }
        try insertThread(
            into: fixture,
            id: guardianID,
            rolloutPath: guardianRollout.path,
            source: #"{"subagent":{"other":"guardian"}}"#,
            title: "guardian",
            firstMessage: "",
            updatedAtMilliseconds:
                Int64(cycleStart.timeIntervalSince1970 * 1_000) + 1
        )
        let store = TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        )

        let result = try await store.fetchTasks(quota: quota(cycleStart: cycleStart))

        XCTAssertEqual(result.backgroundTokenCount, 100)
        assertCompleteResult(
            result,
            userIDs: [],
            automationIDs: [],
            backgroundCount: 1,
            totalTokens: 100,
            totalAPICostUSD: 0.000_1
        )
    }

    func testGuardianWithoutConfirmedMainStaysBackground() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let missingMainID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be64"
        let guardianID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be65"
        let guardianRollout = fixture.directory
            .appendingPathComponent("orphan-guardian.jsonl")
        try writeRollout(
            [
                referenceLine(
                    at: cycleStart.addingTimeInterval(10),
                    threadIDs: [missingMainID]
                ),
                tokenLine(
                    at: cycleStart.addingTimeInterval(20),
                    inputTokens: 70,
                    outputTokens: 30
                )
            ],
            to: guardianRollout
        )
        try insertThread(
            into: fixture,
            id: guardianID,
            rolloutPath: guardianRollout.path,
            source: #"{"subagent":{"other":"guardian"}}"#,
            title: "guardian",
            firstMessage: "",
            updatedAtMilliseconds:
                Int64(cycleStart.timeIntervalSince1970 * 1_000) + 1
        )
        let store = TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        )

        let result = try await store.fetchTasks(quota: quota(cycleStart: cycleStart))

        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertEqual(result.backgroundThreadCount, 1)
        XCTAssertEqual(result.backgroundTokenCount, 100)
    }

    func testStructuredGuardianSessionIgnoresUnrelatedMainUUIDInMemoryText() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let mainID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be66"
        let unrelatedMainID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be67"
        let guardianID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be68"
        let reviewID = "019fb2a6-a1d7-75a0-97e0-fbb93e00be69"
        let guardianRollout = fixture.directory
            .appendingPathComponent("structured-guardian.jsonl")
        try writeRollout(
            [
                sessionMetaLine(
                    mainID: mainID,
                    guardianID: guardianID,
                    parentID: reviewID
                ),
                embeddedMemoryLine(
                    at: cycleStart.addingTimeInterval(10),
                    unrelatedThreadID: unrelatedMainID
                ),
                tokenLine(
                    at: cycleStart.addingTimeInterval(20),
                    inputTokens: 75,
                    outputTokens: 25
                )
            ],
            to: guardianRollout
        )
        for (id, title) in [
            (mainID, "目标主对话"),
            (unrelatedMainID, "历史主对话")
        ] {
            try insertThread(
                into: fixture,
                id: id,
                rolloutPath: fixture.directory
                    .appendingPathComponent("\(id).jsonl").path,
                source: "vscode",
                title: title,
                firstMessage: "",
                updatedAtMilliseconds:
                    Int64(cycleStart.timeIntervalSince1970 * 1_000) - 1
            )
        }
        try insertThread(
            into: fixture,
            id: guardianID,
            rolloutPath: guardianRollout.path,
            source: #"{"subagent":{"other":"guardian"}}"#,
            title: "guardian",
            firstMessage: "",
            updatedAtMilliseconds:
                Int64(cycleStart.timeIntervalSince1970 * 1_000) + 1
        )
        let store = TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        )

        let result = try await store.fetchTasks(quota: quota(cycleStart: cycleStart))
        let task = try XCTUnwrap(result.tasks.first { $0.id == mainID })

        XCTAssertEqual(result.tasks.map(\.id), [mainID])
        XCTAssertEqual(task.tokenCount, 100)
        XCTAssertEqual(result.backgroundThreadCount, 0)
    }

    func testNewSchemaKeepsSameCWDUserRootsDistinct() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let updatedAt = Int64(cycleStart.timeIntervalSince1970 * 1_000)
        let stockRollout = fixture.directory.appendingPathComponent("stock.jsonl")
        let videoRollout = fixture.directory.appendingPathComponent("video.jsonl")
        try writeTokenRollout(
            at: stockRollout,
            cycleStart: cycleStart,
            inputTokens: 80,
            outputTokens: 20
        )
        try writeTokenRollout(
            at: videoRollout,
            cycleStart: cycleStart,
            inputTokens: 150,
            outputTokens: 50
        )
        try insertThread(
            into: fixture,
            id: "user-stock",
            rolloutPath: stockRollout.path,
            source: "vscode",
            threadSource: "user",
            title: "股票分析",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt + 1,
            cwd: "/tmp/codex-fixtures/股票"
        )
        try insertThread(
            into: fixture,
            id: "user-video",
            rolloutPath: videoRollout.path,
            source: "vscode",
            threadSource: "user",
            title: "视频工作流",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt + 2,
            cwd: "/tmp/codex-fixtures/股票"
        )

        let result = try await TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        ).fetchTasks(quota: quota(cycleStart: cycleStart))

        XCTAssertEqual(result.tasks.first { $0.id == "user-stock" }?.title, "股票分析")
        XCTAssertEqual(result.tasks.first { $0.id == "user-video" }?.title, "视频工作流")
        XCTAssertEqual(Set(result.tasks.map(\.projectPath)), ["/tmp/codex-fixtures/股票"])
        assertCompleteResult(
            result,
            userIDs: ["user-stock", "user-video"],
            automationIDs: [],
            backgroundCount: 0,
            totalTokens: 300,
            totalAPICostUSD: 0.000_3
        )
    }

    func testNewSchemaSeparatesAutomationRootAndNestedChild() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let updatedAt = Int64(cycleStart.timeIntervalSince1970 * 1_000)
        let rootRollout = fixture.directory.appendingPathComponent("automation.jsonl")
        let childRollout = fixture.directory.appendingPathComponent("automation-child.jsonl")
        try writeTokenRollout(
            at: rootRollout,
            cycleStart: cycleStart,
            inputTokens: 75,
            outputTokens: 25
        )
        try writeTokenRollout(
            at: childRollout,
            cycleStart: cycleStart,
            inputTokens: 40,
            outputTokens: 10
        )
        try insertThread(
            into: fixture,
            id: "automation-root",
            rolloutPath: rootRollout.path,
            source: "exec",
            threadSource: "automation",
            title: "每日巡检",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt + 1
        )
        try insertThread(
            into: fixture,
            id: "automation-child",
            rolloutPath: childRollout.path,
            source: childSource(parentID: "automation-root"),
            threadSource: "subagent",
            title: "child",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt + 2
        )

        let result = try await TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        ).fetchTasks(quota: quota(cycleStart: cycleStart))
        let automation = try XCTUnwrap(result.automationTasks.first)

        XCTAssertEqual(automation.tokenCount, 150)
        XCTAssertEqual(automation.subtaskCount, 1)
        assertCompleteResult(
            result,
            userIDs: [],
            automationIDs: ["automation-root"],
            backgroundCount: 0,
            totalTokens: 150,
            totalAPICostUSD: 0.000_15
        )
    }

    func testNewSchemaRejectsInternalFeaturesAndRootParentConflicts() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let updatedAt = Int64(cycleStart.timeIntervalSince1970 * 1_000)
        let rows: [(id: String, source: String?, threadSource: String)] = [
            ("composer", "vscode", "composer_link"),
            ("memory", "cli", "memory_consolidation"),
            ("unknown", "vscode", "experimental_feature"),
            ("user-conflict", childSource(parentID: "parent-user"), "user"),
            (
                "automation-conflict",
                childSource(parentID: "parent-automation"),
                "automation"
            )
        ]
        for (index, row) in rows.enumerated() {
            let rollout = fixture.directory.appendingPathComponent("\(row.id).jsonl")
            try writeTokenRollout(
                at: rollout,
                cycleStart: cycleStart,
                inputTokens: 8,
                outputTokens: 2
            )
            try insertThread(
                into: fixture,
                id: row.id,
                rolloutPath: rollout.path,
                source: row.source,
                threadSource: row.threadSource,
                title: row.id,
                firstMessage: "",
                updatedAtMilliseconds: updatedAt + Int64(index + 1)
            )
        }

        let result = try await TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        ).fetchTasks(quota: quota(cycleStart: cycleStart))

        assertCompleteResult(
            result,
            userIDs: [],
            automationIDs: [],
            backgroundCount: 5,
            totalTokens: 50,
            totalAPICostUSD: 0.000_05
        )
    }

    func testInactiveUserRootIsFetchedThroughNestedActiveChildAncestors() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let updatedAt = Int64(cycleStart.timeIntervalSince1970 * 1_000)
        let leafRollout = fixture.directory.appendingPathComponent("nested-leaf.jsonl")
        try writeTokenRollout(
            at: leafRollout,
            cycleStart: cycleStart,
            inputTokens: 80,
            outputTokens: 20
        )
        try insertThread(
            into: fixture,
            id: "inactive-user-root",
            rolloutPath: fixture.directory.appendingPathComponent("inactive-root.jsonl").path,
            source: "vscode",
            threadSource: "user",
            title: "祖先用户根",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt - 2
        )
        try insertThread(
            into: fixture,
            id: "inactive-middle-child",
            rolloutPath: fixture.directory.appendingPathComponent("inactive-middle.jsonl").path,
            source: childSource(parentID: "inactive-user-root"),
            threadSource: "subagent",
            title: "middle",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt - 1
        )
        try insertThread(
            into: fixture,
            id: "active-nested-child",
            rolloutPath: leafRollout.path,
            source: childSource(parentID: "inactive-middle-child"),
            threadSource: "subagent",
            title: "leaf",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt + 1
        )

        let result = try await TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        ).fetchTasks(quota: quota(cycleStart: cycleStart))
        let root = try XCTUnwrap(result.tasks.first)

        XCTAssertEqual(root.tokenCount, 100)
        XCTAssertEqual(root.subtaskCount, 1)
        assertCompleteResult(
            result,
            userIDs: ["inactive-user-root"],
            automationIDs: [],
            backgroundCount: 0,
            totalTokens: 100,
            totalAPICostUSD: 0.000_1
        )
    }

    func testInactiveGuardianInAncestorChainResolvesActiveChildToRoot() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let updatedAt = Int64(cycleStart.timeIntervalSince1970 * 1_000)
        let rootID = "019fb2a6-a1d7-75a0-97e0-fbb93e00bf01"
        let guardianID = "019fb2a6-a1d7-75a0-97e0-fbb93e00bf02"
        let childID = "019fb2a6-a1d7-75a0-97e0-fbb93e00bf03"
        let guardianRollout = fixture.directory.appendingPathComponent("inactive-guardian.jsonl")
        let childRollout = fixture.directory.appendingPathComponent("guardian-child.jsonl")
        try writeRollout(
            [
                sessionMetaLine(
                    mainID: rootID,
                    guardianID: guardianID,
                    parentID: "guardian-review"
                )
            ],
            to: guardianRollout
        )
        try writeTokenRollout(
            at: childRollout,
            cycleStart: cycleStart,
            inputTokens: 70,
            outputTokens: 30
        )
        try insertThread(
            into: fixture,
            id: rootID,
            rolloutPath: fixture.directory.appendingPathComponent("guardian-root.jsonl").path,
            source: "vscode",
            threadSource: "user",
            title: "Guardian根对话",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt - 2
        )
        try insertThread(
            into: fixture,
            id: guardianID,
            rolloutPath: guardianRollout.path,
            source: guardianSource(),
            threadSource: "subagent",
            title: "guardian",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt - 1
        )
        try insertThread(
            into: fixture,
            id: childID,
            rolloutPath: childRollout.path,
            source: childSource(parentID: guardianID),
            threadSource: "subagent",
            title: "child",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt + 1
        )

        let result = try await TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        ).fetchTasks(quota: quota(cycleStart: cycleStart))

        XCTAssertEqual(result.tasks.first?.tokenCount, 100)
        XCTAssertEqual(result.tasks.first?.subtaskCount, 1)
        assertCompleteResult(
            result,
            userIDs: [rootID],
            automationIDs: [],
            backgroundCount: 0,
            totalTokens: 100,
            totalAPICostUSD: 0.000_1
        )
    }

    func testGuardiansResolveUserAndAutomationRootsButAmbiguityStaysBackground() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let updatedAt = Int64(cycleStart.timeIntervalSince1970 * 1_000)
        let userID = "019fb2a6-a1d7-75a0-97e0-fbb93e00bf10"
        let automationID = "019fb2a6-a1d7-75a0-97e0-fbb93e00bf11"
        let userGuardianID = "019fb2a6-a1d7-75a0-97e0-fbb93e00bf12"
        let automationGuardianID = "019fb2a6-a1d7-75a0-97e0-fbb93e00bf13"
        let ambiguousGuardianID = "019fb2a6-a1d7-75a0-97e0-fbb93e00bf14"
        try insertThread(
            into: fixture,
            id: userID,
            rolloutPath: fixture.directory.appendingPathComponent("inactive-user.jsonl").path,
            source: "vscode",
            threadSource: "user",
            title: "",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt - 2
        )
        try insertThread(
            into: fixture,
            id: automationID,
            rolloutPath: fixture.directory.appendingPathComponent("inactive-automation.jsonl").path,
            source: "exec",
            threadSource: "automation",
            title: "新对话",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt - 1
        )
        let guardianRows: [(
            id: String,
            lines: [String],
            inputTokens: Int64,
            outputTokens: Int64
        )] = [
            (
                userGuardianID,
                [
                    sessionMetaLine(
                        mainID: userID,
                        guardianID: userGuardianID,
                        parentID: "user-review"
                    )
                ],
                80,
                20
            ),
            (
                automationGuardianID,
                [
                    sessionMetaLine(
                        mainID: automationID,
                        guardianID: automationGuardianID,
                        parentID: "automation-review"
                    )
                ],
                150,
                50
            ),
            (
                ambiguousGuardianID,
                [
                    referenceLine(
                        at: cycleStart.addingTimeInterval(5),
                        threadIDs: [userID, automationID]
                    )
                ],
                225,
                75
            )
        ]
        for (index, guardian) in guardianRows.enumerated() {
            let rollout = fixture.directory.appendingPathComponent("\(guardian.id).jsonl")
            try writeRollout(
                guardian.lines + [
                    tokenLine(
                        at: cycleStart.addingTimeInterval(10),
                        inputTokens: guardian.inputTokens,
                        outputTokens: guardian.outputTokens
                    )
                ],
                to: rollout
            )
            try insertThread(
                into: fixture,
                id: guardian.id,
                rolloutPath: rollout.path,
                source: guardianSource(),
                threadSource: "subagent",
                title: "guardian",
                firstMessage: "",
                updatedAtMilliseconds: updatedAt + Int64(index + 1)
            )
        }

        let result = try await TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        ).fetchTasks(quota: quota(cycleStart: cycleStart))

        XCTAssertEqual(result.tasks.first?.title, "未命名对话")
        XCTAssertEqual(result.tasks.first?.tokenCount, 100)
        XCTAssertEqual(result.automationTasks.first?.title, "自动任务")
        XCTAssertEqual(result.automationTasks.first?.tokenCount, 200)
        XCTAssertEqual(result.backgroundTokenCount, 300)
        assertCompleteResult(
            result,
            userIDs: [userID],
            automationIDs: [automationID],
            backgroundCount: 1,
            totalTokens: 600,
            totalAPICostUSD: 0.000_6
        )
    }

    func testBadRootRolloutPathsRemainVisibleAndDoNotSuppressValidUsage() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let updatedAt = Int64(cycleStart.timeIntervalSince1970 * 1_000)
        let nonRegularURL = fixture.directory.appendingPathComponent("rollout-directory")
        try FileManager.default.createDirectory(
            at: nonRegularURL,
            withIntermediateDirectories: false
        )
        let unreadableURL = fixture.directory.appendingPathComponent("unreadable.jsonl")
        try writeTokenRollout(
            at: unreadableURL,
            cycleStart: cycleStart,
            inputTokens: 900,
            outputTokens: 99
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: unreadableURL.path
        )
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: unreadableURL.path
            )
        }
        let validURL = fixture.directory.appendingPathComponent("valid.jsonl")
        try writeTokenRollout(
            at: validURL,
            cycleStart: cycleStart,
            inputTokens: 75,
            outputTokens: 25
        )
        let paths: [(id: String, path: String?)] = [
            ("empty-path-root", ""),
            ("null-path-root", nil),
            (
                "missing-path-root",
                fixture.directory.appendingPathComponent("missing.jsonl").path
            ),
            ("directory-path-root", nonRegularURL.path),
            ("unreadable-path-root", unreadableURL.path),
            ("valid-path-root", validURL.path)
        ]
        for (index, row) in paths.enumerated() {
            try insertThread(
                into: fixture,
                id: row.id,
                rolloutPath: row.path,
                source: "vscode",
                threadSource: "user",
                title: row.id,
                firstMessage: "",
                updatedAtMilliseconds: updatedAt + Int64(index + 1)
            )
        }

        guard let result = await fetchWithoutSuppressingFailure(
            fixture: fixture,
            cycleStart: cycleStart
        ) else {
            return
        }

        for id in paths.dropLast().map(\.id) {
            XCTAssertEqual(result.tasks.first { $0.id == id }?.tokenCount, 0, id)
        }
        XCTAssertEqual(result.tasks.first { $0.id == "valid-path-root" }?.tokenCount, 100)
        assertCompleteResult(
            result,
            userIDs: Set(paths.map(\.id)),
            automationIDs: [],
            backgroundCount: 0,
            totalTokens: 100,
            totalAPICostUSD: 0.000_1
        )
    }

    func testUnreadableAndDamagedGuardiansSendTheirChainsToBackground() async throws {
        let fixture = try makeFixture()
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let updatedAt = Int64(cycleStart.timeIntervalSince1970 * 1_000)
        let validRootID = "valid-independent-root"
        let validRootRollout = fixture.directory.appendingPathComponent("valid-root.jsonl")
        try writeTokenRollout(
            at: validRootRollout,
            cycleStart: cycleStart,
            inputTokens: 80,
            outputTokens: 20
        )
        try insertThread(
            into: fixture,
            id: validRootID,
            rolloutPath: validRootRollout.path,
            source: "vscode",
            threadSource: "user",
            title: "有效根对话",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt + 1
        )

        let unreadableGuardianID = "019fb2a6-a1d7-75a0-97e0-fbb93e00bf20"
        let unreadableGuardianURL = fixture.directory.appendingPathComponent("unreadable-guardian.jsonl")
        try writeRollout(
            [
                sessionMetaLine(
                    mainID: "019fb2a6-a1d7-75a0-97e0-fbb93e00bf21",
                    guardianID: unreadableGuardianID,
                    parentID: "unreadable-review"
                )
            ],
            to: unreadableGuardianURL
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: unreadableGuardianURL.path
        )
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: unreadableGuardianURL.path
            )
        }

        let damagedGuardianID = "019fb2a6-a1d7-75a0-97e0-fbb93e00bf22"
        let damagedGuardianURL = fixture.directory.appendingPathComponent("damaged-guardian")
        try FileManager.default.createDirectory(
            at: damagedGuardianURL,
            withIntermediateDirectories: false
        )
        let guardianFixtures: [(
            guardianID: String,
            guardianPath: String,
            childID: String,
            childTokens: (Int64, Int64)
        )] = [
            (
                unreadableGuardianID,
                unreadableGuardianURL.path,
                "unreadable-guardian-child",
                (40, 10)
            ),
            (
                damagedGuardianID,
                damagedGuardianURL.path,
                "damaged-guardian-child",
                (45, 15)
            )
        ]
        for (index, item) in guardianFixtures.enumerated() {
            try insertThread(
                into: fixture,
                id: item.guardianID,
                rolloutPath: item.guardianPath,
                source: guardianSource(),
                threadSource: "subagent",
                title: "guardian",
                firstMessage: "",
                updatedAtMilliseconds: updatedAt + Int64(index * 2 + 2)
            )
            let childRollout = fixture.directory.appendingPathComponent("\(item.childID).jsonl")
            try writeTokenRollout(
                at: childRollout,
                cycleStart: cycleStart,
                inputTokens: item.childTokens.0,
                outputTokens: item.childTokens.1
            )
            try insertThread(
                into: fixture,
                id: item.childID,
                rolloutPath: childRollout.path,
                source: childSource(parentID: item.guardianID),
                threadSource: "subagent",
                title: "child",
                firstMessage: "",
                updatedAtMilliseconds: updatedAt + Int64(index * 2 + 3)
            )
        }

        guard let result = await fetchWithoutSuppressingFailure(
            fixture: fixture,
            cycleStart: cycleStart
        ) else {
            return
        }

        XCTAssertEqual(result.tasks.first?.tokenCount, 100)
        XCTAssertEqual(result.backgroundTokenCount, 110)
        assertCompleteResult(
            result,
            userIDs: [validRootID],
            automationIDs: [],
            backgroundCount: 4,
            totalTokens: 210,
            totalAPICostUSD: 0.000_21
        )
    }

    func testLegacySchemaWithoutThreadSourceAggregatesRootAndChild() async throws {
        let fixture = try makeFixture(includesThreadSource: false)
        let cycleStart = Date(timeIntervalSince1970: 2_000_000_000)
        let updatedAt = Int64(cycleStart.timeIntervalSince1970 * 1_000)
        let rootRollout = fixture.directory.appendingPathComponent("legacy-root.jsonl")
        let childRollout = fixture.directory.appendingPathComponent("legacy-child.jsonl")
        try writeTokenRollout(
            at: rootRollout,
            cycleStart: cycleStart,
            inputTokens: 80,
            outputTokens: 20
        )
        try writeTokenRollout(
            at: childRollout,
            cycleStart: cycleStart,
            inputTokens: 35,
            outputTokens: 15
        )
        try insertThread(
            into: fixture,
            id: "legacy-root",
            rolloutPath: rootRollout.path,
            source: "vscode",
            title: "旧版根对话",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt + 1
        )
        try insertThread(
            into: fixture,
            id: "legacy-child",
            rolloutPath: childRollout.path,
            source: childSource(parentID: "legacy-root"),
            title: "child",
            firstMessage: "",
            updatedAtMilliseconds: updatedAt + 2
        )

        let result = try await TaskQuotaStore(
            databaseURL: fixture.databaseURL,
            titleCacheURL: fixture.cacheURL
        ).fetchTasks(quota: quota(cycleStart: cycleStart))

        XCTAssertEqual(result.tasks.first?.tokenCount, 150)
        XCTAssertEqual(result.tasks.first?.subtaskCount, 1)
        assertCompleteResult(
            result,
            userIDs: ["legacy-root"],
            automationIDs: [],
            backgroundCount: 0,
            totalTokens: 150,
            totalAPICostUSD: 0.000_15
        )
    }
}
