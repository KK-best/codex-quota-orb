import Foundation

public struct ThreadTitleCache: Sendable {
    struct Payload: Codable {
        let algorithmVersion: Int
        let titles: [String: String]
    }

    public let algorithmVersion: Int
    public private(set) var titles: [String: String]

    public init(algorithmVersion: Int, titles: [String: String] = [:]) {
        self.algorithmVersion = algorithmVersion
        self.titles = titles.filter {
            !$0.key.isEmpty && !$0.value.isEmpty
                && $0.value.count <= ThreadTitleSummarizer.maximumLength
                && $0.value == ThreadTitleSummarizer.limited($0.value)
        }
    }

    public static func load(
        from url: URL,
        algorithmVersion: Int
    ) -> ThreadTitleCache {
        guard
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            payload.algorithmVersion == algorithmVersion
        else {
            return ThreadTitleCache(algorithmVersion: algorithmVersion)
        }
        return ThreadTitleCache(
            algorithmVersion: algorithmVersion,
            titles: payload.titles
        )
    }

    public mutating func title(
        for threadID: String,
        generate: () -> String
    ) -> String {
        if let cached = titles[threadID] { return cached }
        let generated = ThreadTitleSummarizer.limited(generate())
        titles[threadID] = generated
        return generated
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = Payload(
            algorithmVersion: algorithmVersion,
            titles: titles
        )
        try JSONEncoder().encode(payload).write(to: url, options: .atomic)
    }
}
