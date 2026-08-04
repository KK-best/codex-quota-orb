import Foundation

public enum AccountLineAction: Equatable, Sendable {
    case none
    case requestAccountData
    case complete(rateLimitLine: Data, usageLine: Data)
}

public struct AccountLineCollector: Sendable {
    private var rateLimitLine: Data?
    private var usageLine: Data?

    public init() {}

    public mutating func ingest(_ line: Data) throws -> AccountLineAction {
        guard
            let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
            let id = object["id"] as? Int
        else {
            return .none
        }

        switch id {
        case 0:
            return .requestAccountData
        case 7:
            rateLimitLine = line
        case 9:
            usageLine = line
        default:
            return .none
        }

        if let rateLimitLine, let usageLine {
            return .complete(
                rateLimitLine: rateLimitLine,
                usageLine: usageLine
            )
        }
        return .none
    }
}
