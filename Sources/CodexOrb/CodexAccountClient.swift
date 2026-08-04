import CodexOrbCore
import Foundation

struct CodexAccountClient: Sendable {
    enum ClientError: LocalizedError {
        case binaryNotFound
        case serverClosed
        case timedOut
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "未找到本机 Codex，可先打开 ChatGPT / Codex。"
            case .serverClosed:
                return "Codex 额度接口提前关闭。"
            case .timedOut:
                return "读取官方额度超时，请稍后重试。"
            case let .launchFailed(message):
                return "无法启动 Codex 额度接口：\(message)"
            }
        }
    }

    func fetch() async throws -> AccountSnapshot {
        guard let executableURL = locateCodexBinary() else {
            throw ClientError.binaryNotFound
        }

        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw ClientError.launchFailed(error.localizedDescription)
        }

        do {
            try write(
                [
                    "method": "initialize",
                    "id": 0,
                    "params": [
                        "clientInfo": [
                            "name": "codex_orb",
                            "title": "Codex Quota Orb",
                            "version": "1.0.0"
                        ],
                        "capabilities": [
                            "optOutNotificationMethods": [
                                "remoteControl/status/changed"
                            ]
                        ]
                    ]
                ],
                to: standardInput.fileHandleForWriting
            )

            let snapshot = try await withThrowingTaskGroup(of: AccountSnapshot.self) { group in
                group.addTask {
                    var collector = AccountLineCollector()
                    for try await line in standardOutput.fileHandleForReading.bytes.lines {
                        let data = Data(line.utf8)
                        switch try collector.ingest(data) {
                        case .none:
                            continue
                        case .requestAccountData:
                            try write(
                                ["method": "initialized", "params": [:] as [String: String]],
                                to: standardInput.fileHandleForWriting
                            )
                            try write(
                                ["method": "account/rateLimits/read", "id": 7, "params": [:] as [String: String]],
                                to: standardInput.fileHandleForWriting
                            )
                            try write(
                                ["method": "account/usage/read", "id": 9, "params": [:] as [String: String]],
                                to: standardInput.fileHandleForWriting
                            )
                        case let .complete(rateLimitLine, usageLine):
                            return try AccountResponseParser.parse(
                                rateLimitLine: rateLimitLine,
                                usageLine: usageLine
                            )
                        }
                    }
                    throw ClientError.serverClosed
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    throw ClientError.timedOut
                }

                guard let first = try await group.next() else {
                    throw ClientError.serverClosed
                }
                group.cancelAll()
                return first
            }

            if process.isRunning {
                process.terminate()
            }
            return snapshot
        } catch {
            if process.isRunning {
                process.terminate()
            }
            throw error
        }
    }

    private func locateCodexBinary() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            home.appendingPathComponent(".npm-global/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private func write(
        _ object: [String: Any],
        to handle: FileHandle
    ) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }
}
