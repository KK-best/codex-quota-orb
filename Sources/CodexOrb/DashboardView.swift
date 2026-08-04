import CodexOrbCore
import SwiftUI

private enum ProjectScope: String, CaseIterable, Identifiable {
    case lifetime = "累计"
    case launch = "本次监测"

    var id: String { rawValue }
}

private enum TaskValueMode: String, CaseIterable, Identifiable {
    case quota = "额度 %"
    case tokens = "Token"
    case apiCost = "API $"

    var id: String { rawValue }

    var displayMetric: TaskDisplayMetric {
        switch self {
        case .quota:
            return .quota
        case .tokens:
            return .tokens
        case .apiCost:
            return .apiCost
        }
    }
}

struct DashboardView: View {
    @ObservedObject var monitor: UsageMonitor
    let onClose: () -> Void
    let onQuit: () -> Void

    @State private var scope: ProjectScope = .lifetime
    @State private var taskMode: TaskValueMode = .quota

    private var displayedProjects: [ProjectUsage] {
        switch scope {
        case .lifetime:
            return monitor.projects
        case .launch:
            return monitor.projects.filter {
                monitor.launchTokens(for: $0) > 0
            }
        }
    }

    private func visibleTokens(_ project: ProjectUsage) -> Int64 {
        scope == .lifetime
            ? project.totalTokens
            : monitor.launchTokens(for: project)
    }

    private var displayedTasks: [TaskQuotaUsage] {
        TaskDisplayOrdering.sorted(
            monitor.taskQuota?.tasks ?? [],
            by: taskMode.displayMetric
        )
    }

    private var displayedAutomationTasks: [TaskQuotaUsage] {
        TaskDisplayOrdering.sorted(
            monitor.taskQuota?.automationTasks ?? [],
            by: taskMode.displayMetric
        )
    }

    private func taskMetric(
        _ task: TaskQuotaUsage
    ) -> Double {
        switch taskMode {
        case .quota:
            return task.usedPercent
        case .tokens:
            return Double(task.tokenCount)
        case .apiCost:
            return task.apiEquivalentCostUSD
        }
    }

    private var displayedTaskMaximum: Double {
        displayedTasks.reduce(0) { maximum, task in
            max(maximum, taskMetric(task))
        }
    }

    private var displayedAutomationTaskMaximum: Double {
        displayedAutomationTasks.reduce(0) { maximum, task in
            max(maximum, taskMetric(task))
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                }

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        quotaCard
                        accountMetrics
                        taskSection
                        projectSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                }

                footer
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .padding(7)
        .shadow(color: .black.opacity(0.24), radius: 28, y: 15)
        .frame(width: 430, height: 620)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "circle.dotted.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("Codex 额度")
                    .font(.system(size: 15, weight: .semibold))
                Text("本地用量监测")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(PanelButtonStyle())
            .help("悬浮球显示设置")

            Button {
                monitor.refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(monitor.isRefreshingAccount ? 360 : 0))
                    .animation(
                        monitor.isRefreshingAccount
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: monitor.isRefreshingAccount
                    )
            }
            .buttonStyle(PanelButtonStyle())
            .help("刷新")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(PanelButtonStyle())
            .help("收起")
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
    }

    private var quotaCard: some View {
        HStack(spacing: 18) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(
                            from: 0,
                            to: (monitor.account?.quota.remainingPercent ?? 0) / 100
                        )
                        .stroke(
                            quotaAccent,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text(monitor.account.map {
                            "\(Int($0.quota.remainingPercent.rounded()))"
                        } ?? "—")
                            .font(.system(size: 29, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("% 剩余")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)

                resetProbabilityOrb
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(monitor.account.map {
                        TokenFormatter.windowLabel(
                            minutes: $0.quota.windowDurationMinutes
                        )
                    } ?? "正在读取额度")
                        .font(.system(size: 17, weight: .semibold))

                    if let plan = monitor.account?.planType {
                        Text(TokenFormatter.planLabel(plan))
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Text(monitor.account.map {
                    "已使用 \(Int($0.quota.usedPercent.rounded()))%"
                } ?? monitor.accountError ?? "连接 Codex 官方接口…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let resetAt = monitor.account?.quota.resetsAt {
                    Label(
                        TokenFormatter.resetLabel(resetAt: resetAt),
                        systemImage: "clock"
                    )
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    private var accountMetrics: some View {
        HStack(spacing: 10) {
            MetricTile(
                label: "账户累计",
                value: monitor.account.map {
                    TokenFormatter.compact($0.lifetimeTokens)
                } ?? "—",
                detail: "官方 activity"
            )

            MetricTile(
                label: monitor.account?.dailyUsage.last.map {
                    "\($0.date.suffix(5)) 用量"
                } ?? "最近单日",
                value: monitor.account?.dailyUsage.last.map {
                    TokenFormatter.compact($0.tokens)
                } ?? "—",
                detail: "官方 Token"
            )

            MetricTile(
                label: "免费重置",
                value: monitor.account.map {
                    "\($0.resetCredits)"
                } ?? "—",
                detail: "可用次数"
            )
        }
    }

    private var resetProbabilityOrb: some View {
        let snapshot = monitor.resetProbability
        let probability = snapshot?.preferred24h

        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(resetProbabilityColor(probability).opacity(0.12))
                Circle()
                    .stroke(
                        resetProbabilityColor(probability).opacity(0.32),
                        lineWidth: 1.5
                    )

                if monitor.isRefreshingResetProbability, snapshot == nil {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text(resetProbabilityText(probability))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(width: 42, height: 42)

            Text("24h")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .help(
            "24h 重置概率 · \(resetProbabilityDetail(snapshot)) · 来源：codex-reset.com"
        )
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("项目累计 Token")
                        .font(.system(size: 14.5, weight: .semibold))
                    Text("本机记录 · 含缓存上下文")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("项目口径", selection: $scope) {
                    ForEach(ProjectScope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 158)
                .controlSize(.small)
            }

            if let error = monitor.projectError, monitor.projects.isEmpty {
                EmptyState(
                    icon: "externaldrive.badge.exclamationmark",
                    title: "暂时无法读取项目",
                    detail: error
                )
            } else if displayedProjects.isEmpty {
                EmptyState(
                    icon: "waveform.path.ecg",
                    title: scope == .launch ? "监测已开始" : "暂无项目用量",
                    detail: scope == .launch
                        ? "新产生的 Token 会自动出现在这里"
                        : "打开 Codex 项目后会自动统计"
                )
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(Array(displayedProjects.prefix(18).enumerated()), id: \.element.id) {
                        index,
                        project in
                        ProjectRow(
                            project: project,
                            tokens: visibleTokens(project),
                            maximum: max(
                                1,
                                visibleTokens(displayedProjects[0])
                            ),
                            color: projectColor(index)
                        )
                    }
                }
            }
        }
        .padding(15)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本轮对话消耗")
                        .font(.system(size: 14.5, weight: .semibold))
                    Text(taskSubtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if monitor.isRefreshingTasks {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Picker("对话显示口径", selection: $taskMode) {
                        ForEach(TaskValueMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 166)
                    .controlSize(.small)
                }
            }

            if let error = monitor.taskError,
               monitor.taskQuota == nil {
                EmptyState(
                    icon: "checklist.unchecked",
                    title: "暂时无法归并对话",
                    detail: error
                )
            } else if let result = monitor.taskQuota {
                if result.tasks.isEmpty, result.automationTasks.isEmpty {
                    EmptyState(
                        icon: "checklist",
                        title: "本轮暂无主对话",
                        detail: "产生新的 Codex 主对话后会自动显示"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("主对话")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if result.tasks.isEmpty {
                            Text("本轮暂无主对话")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 5)
                        } else {
                            LazyVStack(spacing: 4) {
                                ForEach(
                                    Array(displayedTasks.enumerated()),
                                    id: \.element.id
                                ) { index, task in
                                    TaskRow(
                                        task: task,
                                        maximum: displayedTaskMaximum,
                                        mode: taskMode,
                                        color: projectColor(index)
                                    )
                                }
                            }
                        }

                        if !result.automationTasks.isEmpty {
                            Text("自动任务")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)

                            LazyVStack(spacing: 4) {
                                ForEach(
                                    Array(displayedAutomationTasks.enumerated()),
                                    id: \.element.id
                                ) { index, task in
                                    TaskRow(
                                        task: task,
                                        maximum: displayedAutomationTaskMaximum,
                                        mode: taskMode,
                                        color: projectColor(index + displayedTasks.count)
                                    )
                                }
                            }
                        }
                    }
                }

                taskSectionFooter(result)
            } else {
                EmptyState(
                    icon: "checklist.checked",
                    title: "正在归并本轮对话",
                    detail: "首次扫描本轮日志可能需要几秒"
                )
            }
        }
        .padding(15)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private func taskSectionFooter(
        _ result: TaskAggregationResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(taskSummary(result))

            if result.backgroundThreadCount > 0 {
                Text(
                    "未归属后台 \(result.backgroundThreadCount) 个"
                        + " · \(backgroundValue(result))"
                )
            }

            if let diagnostic = quotaFooterDisplay(result).unreconstructedText {
                Text(diagnostic)
            }
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.top, 2)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(
                    monitor.accountError == nil
                        && monitor.projectError == nil
                        && monitor.taskError == nil
                        ? Color(nsColor: .systemGreen)
                        : Color(nsColor: .systemOrange)
                )
                .frame(width: 6, height: 6)

            Text(footerStatus)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(footerStatus)

            Spacer()

            Button("退出", action: onQuit)
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 21)
        .frame(height: 42)
        .background(Color.primary.opacity(0.025))
    }

    private var footerStatus: String {
        if let error = monitor.accountError
            ?? monitor.taskError
            ?? monitor.projectError {
            return error
        }
        if let date = monitor.lastTaskUpdated {
            return "任务同步 \(date.formatted(date: .omitted, time: .shortened)) · 本地读取"
        }
        return "正在同步任务 · 数据仅保留在本机"
    }

    private var quotaAccent: Color {
        guard let severity = monitor.account?.quota.severity else {
            return Color(nsColor: .systemGray)
        }
        switch severity {
        case .normal:
            return Color(nsColor: .systemBlue)
        case .warning:
            return Color(nsColor: .systemOrange)
        case .critical:
            return Color(nsColor: .systemRed)
        }
    }

    private func resetProbabilityText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private func resetProbabilityDetail(
        _ snapshot: ResetProbabilitySnapshot?
    ) -> String {
        guard let snapshot else {
            if monitor.isRefreshingResetProbability {
                return "正在读取公开预测…"
            }
            return monitor.resetProbabilityError ?? "暂无公开预测"
        }

        if let community = snapshot.community24h,
           snapshot.model24h != nil {
            return "模型预测 · 社区 \(resetProbabilityText(community)) · \(snapshot.communityVoteCount) 票"
        }
        return snapshot.preferredSourceLabel + " · codex-reset.com"
    }

    private func resetProbabilityColor(_ value: Double?) -> Color {
        guard let value else {
            return Color(nsColor: .systemGray)
        }
        if value >= 60 {
            return Color(nsColor: .systemGreen)
        }
        if value >= 30 {
            return Color(nsColor: .systemOrange)
        }
        return Color.accentColor
    }

    private func projectColor(_ index: Int) -> Color {
        let hues: [Double] = [0.58, 0.72, 0.46, 0.08, 0.91, 0.52]
        return Color(
            hue: hues[index % hues.count],
            saturation: 0.62,
            brightness: 0.88
        )
    }

    private func percent(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(1))
        ) + "%"
    }

    private var taskSubtitle: String {
        switch taskMode {
        case .quota:
            return "按主对话归并 · 以本次重置的 100% 为基准"
        case .tokens:
            return "本轮日志中的输入 + 输出 Token"
        case .apiCost:
            return "按标准 API 价格估算，非实际账单"
        }
    }

    private func taskSummary(
        _ result: TaskAggregationResult
    ) -> String {
        switch taskMode {
        case .quota:
            let display = quotaFooterDisplay(result)
            return "主对话 \(display.mainText)"
                + " + 自动任务 \(display.automationText)"
                + " + 后台 \(display.backgroundText)"
                + " = 官方 \(display.officialText)"
        case .tokens:
            let mainTotal = result.tasks.reduce(Int64(0)) {
                $0 + $1.tokenCount
            }
            let automationTotal = result.automationTasks.reduce(Int64(0)) {
                $0 + $1.tokenCount
            }
            return "主对话 \(TokenFormatter.compact(mainTotal)) Token"
                + " + 自动任务 \(TokenFormatter.compact(automationTotal)) Token"
                + " + 后台 \(TokenFormatter.compact(result.backgroundTokenCount)) Token"
        case .apiCost:
            let mainTotal = result.tasks.reduce(0.0) {
                $0 + $1.apiEquivalentCostUSD
            }
            let automationTotal = result.automationTasks.reduce(0.0) {
                $0 + $1.apiEquivalentCostUSD
            }
            return "主对话 \(currency(mainTotal))"
                + " + 自动任务 \(currency(automationTotal))"
                + " + 后台 \(currency(result.backgroundAPICostUSD))"
                + " · 非实际账单"
        }
    }

    private func quotaFooterDisplay(
        _ result: TaskAggregationResult
    ) -> QuotaFooterDisplay {
        QuotaFooterDisplay(
            mainTenths: result.tasks.reduce(0) {
                $0 + $1.displayUsedTenths
            },
            automationTenths: result.automationTasks.reduce(0) {
                $0 + $1.displayUsedTenths
            },
            backgroundTenths: result.backgroundDisplayTenths,
            officialTenths: result.officialDisplayTenths,
            hasUnreconstructedQuota: result.hasUnreconstructedQuota
        )
    }

    private func backgroundValue(
        _ result: TaskAggregationResult
    ) -> String {
        switch taskMode {
        case .quota:
            return quotaFooterDisplay(result).backgroundText
        case .tokens:
            return "\(TokenFormatter.compact(result.backgroundTokenCount)) Token"
        case .apiCost:
            return currency(result.backgroundAPICostUSD)
        }
    }

    private func currency(_ value: Double) -> String {
        value.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(value < 1 ? 3 : 2))
        )
    }
}

private struct MetricTile: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct ProjectRow: View {
    let project: ProjectUsage
    let tokens: Int64
    let maximum: Int64
    let color: Color

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 9) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(abbreviatedPath)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(TokenFormatter.compact(tokens))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("\(project.sessionCount) 个任务")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.055))
                    Capsule()
                        .fill(color.opacity(0.72))
                        .frame(
                            width: max(
                                3,
                                proxy.size.width
                                    * CGFloat(Double(tokens) / Double(maximum))
                            )
                        )
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 7)
    }

    private var abbreviatedPath: String {
        (project.path as NSString).abbreviatingWithTildeInPath
    }
}

private struct TaskRow: View {
    let task: TaskQuotaUsage
    let maximum: Double
    let mode: TaskValueMode
    let color: Color

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 9) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text(valueLabel)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.055))
                    Capsule()
                        .fill(color.opacity(0.72))
                        .frame(
                            width: barWidth(in: proxy.size.width)
                        )
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 7)
    }

    private var detail: String {
        TaskDetailFormatter.detail(
            projectPath: task.projectPath,
            subtaskCount: task.subtaskCount,
            containsEstimatedPricing: task.containsEstimatedPricing
        )
    }

    private var metric: Double {
        switch mode {
        case .quota:
            return task.usedPercent
        case .tokens:
            return Double(task.tokenCount)
        case .apiCost:
            return task.apiEquivalentCostUSD
        }
    }

    private var valueLabel: String {
        switch mode {
        case .quota:
            return percentLabel
        case .tokens:
            return TokenFormatter.compact(task.tokenCount)
        case .apiCost:
            return task.apiEquivalentCostUSD.formatted(
                .currency(code: "USD")
                    .precision(
                        .fractionLength(
                            task.apiEquivalentCostUSD < 1 ? 3 : 2
                        )
                    )
            )
        }
    }

    private var barRatio: Double {
        guard maximum > 0 else { return 0 }
        return min(max(metric / maximum, 0), 1)
    }

    private func barWidth(in availableWidth: CGFloat) -> CGFloat {
        guard metric > 0, availableWidth > 0 else { return 0 }
        let proportionalWidth = availableWidth * CGFloat(barRatio)
        return min(availableWidth, max(3, proportionalWidth))
    }

    private var percentLabel: String {
        "\(task.displayUsedTenths / 10).\(task.displayUsedTenths % 10)%"
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
            Text(detail)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : 0.055))
            .clipShape(Circle())
    }
}
