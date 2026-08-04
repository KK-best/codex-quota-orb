import CodexOrbCore
import Foundation

struct TokenUsageStore: Sendable {
    enum StoreError: LocalizedError {
        case databaseNotFound
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .databaseNotFound:
                return "未找到 Codex 项目索引。"
            case let .queryFailed(message):
                return "项目 Token 查询失败：\(message)"
            }
        }
    }

    func fetchProjects() async throws -> [ProjectUsage] {
        try await Task.detached(priority: .utility) {
            try fetchProjectsSynchronously()
        }.value
    }

    private func fetchProjectsSynchronously() throws -> [ProjectUsage] {
        guard let databaseURL = locateStateDatabase() else {
            throw StoreError.databaseNotFound
        }

        let query = """
        SELECT
            cwd,
            SUM(tokens_used) AS total_tokens,
            COUNT(*) AS session_count,
            MAX(updated_at_ms) AS last_updated_ms
        FROM threads
        WHERE tokens_used > 0 AND cwd <> ''
        GROUP BY cwd
        ORDER BY total_tokens DESC;
        """

        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
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

        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(
                decoding: errorOutput.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw StoreError.queryFailed(message)
        }

        return try ProjectUsageParser.parse(data)
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

    private func stateVersion(_ url: URL) -> Int {
        Int(
            url.deletingPathExtension()
                .lastPathComponent
                .replacingOccurrences(of: "state_", with: "")
        ) ?? 0
    }
}
