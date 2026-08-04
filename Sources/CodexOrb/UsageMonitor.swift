import CodexOrbCore
import Foundation

@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var account: AccountSnapshot?
    @Published private(set) var resetProbability: ResetProbabilitySnapshot?
    @Published private(set) var projects: [ProjectUsage] = []
    @Published private(set) var taskQuota: TaskAggregationResult?
    @Published private(set) var baseline: [String: Int64] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastTaskUpdated: Date?
    @Published private(set) var accountError: String?
    @Published private(set) var resetProbabilityError: String?
    @Published private(set) var projectError: String?
    @Published private(set) var taskError: String?
    @Published private(set) var isRefreshingAccount = false
    @Published private(set) var isRefreshingResetProbability = false
    @Published private(set) var isRefreshingProjects = false
    @Published private(set) var isRefreshingTasks = false
    @Published private(set) var isDashboardPresented = false

    private let accountClient = CodexAccountClient()
    private let resetPollClient = ResetPollClient()
    private let tokenStore = TokenUsageStore()
    private let taskStore = TaskQuotaStore()
    private var activeTaskQuota: QuotaSnapshot?
    private var pendingTaskQuota: QuotaSnapshot?
    private var localTimer: Timer?
    private var accountTimer: Timer?
    private var resetProbabilityTimer: Timer?

    func start() {
        refreshAll()

        localTimer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProjects()
            }
        }

        accountTimer = Timer.scheduledTimer(
            withTimeInterval: 300,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccount()
            }
        }

        resetProbabilityTimer = Timer.scheduledTimer(
            withTimeInterval: 300,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshResetProbability()
            }
        }
    }

    func stop() {
        localTimer?.invalidate()
        accountTimer?.invalidate()
        resetProbabilityTimer?.invalidate()
        localTimer = nil
        accountTimer = nil
        resetProbabilityTimer = nil
    }

    func refreshAll() {
        refreshProjects()
        refreshAccount()
        refreshResetProbability()
    }

    func refreshResetProbability() {
        guard !isRefreshingResetProbability else { return }
        isRefreshingResetProbability = true

        Task {
            defer { isRefreshingResetProbability = false }
            do {
                resetProbability = try await resetPollClient.fetch()
                resetProbabilityError = nil
            } catch {
                resetProbabilityError = error.localizedDescription
            }
        }
    }

    func refreshProjects() {
        guard !isRefreshingProjects else { return }
        isRefreshingProjects = true

        Task {
            defer { isRefreshingProjects = false }
            do {
                let updatedProjects = try await tokenStore.fetchProjects()
                if baseline.isEmpty {
                    baseline = Dictionary(
                        uniqueKeysWithValues: updatedProjects.map {
                            ($0.path, $0.totalTokens)
                        }
                    )
                }
                projects = updatedProjects
                projectError = nil
                lastUpdated = Date()
            } catch {
                projectError = error.localizedDescription
            }
        }
    }

    func refreshAccount() {
        guard !isRefreshingAccount else { return }
        isRefreshingAccount = true

        Task {
            defer { isRefreshingAccount = false }
            do {
                let updatedAccount = try await accountClient.fetch()
                account = updatedAccount
                accountError = nil
                lastUpdated = Date()
                refreshTasks(for: updatedAccount.quota)
            } catch {
                accountError = error.localizedDescription
            }
        }
    }

    func refreshTasks(for quota: QuotaSnapshot) {
        guard !isRefreshingTasks else {
            pendingTaskQuota = quota
            return
        }

        isRefreshingTasks = true
        activeTaskQuota = quota
        Task {
            let outcome: Result<TaskAggregationResult, Error>
            do {
                outcome = .success(
                    try await taskStore.fetchTasks(quota: quota)
                )
            } catch {
                outcome = .failure(error)
            }
            finishTaskRefresh(for: quota, outcome: outcome)
        }
    }

    private func finishTaskRefresh(
        for quota: QuotaSnapshot,
        outcome: Result<TaskAggregationResult, Error>
    ) {
        guard activeTaskQuota == quota else { return }

        isRefreshingTasks = false
        activeTaskQuota = nil

        let pendingQuota = pendingTaskQuota
        pendingTaskQuota = nil
        let isCurrentQuota = account?.quota == quota

        if pendingQuota == nil, isCurrentQuota {
            switch outcome {
            case let .success(result):
                taskQuota = result
                taskError = nil
                lastTaskUpdated = Date()
            case let .failure(error):
                taskError = error.localizedDescription
            }
        }

        if let pendingQuota {
            refreshTasks(for: pendingQuota)
        }
    }

    func launchTokens(for project: ProjectUsage) -> Int64 {
        project.tokensSince(baseline)
    }

    func setDashboardPresented(_ presented: Bool) {
        isDashboardPresented = presented
    }
}
