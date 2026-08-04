import CodexOrbCore
import Foundation

struct TaskQuotaStore: Sendable {
    private let databaseURLOverride: URL?
    private let titleCacheURLOverride: URL?

    init(
        databaseURL: URL? = nil,
        titleCacheURL: URL? = nil
    ) {
        databaseURLOverride = databaseURL
        titleCacheURLOverride = titleCacheURL
    }

    enum StoreError: LocalizedError {
        case databaseNotFound
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .databaseNotFound:
                return "未找到 Codex 对话索引。"
            case let .queryFailed(message):
                return "任务额度查询失败：\(message)"
            }
        }
    }

    func fetchTasks(
        quota: QuotaSnapshot
    ) async throws -> TaskAggregationResult {
        try await Task.detached(priority: .utility) {
            try fetchSynchronously(quota: quota)
        }.value
    }

    private func fetchSynchronously(
        quota: QuotaSnapshot
    ) throws -> TaskAggregationResult {
        guard let databaseURL = databaseURLOverride
                ?? locateStateDatabase() else {
            throw StoreError.databaseNotFound
        }

        let cycleStart = quota.resetsAt.addingTimeInterval(
            -TimeInterval(quota.windowDurationMinutes * 60)
        )
        let threadSourceExpression = try threadSourceExpression(
            databaseURL: databaseURL
        )
        let activeRows = try fetchActiveThreadRows(
            databaseURL: databaseURL,
            cycleStart: cycleStart,
            threadSourceExpression: threadSourceExpression
        )

        let ancestorRows = try rowsIncludingAncestors(
            of: activeRows,
            databaseURL: databaseURL,
            threadSourceExpression: threadSourceExpression
        )
        let knownRootIDs = Set(ancestorRows.compactMap { row -> String? in
            switch ThreadSourceParser.relation(
                from: row.source,
                threadSource: row.threadSource
            ) {
            case .main, .automation:
                return row.id
            case .child, .guardian, .background:
                return nil
            }
        })
        let referencesByGuardianID = guardianReferenceCandidates(
            in: ancestorRows,
            knownRootIDs: knownRootIDs
        )
        let referencedRows = try fetchThreadRows(
            databaseURL: databaseURL,
            ids: referencesByGuardianID.values.reduce(into: []) {
                $0.formUnion($1)
            },
            threadSourceExpression: threadSourceExpression
        )
        let confirmedReferencedRoots = referencedRows.filter {
            switch ThreadSourceParser.relation(
                from: $0.source,
                threadSource: $0.threadSource
            ) {
            case .main, .automation:
                return true
            case .child, .guardian, .background:
                return false
            }
        }
        let allRows = Dictionary(
            (ancestorRows + confirmedReferencedRoots).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values.sorted { $0.id < $1.id }
        let rootIDs = Set(allRows.compactMap { row -> String? in
            switch ThreadSourceParser.relation(
                from: row.source,
                threadSource: row.threadSource
            ) {
            case .main, .automation:
                return row.id
            case .child, .guardian, .background:
                return nil
            }
        })

        var records: [ThreadTaskUsage] = []
        let activeIDs = Set(activeRows.map(\.id))
        let cacheURL = titleCacheURL()
        var titleCache = ThreadTitleCache.load(
            from: cacheURL,
            algorithmVersion: ThreadTitleSummarizer.algorithmVersion
        )

        func displayTitle(
            for row: ThreadRow,
            relation: ThreadRelation
        ) -> String {
            switch relation {
            case .main:
                return titleCache.title(for: row.id) {
                    ThreadTitleSummarizer.summarize(
                        title: row.titleText,
                        firstMessage: row.firstUserMessage,
                        cwd: row.cwd
                    )
                }
            case .automation:
                return titleCache.title(for: row.id) {
                    let summary = ThreadTitleSummarizer.summarize(
                        title: row.titleText,
                        firstMessage: row.firstUserMessage,
                        cwd: row.cwd
                    )
                    return summary == "未命名对话" ? "自动任务" : summary
                }
            case .child, .guardian, .background:
                return "子任务"
            }
        }

        for row in allRows {
            let isActiveInCycle = activeIDs.contains(row.id)
            let initialRelation = ThreadSourceParser.relation(
                from: row.source,
                threadSource: row.threadSource
            )
            let relation: ThreadRelation
            if case .guardian = initialRelation {
                relation = .guardian(
                    referencedRootIDs:
                        referencesByGuardianID[row.id, default: []]
                            .intersection(rootIDs)
                )
            } else {
                relation = initialRelation
            }
            let scan: ThreadScanResult
            if isActiveInCycle,
               let rolloutURL = resolvedRolloutURL(row.rolloutPath) {
                scan = (try? taskUsage(
                    at: rolloutURL,
                    cycleStart: cycleStart
                )) ?? .zero
            } else {
                scan = .zero
            }
            let title = displayTitle(for: row, relation: relation)
            records.append(
                ThreadTaskUsage(
                    id: row.id,
                    title: title,
                    projectPath: row.cwd,
                    relation: relation,
                    tokenCount: scan.tokenCount,
                    apiEquivalentCostUSD: scan.apiEquivalentCostUSD,
                    modelLabel: scan.modelLabel,
                    lastActive: scan.lastActive ?? cycleStart,
                    isActiveInCycle: isActiveInCycle
                )
            )
        }
        try? titleCache.save(to: cacheURL)

        return TaskUsageAggregator.aggregate(
            records: records,
            currentUsedPercent: quota.usedPercent
        )
    }

    private func fetchActiveThreadRows(
        databaseURL: URL,
        cycleStart: Date,
        threadSourceExpression: String
    ) throws -> [ThreadRow] {
        let cycleStartMilliseconds = Int64(
            cycleStart.timeIntervalSince1970 * 1_000
        )
        let query = """
        SELECT
            id,
            COALESCE(rollout_path, '') AS rollout_path,
            cwd,
            source,
            \(threadSourceExpression) AS thread_source,
            substr(COALESCE(NULLIF(title, ''), ''), 1, 512) AS title_text,
            substr(
                COALESCE(NULLIF(first_user_message, ''), ''),
                1,
                2048
            ) AS first_user_message
        FROM threads
        WHERE updated_at_ms >= \(cycleStartMilliseconds)
        ORDER BY updated_at_ms ASC;
        """

        return try fetchJSONRows(
            databaseURL: databaseURL,
            query: query,
            as: ThreadRow.self
        )
    }

    private func rowsIncludingAncestors(
        of activeRows: [ThreadRow],
        databaseURL: URL,
        threadSourceExpression: String
    ) throws -> [ThreadRow] {
        var rowsByID = Dictionary(
            activeRows.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var pendingParents = Set(activeRows.compactMap { row -> String? in
            if case let .child(parentID) = ThreadSourceParser.relation(
                from: row.source,
                threadSource: row.threadSource
            ) {
                return parentID
            }
            return nil
        })
        var visited = Set<String>()

        while let parentID = pendingParents.popFirst() {
            guard visited.insert(parentID).inserted else { continue }
            let parent: ThreadRow?
            if let existing = rowsByID[parentID] {
                parent = existing
            } else {
                parent = try fetchThreadRows(
                    databaseURL: databaseURL,
                    ids: [parentID],
                    threadSourceExpression: threadSourceExpression
                ).first
            }
            guard let parent else { continue }
            rowsByID[parent.id] = parent
            if case let .child(grandparentID) = ThreadSourceParser.relation(
                from: parent.source,
                threadSource: parent.threadSource
            ) {
                pendingParents.insert(grandparentID)
            }
        }

        return rowsByID.values.sorted { $0.id < $1.id }
    }

    private func fetchThreadRows(
        databaseURL: URL,
        ids: Set<String>,
        threadSourceExpression: String
    ) throws -> [ThreadRow] {
        guard !ids.isEmpty else { return [] }
        let sortedIDs = ids.sorted()
        var rows: [ThreadRow] = []
        let batchSize = 200
        for start in stride(from: 0, to: sortedIDs.count, by: batchSize) {
            let end = min(start + batchSize, sortedIDs.count)
            let quotedIDs = sortedIDs[start..<end]
                .map(sqlStringLiteral)
                .joined(separator: ", ")
            let query = """
            SELECT
                id,
                COALESCE(rollout_path, '') AS rollout_path,
                cwd,
                source,
                \(threadSourceExpression) AS thread_source,
                substr(COALESCE(NULLIF(title, ''), ''), 1, 512) AS title_text,
                substr(
                    COALESCE(NULLIF(first_user_message, ''), ''),
                    1,
                    2048
                ) AS first_user_message
            FROM threads
            WHERE id IN (\(quotedIDs));
            """

            rows.append(
                contentsOf: try fetchJSONRows(
                    databaseURL: databaseURL,
                    query: query,
                    as: ThreadRow.self
                )
            )
        }
        return rows
    }

    private func fetchJSONRows<Row: Decodable>(
        databaseURL: URL,
        query: String,
        as type: Row.Type
    ) throws -> [Row] {

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        let outputURL = temporaryDirectory.appendingPathComponent(
            "codex-orb-sqlite-output-\(UUID().uuidString)"
        )
        let errorURL = temporaryDirectory.appendingPathComponent(
            "codex-orb-sqlite-error-\(UUID().uuidString)"
        )
        guard fileManager.createFile(atPath: outputURL.path, contents: nil),
              fileManager.createFile(atPath: errorURL.path, contents: nil)
        else {
            throw StoreError.queryFailed("无法创建 SQLite 查询临时输出。")
        }
        defer {
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.removeItem(at: errorURL)
        }

        let output = try FileHandle(forWritingTo: outputURL)
        let errorOutput = try FileHandle(forWritingTo: errorURL)
        defer {
            try? output.close()
            try? errorOutput.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            "-json",
            databaseURL.path,
            query
        ]
        process.standardOutput = output
        process.standardError = errorOutput

        try process.run()
        process.waitUntilExit()
        try output.close()
        try errorOutput.close()

        let data = try Data(contentsOf: outputURL)
        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: try Data(contentsOf: errorURL),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw StoreError.queryFailed(message)
        }
        guard !String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            return []
        }

        return try JSONDecoder().decode([Row].self, from: data)
    }

    private func threadSourceExpression(databaseURL: URL) throws -> String {
        let query = """
        SELECT EXISTS(
            SELECT 1
            FROM pragma_table_info('threads')
            WHERE name = 'thread_source'
        ) AS has_thread_source;
        """
        let probe = try fetchJSONRows(
            databaseURL: databaseURL,
            query: query,
            as: ThreadSchemaProbe.self
        ).first
        return probe?.hasThreadSource == 1 ? "thread_source" : "NULL"
    }

    private func taskUsage(
        at url: URL,
        cycleStart: Date
    ) throws -> ThreadScanResult {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        var rawEvents: [RawQuotaEvent] = []
        var modelEvents: [ModelEvent] = []
        var foundBaselineEvent = false
        var foundPriorModel = false
        try ReverseJSONLLineReader.readLines(at: url) { line in
            guard let timestamp = lineTimestamp(
                line,
                formatter: formatter
            ) else {
                return false
            }

            let isTokenEvent = line.range(
                of: Data(#""type":"token_count""#.utf8)
            ) != nil
            let isTurnContext = line.range(
                of: Data(#""type":"turn_context""#.utf8)
            ) != nil
            if timestamp < cycleStart {
                if isTokenEvent,
                   let event = decodeQuotaEvent(
                    line,
                    timestamp: timestamp
                   ) {
                    rawEvents.append(event)
                    foundBaselineEvent = true
                }
                if isTurnContext,
                   let event = decodeModelEvent(
                    line,
                    timestamp: timestamp
                   ) {
                    modelEvents.append(event)
                    foundPriorModel = true
                }
                return foundBaselineEvent && foundPriorModel
            }

            if isTokenEvent,
               let event = decodeQuotaEvent(
                line,
                timestamp: timestamp
               ) {
                rawEvents.append(event)
            }
            if isTurnContext,
               let event = decodeModelEvent(
                line,
                timestamp: timestamp
               ) {
                modelEvents.append(event)
            }
            return false
        }

        let orderedModels = modelEvents.sorted {
            $0.timestamp < $1.timestamp
        }
        var modelIndex = 0
        var currentModel = ""
        var observedModels = Set<String>()
        var previousUsage: TokenUsageBreakdown?
        var apiCost = 0.0
        var hasPricedUsage = false
        var tokenCount: Int64 = 0
        var lastActive: Date?
        for event in rawEvents.reversed() {
            while modelIndex < orderedModels.count,
                  orderedModels[modelIndex].timestamp <= event.timestamp {
                currentModel = orderedModels[modelIndex].model
                modelIndex += 1
            }

            if event.timestamp < cycleStart {
                previousUsage = event.totalUsage
                continue
            }

            let incrementalUsage: TokenUsageBreakdown
            if let previousUsage {
                incrementalUsage = event.totalUsage - previousUsage
            } else {
                incrementalUsage = event.totalUsage
            }
            let tokenWeight = incrementalUsage.inputTokens
                + incrementalUsage.outputTokens
            tokenCount += tokenWeight
            lastActive = max(lastActive ?? event.timestamp, event.timestamp)

            if !currentModel.isEmpty {
                observedModels.insert(currentModel)
                if let cost = APICostEstimator.estimateUSD(
                    usage: incrementalUsage,
                    model: currentModel,
                    usesLongContextPricing:
                        APICostEstimator.usesLongContextPricing(
                            inputTokens: event.lastUsage.inputTokens
                        )
                ) {
                    apiCost += cost
                    hasPricedUsage = true
                }
            }

            previousUsage = event.totalUsage
        }

        let modelLabel: String
        if observedModels.count == 1 {
            modelLabel = observedModels.first ?? ""
        } else if observedModels.count > 1 {
            modelLabel = "\(observedModels.count) 种模型"
        } else {
            modelLabel = ""
        }
        return ThreadScanResult(
            apiEquivalentCostUSD: hasPricedUsage ? apiCost : nil,
            modelLabel: modelLabel,
            tokenCount: tokenCount,
            lastActive: lastActive
        )
    }

    private func guardianReferenceCandidates(
        in structurallyIncludedRows: [ThreadRow],
        knownRootIDs: Set<String>
    ) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for row in structurallyIncludedRows {
            guard case .guardian = ThreadSourceParser.relation(
                from: row.source,
                threadSource: row.threadSource
            ) else {
                continue
            }
            guard let rolloutURL = resolvedRolloutURL(row.rolloutPath) else {
                result[row.id] = []
                continue
            }
            var knownRootScanner = RolloutReferenceScanner(
                candidates: knownRootIDs
            )
            var structuredSessionIDs = Set<String>()
            var fallbackDiscoveredIDs = Set<String>()
            do {
                try ReverseJSONLLineReader.readLines(at: rolloutURL) { line in
                    if let sessionID = guardianSessionID(in: line) {
                        structuredSessionIDs.insert(sessionID)
                        return false
                    }
                    guard let reviewText = guardianReviewText(in: line) else {
                        return false
                    }
                    knownRootScanner.consume(reviewText)
                    fallbackDiscoveredIDs.formUnion(
                        uuidCandidates(in: reviewText)
                    )
                    return false
                }
            } catch {
                result[row.id] = []
                continue
            }
            if structuredSessionIDs.isEmpty {
                result[row.id] = knownRootScanner.referencedIDs
                    .union(fallbackDiscoveredIDs)
            } else {
                result[row.id] = structuredSessionIDs
            }
        }
        return result
    }

    private func guardianSessionID(in data: Data) -> String? {
        guard data.range(
            of: Data(#""type":"session_meta""#.utf8)
        ) != nil,
        let envelope = try? JSONDecoder().decode(
            GuardianSessionMetaEnvelope.self,
            from: data
        ),
        envelope.type == "session_meta",
        let sessionID = envelope.payload.sessionID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
        !sessionID.isEmpty else {
            return nil
        }
        return sessionID
    }

    private func guardianReviewText(in data: Data) -> Data? {
        guard data.range(
            of: Data(#""type":"review""#.utf8)
        ) != nil,
        let envelope = try? JSONDecoder().decode(
            GuardianReviewEnvelope.self,
            from: data
        ),
        envelope.type == "event_msg",
        envelope.payload.type == "review",
        let text = envelope.payload.text,
        !text.isEmpty else {
            return nil
        }
        return Data(text.utf8)
    }

    private func uuidCandidates(in data: Data) -> Set<String> {
        let bytes = [UInt8](data)
        let uuidLength = 36
        guard bytes.count >= uuidLength else { return [] }

        var result = Set<String>()
        var index = 0
        while index <= bytes.count - uuidLength {
            guard isUUID(bytes, startingAt: index) else {
                index += 1
                continue
            }
            let previousIsHex = index > 0 && isASCIIHex(bytes[index - 1])
            let followingIndex = index + uuidLength
            let followingIsHex = followingIndex < bytes.count
                && isASCIIHex(bytes[followingIndex])
            guard !previousIsHex, !followingIsHex else {
                index += 1
                continue
            }
            result.insert(
                String(
                    decoding: bytes[index..<followingIndex],
                    as: UTF8.self
                )
            )
            index = followingIndex
        }
        return result
    }

    private func isUUID(
        _ bytes: [UInt8],
        startingAt start: Int
    ) -> Bool {
        for offset in 0..<36 {
            let byte = bytes[start + offset]
            switch offset {
            case 8, 13, 18, 23:
                guard byte == 45 else { return false }
            default:
                guard isASCIIHex(byte) else { return false }
            }
        }
        return true
    }

    private func isASCIIHex(_ byte: UInt8) -> Bool {
        switch byte {
        case 48...57, 65...70, 97...102:
            return true
        default:
            return false
        }
    }

    private func lineTimestamp(
        _ line: Data,
        formatter: ISO8601DateFormatter
    ) -> Date? {
        let prefix = String(decoding: line.prefix(80), as: UTF8.self)
        let marker = #""timestamp":""#
        guard let markerRange = prefix.range(of: marker) else {
            return nil
        }
        let remainder = prefix[markerRange.upperBound...]
        guard let quote = remainder.firstIndex(of: "\"") else {
            return nil
        }
        return formatter.date(from: String(remainder[..<quote]))
    }

    private func decodeQuotaEvent(
        _ line: Data,
        timestamp: Date
    ) -> RawQuotaEvent? {
        guard let envelope = try? JSONDecoder().decode(
            TokenCountEnvelope.self,
            from: line
        ),
        envelope.payload.type == "token_count",
        let info = envelope.payload.info,
        info.totalTokenUsage != nil
        else {
            return nil
        }

        return RawQuotaEvent(
            timestamp: timestamp,
            totalUsage: TokenUsageBreakdown(
                inputTokens: info.totalTokenUsage?.inputTokens ?? 0,
                cachedInputTokens:
                    info.totalTokenUsage?.cachedInputTokens ?? 0,
                cacheWriteInputTokens:
                    info.totalTokenUsage?.cacheWriteInputTokens ?? 0,
                outputTokens: info.totalTokenUsage?.outputTokens ?? 0
            ),
            lastUsage: TokenUsageBreakdown(
                inputTokens: info.lastTokenUsage?.inputTokens ?? 0,
                cachedInputTokens:
                    info.lastTokenUsage?.cachedInputTokens ?? 0,
                cacheWriteInputTokens:
                    info.lastTokenUsage?.cacheWriteInputTokens ?? 0,
                outputTokens: info.lastTokenUsage?.outputTokens ?? 0
            )
        )
    }

    private func decodeModelEvent(
        _ line: Data,
        timestamp: Date
    ) -> ModelEvent? {
        guard let model = RolloutEventParser.model(from: line) else {
            return nil
        }
        return ModelEvent(
            timestamp: timestamp,
            model: model
        )
    }

    private func resolvedRolloutURL(_ path: String) -> URL? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let candidate = URL(fileURLWithPath: trimmedPath)
        if isReadableRegularFile(candidate) {
            return candidate
        }

        let archived = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/archived_sessions")
            .appendingPathComponent(candidate.lastPathComponent)
        return isReadableRegularFile(archived) ? archived : nil
    }

    private func isReadableRegularFile(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
            && fileManager.isReadableFile(atPath: url.path)
    }

    private func locateStateDatabase() -> URL? {
        let codexHome = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return files
            .filter {
                $0.lastPathComponent.hasPrefix("state_")
                    && $0.pathExtension == "sqlite"
            }
            .max {
                stateVersion($0) < stateVersion($1)
            }
    }

    private func titleCacheURL() -> URL {
        if let titleCacheURLOverride {
            return titleCacheURLOverride
        }
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("CodexQuotaOrb", isDirectory: true)
            .appendingPathComponent("thread-titles.json")
    }

    private func stateVersion(_ url: URL) -> Int {
        Int(
            url.deletingPathExtension()
                .lastPathComponent
                .replacingOccurrences(of: "state_", with: "")
        ) ?? 0
    }

    private func sqlStringLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

private struct ThreadRow: Decodable {
    let id: String
    let rolloutPath: String
    let cwd: String
    let source: String?
    let threadSource: String?
    let titleText: String
    let firstUserMessage: String

    enum CodingKeys: String, CodingKey {
        case id, cwd, source
        case rolloutPath = "rollout_path"
        case threadSource = "thread_source"
        case titleText = "title_text"
        case firstUserMessage = "first_user_message"
    }
}

private struct ThreadSchemaProbe: Decodable {
    let hasThreadSource: Int

    enum CodingKeys: String, CodingKey {
        case hasThreadSource = "has_thread_source"
    }
}

private struct RawQuotaEvent {
    let timestamp: Date
    let totalUsage: TokenUsageBreakdown
    let lastUsage: TokenUsageBreakdown
}

private struct ModelEvent {
    let timestamp: Date
    let model: String
}

private struct ThreadScanResult {
    let apiEquivalentCostUSD: Double?
    let modelLabel: String
    let tokenCount: Int64
    let lastActive: Date?

    static let zero = ThreadScanResult(
        apiEquivalentCostUSD: 0,
        modelLabel: "",
        tokenCount: 0,
        lastActive: nil
    )
}

private struct GuardianSessionMetaEnvelope: Decodable {
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let sessionID: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
        }
    }
}

private struct GuardianReviewEnvelope: Decodable {
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let type: String
        let text: String?
    }
}

private struct TokenCountEnvelope: Decodable {
    let payload: Payload

    struct Payload: Decodable {
        let type: String
        let info: Info?

        enum CodingKeys: String, CodingKey {
            case type
            case info
        }
    }

    struct Info: Decodable {
        let totalTokenUsage: TokenUsage?
        let lastTokenUsage: TokenUsage?

        enum CodingKeys: String, CodingKey {
            case totalTokenUsage = "total_token_usage"
            case lastTokenUsage = "last_token_usage"
        }
    }

    struct TokenUsage: Decodable {
        let inputTokens: Int64
        let cachedInputTokens: Int64
        let cacheWriteInputTokens: Int64
        let outputTokens: Int64

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case cacheWriteInputTokens = "cache_write_input_tokens"
            case outputTokens = "output_tokens"
        }
    }

}
