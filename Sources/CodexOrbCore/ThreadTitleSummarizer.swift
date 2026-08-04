import Foundation

public enum ThreadTitleSummarizer {
    public static let maximumLength = 8
    public static let algorithmVersion = 4

    private struct SemanticRule {
        let required: [String]
        let output: String
    }

    private struct Candidate {
        let value: String
        let score: Int
        let kindPriority: Int
        let sourcePriority: Int
    }

    private static let semanticRules: [SemanticRule] = [
        SemanticRule(required: ["Codex", "额度"], output: "Codex额度球"),
        SemanticRule(required: ["篮球", "成本"], output: "篮球机成本"),
        SemanticRule(required: ["环境", "机器人"], output: "环境机器人"),
        SemanticRule(required: ["WAIC"], output: "WAIC信息"),
        SemanticRule(required: ["SkyNomad", "成本"], output: "小米车型成本"),
        SemanticRule(required: ["智能驾驶", "排行"], output: "智能驾驶排行"),
        SemanticRule(required: ["image2.0", "工作流"], output: "视频工作流"),
        SemanticRule(required: ["知识框架"], output: "知识框架"),
        SemanticRule(required: ["AI", "黑客松"], output: "AI黑客松"),
        SemanticRule(required: ["新能源汽车", "APP"], output: "汽车产业APP"),
        SemanticRule(required: ["网站", "基座"], output: "网站基座设计"),
        SemanticRule(required: ["社会", "宏观"], output: "社会宏观"),
        SemanticRule(required: ["英雄塔", "资产"], output: "英雄塔资产"),
        SemanticRule(required: ["商业世界", "模拟器"], output: "商业模拟器"),
        SemanticRule(required: ["cangjie", "skill"], output: "仓颉技能"),
        SemanticRule(required: ["agency-agent"], output: "Agent技能"),
        SemanticRule(required: ["医药", "AI", "趋势"], output: "医药AI趋势"),
        SemanticRule(required: ["AI", "产业", "研究"], output: "AI产业研究"),
        SemanticRule(required: ["地平线", "股票"], output: "股票分析")
    ]

    private static let removablePrefixes = [
        "你好", "您好", "哈喽", "嗨", "hello", "hey", "hi",
        "我希望", "我想", "我觉得", "需要你", "帮我", "请你", "请",
        "全面", "详细", "继续", "重新", "关于", "分析",
        "设计", "制作", "构建",
        "收集", "评估", "解释", "重构", "接手", "创建", "拆解", "整理"
    ]

    private static let lowInformationRequestPhrases = [
        "继续处理", "处理一下", "看一下", "搞一下", "弄一下",
        "这件事", "看看", "帮忙", "这个", "那个",
        "处理", "一下", "搞", "弄"
    ]

    private static let placeholderTitles = [
        "新对话", "新任务", "未命名", "未命名对话", "无标题",
        "untitled", "newchat", "newconversation"
    ]

    private static let protectedEntities = [
        "image2.0", "SkyNomad", "GitHub", "Codex", "WAIC", "AI"
    ]

    private static let topicTerms = [
        ("权限安全", "安全"),
        ("数据安全", "安全"),
        ("网络安全", "安全"),
        ("智能驾驶", "智驾"),
        ("视频工作流程", "工作流"),
        ("视频工作流", "工作流"),
        ("工作流程", "工作流"),
        ("工作流", "工作流"),
        ("机器人", "机器人"),
        ("知识框架", "框架"),
        ("成本", "成本"),
        ("安全", "安全"),
        ("排行", "排行"),
        ("趋势", "趋势"),
        ("技能", "技能"),
        ("宏观", "宏观"),
        ("游戏", "游戏"),
        ("额度", "额度"),
        ("项目", "项目"),
        ("信息", "信息")
    ]

    private static let compressionPairs = [
        ("智能驾驶能力", "智能驾驶"),
        ("新能源汽车", "汽车"),
        ("视频工作流程", "视频工作流"),
        ("影响趋势", "趋势"),
        ("商业世界模拟器", "商业模拟器"),
        ("提升思维能力", "")
    ]

    public static func summarize(
        title: String,
        firstMessage: String,
        cwd: String
    ) -> String {
        _ = cwd
        let rawSources = [
            (normalizedSource(title), 1),
            (normalizedSource(firstMessage), 0)
        ]
        let sources: [(source: String, priority: Int)] = rawSources.compactMap {
            let cleaned = removingLowInformationPrefix(from: $0.0)
            guard !cleaned.isEmpty,
                  !isPlaceholder(cleaned) else {
                return nil
            }
            return (cleaned, $0.1)
        }
        guard !sources.isEmpty else { return "未命名对话" }

        var candidates: [Candidate] = []
        for (source, sourcePriority) in sources {
            for rule in semanticRules where rule.required.allSatisfy({
                source.localizedCaseInsensitiveContains($0)
            }) {
                candidates.append(
                    Candidate(
                        value: rule.output,
                        score: 200 + rule.required.count * 10,
                        kindPriority: 2,
                        sourcePriority: sourcePriority
                    )
                )
            }
            if let entityTopic = entityTopicCandidate(source) {
                candidates.append(
                    Candidate(
                        value: entityTopic,
                        score: 220,
                        kindPriority: 1,
                        sourcePriority: sourcePriority
                    )
                )
            }
            let generic = genericCompression(source)
            if !generic.isEmpty {
                candidates.append(
                    Candidate(
                        value: generic,
                        score: 100 + informationSpecificity(of: generic),
                        kindPriority: 0,
                        sourcePriority: sourcePriority
                    )
                )
            }
        }

        let best = candidates.max {
            if $0.score != $1.score {
                return $0.score < $1.score
            }
            if $0.kindPriority != $1.kindPriority {
                return $0.kindPriority < $1.kindPriority
            }
            return $0.sourcePriority < $1.sourcePriority
        }
        return limited(best?.value ?? "未命名对话")
    }

    private static func informationSpecificity(of value: String) -> Int {
        let compact = value.unicodeScalars.reduce(into: "") {
            result, scalar in
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar),
                  !isPunctuation(scalar) else {
                return
            }
            result.unicodeScalars.append(scalar)
        }
        guard !isEntirelyLowInformationRequest(compact[...]) else { return 0 }
        return min(compact.count, maximumLength)
    }

    private static func isEntirelyLowInformationRequest(
        _ remaining: Substring
    ) -> Bool {
        var memo: [String.Index: Bool] = [:]
        return isEntirelyLowInformationRequest(remaining, memo: &memo)
    }

    private static func isEntirelyLowInformationRequest(
        _ remaining: Substring,
        memo: inout [String.Index: Bool]
    ) -> Bool {
        guard !remaining.isEmpty else { return true }
        if let cached = memo[remaining.startIndex] { return cached }
        for phrase in lowInformationRequestPhrases
        where remaining.hasPrefix(phrase) {
            if isEntirelyLowInformationRequest(
                remaining.dropFirst(phrase.count),
                memo: &memo
            ) {
                memo[remaining.startIndex] = true
                return true
            }
        }
        memo[remaining.startIndex] = false
        return false
    }

    static func limited(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var compact = ""
        for (index, scalar) in scalars.enumerated() {
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                continue
            }
            guard !isPunctuation(scalar)
                    || preservesSemanticPeriod(at: index, in: scalars) else {
                continue
            }
            compact.unicodeScalars.append(scalar)
        }
        return String((compact.isEmpty ? "未命名对话" : compact)
            .prefix(maximumLength))
    }

    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "&" {
            return true
        }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation,
                .dashPunctuation,
                .openPunctuation,
                .closePunctuation,
                .initialPunctuation,
                .finalPunctuation,
                .otherPunctuation:
            return true
        default:
            return false
        }
    }

    private static func preservesSemanticPeriod(
        at index: Int,
        in scalars: [Unicode.Scalar]
    ) -> Bool {
        guard scalars[index] == ".",
              index > 0,
              index < scalars.count - 1 else {
            return false
        }
        return isASCIIAlphaNumeric(scalars[index - 1])
            && isASCIIAlphaNumeric(scalars[index + 1])
    }

    private static func isASCIIAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        default:
            return false
        }
    }

    private static func normalizedSource(_ raw: String) -> String {
        for rawLine in raw.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("<") else { continue }
            line = line.replacingOccurrences(
                of: #"^\[\$[^\]]+\]\([^)]+\)\s*"#,
                with: "",
                options: .regularExpression
            )
            line = line.replacingOccurrences(
                of: #"\[([^\]]+)\]\([^)]+\)"#,
                with: "$1",
                options: .regularExpression
            )
            line = line.replacingOccurrences(
                of: #"[`*_#>]"#,
                with: "",
                options: .regularExpression
            )
            line = line.replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            line = line.trimmingCharacters(
                in: .whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "，。！？；：、,!?;:")
                )
            )
            if !line.isEmpty { return line }
        }
        return ""
    }

    private static func removingLowInformationPrefix(
        from source: String
    ) -> String {
        var result = source
        var removedPrefix = true
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(CharacterSet(charactersIn: "，。！？；：、—…"))

        while removedPrefix {
            removedPrefix = false
            for prefix in removablePrefixes {
                guard let range = result.range(
                    of: prefix,
                    options: [.anchored, .caseInsensitive]
                ) else {
                    continue
                }
                let suffix = result[range.upperBound...]
                if prefix.unicodeScalars.allSatisfy(isASCIIAlphaNumeric),
                   let first = suffix.unicodeScalars.first,
                   isASCIIAlphaNumeric(first) {
                    continue
                }
                result.removeSubrange(range)
                result = result.trimmingCharacters(in: separators)
                removedPrefix = true
                break
            }
        }
        return result
    }

    private static func isPlaceholder(_ source: String) -> Bool {
        let compact = source.unicodeScalars.reduce(into: "") { result, scalar in
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar),
                  !isPunctuation(scalar) else {
                return
            }
            result.unicodeScalars.append(scalar)
        }
        return placeholderTitles.contains {
            compact.compare($0, options: .caseInsensitive) == .orderedSame
        }
    }

    private static func entityTopicCandidate(_ source: String) -> String? {
        let entity = protectedEntities.first {
            source.localizedCaseInsensitiveContains($0)
        } ?? firstGenericEntity(in: source)
        guard let entity,
              let topic = topicTerms.first(where: {
                  source.localizedCaseInsensitiveContains($0.0)
              })?.1 else {
            return nil
        }

        let availableTopicLength = maximumLength - entity.count
        guard availableTopicLength > 0 else {
            return limited(entity)
        }
        return entity + String(topic.prefix(availableTopicLength))
    }

    private static func firstGenericEntity(in source: String) -> String? {
        guard let range = source.range(
            of: #"[A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)*"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let entity = String(source[range])
        return entity.count >= 2 ? entity : nil
    }

    private static func genericCompression(_ source: String) -> String {
        var result = removingLowInformationPrefix(from: source)
        for (original, replacement) in compressionPairs {
            result = result.replacingOccurrences(
                of: original,
                with: replacement,
                options: .caseInsensitive
            )
        }
        let firstClause = result.components(
            separatedBy: CharacterSet(charactersIn: "，。！？；：,!?;:")
        ).first ?? result
        return firstClause
    }
}
