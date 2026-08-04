import XCTest
@testable import CodexOrbCore

final class ThreadClassificationTests: XCTestCase {
    func testClassifiesThreadIdentityDecisionTable() {
        let cases: [(threadSource: String?, source: String?, expected: ThreadRelation)] = [
            ("user", "vscode", .main),
            ("user", #"{"subagent":{"thread_spawn":{"parent_thread_id":"root"}}}"#, .background),
            ("automation", "vscode", .automation),
            ("automation", #"{"subagent":{"other":"guardian"}}"#, .background),
            ("subagent", #"{"subagent":{"thread_spawn":{"parent_thread_id":" root "}}}"#, .child(parentID: "root")),
            ("subagent", #"{"subagent":{"other":"guardian"}}"#, .guardian(referencedRootIDs: [])),
            ("subagent", "vscode", .background),
            ("composer_link", "vscode", .background),
            ("memory_consolidation", "exec", .background),
            ("future_feature", "vscode", .background),
            (nil, "vscode", .main),
            (nil, "cli", .main),
            (nil, "exec", .main),
            (nil, "mcp", .main),
            (nil, #"{"subagent":{"thread_spawn":{"parent_thread_id":"root"}}}"#, .child(parentID: "root")),
            (nil, #"{"subagent":{"other":"guardian"}}"#, .guardian(referencedRootIDs: [])),
            (nil, nil, .background),
            (nil, "unknown", .background)
        ]

        for testCase in cases {
            XCTAssertEqual(
                ThreadSourceParser.relation(
                    from: testCase.source,
                    threadSource: testCase.threadSource
                ),
                testCase.expected,
                "thread_source=\(testCase.threadSource ?? "nil"), source=\(testCase.source ?? "nil")"
            )
        }
    }

    func testClassifiesEmptyParentIDAsBackground() {
        XCTAssertEqual(
            ThreadSourceParser.relation(
                from: #"{"subagent":{"thread_spawn":{"parent_thread_id":"   "}}}"#,
                threadSource: "subagent"
            ),
            .background
        )
    }

    func testClassifiesMalformedSubagentPayloadAsBackground() {
        XCTAssertEqual(
            ThreadSourceParser.relation(
                from: #"{"subagent":{"thread_spawn":{}}}"#,
                threadSource: "subagent"
            ),
            .background
        )
    }

    func testClassifiesUnknownInternalSubagentAsBackgroundAcrossTypeConflicts() {
        let source = #"{"subagent":{"other":"unknown"}}"#

        XCTAssertEqual(
            ThreadSourceParser.relation(from: source, threadSource: "subagent"),
            .background
        )
        XCTAssertEqual(
            ThreadSourceParser.relation(from: source, threadSource: "user"),
            .background
        )
        XCTAssertEqual(
            ThreadSourceParser.relation(from: source, threadSource: "automation"),
            .background
        )
    }

    func testConflictingStructuredSubagentRelationsStayBackground() {
        let source = #"{"subagent":{"thread_spawn":{"parent_thread_id":"root"},"other":"guardian"}}"#

        XCTAssertEqual(
            ThreadSourceParser.relation(from: source, threadSource: "subagent"),
            .background
        )
    }

    func testNormalizesThreadSourceAndUsesLegacyRulesForBlankValues() {
        XCTAssertEqual(
            ThreadSourceParser.relation(from: "vscode", threadSource: " USER "),
            .main
        )
        XCTAssertEqual(
            ThreadSourceParser.relation(from: "cli", threadSource: " AuToMaTiOn "),
            .automation
        )
        XCTAssertEqual(
            ThreadSourceParser.relation(
                from: #"{"subagent":{"thread_spawn":{"parent_thread_id":"root"}}}"#,
                threadSource: " SUBAGENT "
            ),
            .child(parentID: "root")
        )

        for threadSource in ["", " \n\t "] {
            XCTAssertEqual(
                ThreadSourceParser.relation(from: "mcp", threadSource: threadSource),
                .main
            )
            XCTAssertEqual(
                ThreadSourceParser.relation(from: nil, threadSource: threadSource),
                .background
            )
        }
    }

    func testLegacyOverloadMatchesAnAbsentThreadSource() {
        for source in [
            "vscode",
            "unknown",
            #"{"subagent":{"thread_spawn":{"parent_thread_id":"root"}}}"#
        ] {
            XCTAssertEqual(
                ThreadSourceParser.relation(from: source),
                ThreadSourceParser.relation(from: source, threadSource: nil)
            )
        }
    }
}
