import CodexOrbCore
import Foundation

struct ResetPollClient: Sendable {
    private let endpoint = URL(string: "https://codex-reset.com/api/reset-poll")!

    enum ClientError: LocalizedError {
        case invalidResponse
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "重置预测接口返回了无法识别的数据。"
            case let .server(status):
                return "重置预测接口暂时不可用（\(status)）。"
            }
        }
    }

    func fetch() async throws -> ResetProbabilitySnapshot {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.server(httpResponse.statusCode)
        }

        do {
            return try ResetPollParser.parse(data)
        } catch {
            throw ClientError.invalidResponse
        }
    }
}
