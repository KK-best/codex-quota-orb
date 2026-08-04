import Foundation

public struct QuotaFooterDisplay: Equatable, Sendable {
    public let mainTenths: Int
    public let automationTenths: Int
    public let backgroundTenths: Int
    public let officialTenths: Int
    public let hasUnreconstructedQuota: Bool

    public init(
        mainTenths: Int,
        automationTenths: Int,
        backgroundTenths: Int,
        officialTenths: Int,
        hasUnreconstructedQuota: Bool
    ) {
        self.mainTenths = mainTenths
        self.automationTenths = automationTenths
        self.backgroundTenths = backgroundTenths
        self.officialTenths = officialTenths
        self.hasUnreconstructedQuota = hasUnreconstructedQuota
    }

    public var mainText: String {
        Self.percentText(for: mainTenths)
    }

    public var automationText: String {
        Self.percentText(for: automationTenths)
    }

    public var backgroundText: String {
        Self.percentText(for: backgroundTenths)
    }

    public var officialText: String {
        Self.percentText(for: officialTenths)
    }

    public var unreconstructedText: String? {
        hasUnreconstructedQuota
            ? "无法重建消耗 · \(backgroundText)"
            : nil
    }

    private static func percentText(for tenths: Int) -> String {
        "\(tenths / 10).\(tenths % 10)%"
    }
}

public enum TaskDetailFormatter {
    public static func detail(
        projectPath: String,
        subtaskCount: Int,
        containsEstimatedPricing: Bool
    ) -> String {
        let directory = projectPath.isEmpty
            ? "未知"
            : URL(fileURLWithPath: projectPath).lastPathComponent
        let detail = "运行目录：\(directory) · 已归并 \(subtaskCount) 个子任务"
        return containsEstimatedPricing
            ? "含估算 · \(detail)"
            : detail
    }
}

public enum TokenFormatter {
    public static func compact(_ value: Int64) -> String {
        let absolute = Double(abs(value))
        let sign = value < 0 ? "-" : ""

        if absolute >= 1_000_000_000 {
            return sign + decimal(absolute / 1_000_000_000) + "B"
        }
        if absolute >= 1_000_000 {
            return sign + decimal(absolute / 1_000_000) + "M"
        }
        if absolute >= 1_000 {
            return sign + decimal(absolute / 1_000) + "K"
        }
        return String(value)
    }

    public static func windowLabel(minutes: Int) -> String {
        if minutes > 0, minutes.isMultiple(of: 1_440) {
            return "\(minutes / 1_440) 天额度"
        }
        if minutes > 0, minutes.isMultiple(of: 60) {
            return "\(minutes / 60) 小时额度"
        }
        return "\(minutes) 分钟额度"
    }

    public static func resetLabel(resetAt: Date, now: Date = Date()) -> String {
        let remaining = max(0, Int(resetAt.timeIntervalSince(now)))
        if remaining < 60 {
            return "即将重置"
        }

        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 {
            return hours > 0
                ? "\(days) 天 \(hours) 小时后重置"
                : "\(days) 天后重置"
        }
        if hours > 0 {
            return minutes > 0
                ? "\(hours) 小时 \(minutes) 分后重置"
                : "\(hours) 小时后重置"
        }
        return "\(minutes) 分后重置"
    }

    public static func planLabel(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "pro":
            return "PRO"
        case "plus":
            return "PLUS"
        case "team":
            return "TEAM"
        case "business", "self_serve_business_prolite":
            return "BUSINESS"
        default:
            return rawValue.uppercased()
        }
    }

    private static func decimal(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return formatted.hasSuffix(".0")
            ? String(formatted.dropLast(2))
            : formatted
    }
}
