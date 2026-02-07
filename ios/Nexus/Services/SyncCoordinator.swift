import Foundation
import SwiftUI
import Combine
import os
import WidgetKit

@MainActor
class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    enum SyncDomain: String, CaseIterable, Identifiable {
        case dashboard, finance, healthKit, calendar, whoop, documents

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .finance: return "Finance"
            case .healthKit: return "HealthKit"
            case .calendar: return "Calendar"
            case .whoop: return "WHOOP"
            case .documents: return "Documents"
            }
        }

        var icon: String {
            switch self {
            case .dashboard: return "square.grid.2x2"
            case .finance: return "chart.pie"
            case .healthKit: return "heart.fill"
            case .calendar: return "calendar"
            case .whoop: return "w.circle.fill"
            case .documents: return "doc.text"
            }
        }

        var color: Color {
            switch self {
            case .dashboard: return NexusTheme.Colors.accent
            case .finance: return NexusTheme.Colors.Semantic.green
            case .healthKit: return NexusTheme.Colors.Semantic.red
            case .calendar: return NexusTheme.Colors.Semantic.blue
            case .whoop: return NexusTheme.Colors.Semantic.amber
            case .documents: return NexusTheme.Colors.Semantic.purple
            }
        }

    }

    struct WhoopDebugInfo {
        let rawLastSync: String?
        let parsedDate: Date?
        let checkedAt: Date
        let ageHours: Double?
        let serverStatus: String
        let serverHoursSinceSync: Double?
    }

    // MARK: - Published State

    @Published var domainStates: [SyncDomain: DomainState] = {
        var states: [SyncDomain: DomainState] = [:]
        for domain in SyncDomain.allCases {
            states[domain] = DomainState()
        }
        return states
    }()

    @Published var dashboardPayload: DashboardPayload?
    @Published var financeSummaryResult: FinanceResponse?
    @Published var documentsResult: [Document]?
    @Published var isSyncingAll = false
    @Published var whoopDebugInfo: WhoopDebugInfo?

    // MARK: - Domain-Specific Publishers

    private let dashboardStateSubject = PassthroughSubject<Void, Never>()
    private let financeStateSubject = PassthroughSubject<Void, Never>()
    private let healthKitStateSubject = PassthroughSubject<Void, Never>()
    private let calendarStateSubject = PassthroughSubject<Void, Never>()
    private let documentsStateSubject = PassthroughSubject<Void, Never>()

    var dashboardStatePublisher: AnyPublisher<Void, Never> { dashboardStateSubject.eraseToAnyPublisher() }
    var financeStatePublisher: AnyPublisher<Void, Never> { financeStateSubject.eraseToAnyPublisher() }
    var healthKitStatePublisher: AnyPublisher<Void, Never> { healthKitStateSubject.eraseToAnyPublisher() }
    var calendarStatePublisher: AnyPublisher<Void, Never> { calendarStateSubject.eraseToAnyPublisher() }
    var documentsStatePublisher: AnyPublisher<Void, Never> { documentsStateSubject.eraseToAnyPublisher() }

    func notifyDomainStateChanged(_ domain: SyncDomain) {
        switch domain {
        case .dashboard: dashboardStateSubject.send()
        case .finance: financeStateSubject.send()
        case .healthKit: healthKitStateSubject.send()
        case .calendar: calendarStateSubject.send()
        case .documents: documentsStateSubject.send()
        case .whoop: break // WHOOP state is part of dashboard
        }
    }

    // MARK: - Private

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "sync")
    private let dashboardService = DashboardService.shared
    private let healthKitSync = HealthKitSyncService.shared
    private let calendarSync = CalendarSyncService.shared
    private let reminderSync = ReminderSyncService.shared
    private let api = NexusAPI.shared

    private var lastSyncAllDate: Date?
    private let minSyncInterval: TimeInterval = 15
    private var syncAllTask: Task<Void, Never>?

    private init() {
        if let cached = dashboardService.loadCached() {
            dashboardPayload = cached.payload
            var state = DomainState()
            state.markSucceeded(source: "cache")
            state.phase = .succeeded(at: cached.lastUpdated)
            domainStates[.dashboard] = state
            updateWhoopDebugFromFeedStatus()
        }
    }

    // MARK: - Sync All

    func syncAll(force: Bool = false) {
        if !force,
           let last = lastSyncAllDate,
           Date().timeIntervalSince(last) < minSyncInterval {
            logger.info("syncAll debounced")
            return
        }

        syncAllTask?.cancel()

        isSyncingAll = true
        lastSyncAllDate = Date()

        syncAllTask = Task {
            let flags = AppSettings.shared

            // Phase 1: Push local data to server (HealthKit weight, calendar events)
            await withTaskGroup(of: Void.self) { group in
                if flags.healthKitSyncEnabled {
                    group.addTask { await self.syncHealthKit() }
                }
                if flags.calendarSyncEnabled {
                    group.addTask { await self.syncCalendar() }
                }
            }

            // Phase 2: Fetch server data (now includes what we just pushed)
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.syncDashboard() }
                if flags.financeSyncEnabled {
                    group.addTask { await self.syncFinance() }
                }
                if flags.whoopSyncEnabled {
                    group.addTask { await self.syncWHOOP() }
                }
                if flags.documentsSyncEnabled {
                    group.addTask { await self.syncDocuments() }
                }
            }

            isSyncingAll = false
        }
    }

    func sync(_ domain: SyncDomain) async {
        switch domain {
        case .dashboard:
            await syncDashboard()
        case .finance: await syncFinance()
        case .healthKit: await syncHealthKit()
        case .calendar: await syncCalendar()
        case .whoop:
            await syncWHOOP()
        case .documents:
            await syncDocuments()
        }
    }

    // MARK: - Background Sync

    func syncForBackground() async {
        logger.info("[background] starting background sync")
        let flags = AppSettings.shared

        // Push local data first (HealthKit weight, calendar events, reminders)
        await syncHealthKit()
        if flags.calendarSyncEnabled {
            await syncCalendar()
        }

        // Then fetch server data (includes what we just pushed)
        await syncDashboard()
        logger.info("[background] background sync complete")
    }

    // MARK: - Per-Domain Sync

    private func syncDashboard() async {
        domainStates[.dashboard]?.markSyncing()
        notifyDomainStateChanged(.dashboard)
        let start = CFAbsoluteTimeGetCurrent()
        logger.info("[dashboard] sync started")

        do {
            let result = try await dashboardService.fetchDashboard()
            dashboardPayload = result.payload
            let src = result.source == .network ? "network" : "cache"
            domainStates[.dashboard]?.markSucceeded(source: src)
            notifyDomainStateChanged(.dashboard)

            // Debug: Log payload contents
            let facts = result.payload.todayFacts
            logger.info("[dashboard] payload received: todayFacts=\(facts != nil ? "present" : "nil"), recovery=\(facts?.recoveryScore ?? -1), date=\(result.payload.meta.forDate)")

            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.info("[dashboard] sync succeeded source=\(src) duration=\(ms)ms")

            // Update SharedStorage for widgets
            updateWidgetData(from: result.payload)

            // Check budget alerts (only when fetched from network)
            if result.source == .network {
                await checkBudgetAlerts(from: result.payload)
            }
        } catch is CancellationError {
            domainStates[.dashboard]?.phase = .idle
            notifyDomainStateChanged(.dashboard)
        } catch {
            domainStates[.dashboard]?.markFailed(error.localizedDescription)
            notifyDomainStateChanged(.dashboard)
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.error("[dashboard] sync failed duration=\(ms)ms error=\(error.localizedDescription)")
        }
    }

    private func syncFinance() async {
        domainStates[.finance]?.markSyncing()
        notifyDomainStateChanged(.finance)
        let start = CFAbsoluteTimeGetCurrent()
        logger.info("[finance] sync started")

        do {
            let response = try await api.fetchFinanceSummary()
            financeSummaryResult = response
            let count = response.data?.recentTransactions?.count
            domainStates[.finance]?.markSucceeded(source: "network", itemCount: count)
            notifyDomainStateChanged(.finance)

            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.info("[finance] sync succeeded items=\(count ?? 0) duration=\(ms)ms")
        } catch is CancellationError {
            domainStates[.finance]?.phase = .idle
            notifyDomainStateChanged(.finance)
        } catch {
            domainStates[.finance]?.markFailed(error.localizedDescription)
            notifyDomainStateChanged(.finance)
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.error("[finance] sync failed duration=\(ms)ms error=\(error.localizedDescription)")
        }
    }

    private func syncHealthKit() async {
        let manager = HealthKitManager.shared
        domainStates[.healthKit]?.markSyncing()
        let start = CFAbsoluteTimeGetCurrent()
        logger.info("[healthKit] sync started")

        guard manager.isHealthDataAvailable else {
            domainStates[.healthKit]?.markFailed("HealthKit not available")
            logger.warning("[healthKit] not available")
            return
        }

        guard manager.isAuthorized else {
            let message: String
            switch manager.permissionStatus {
            case .notSetUp:
                message = "HealthKit not set up"
            case .requested:
                message = "HealthKit access not verified — open Health app to check permissions"
            case .failed:
                message = "HealthKit not available"
            case .working:
                message = ""
            }
            domainStates[.healthKit]?.markFailed(message)
            logger.warning("[healthKit] not authorized: \(message)")
            return
        }

        do {
            try await healthKitSync.syncAllData()
            let count = healthKitSync.lastSyncSampleCount
            domainStates[.healthKit]?.markSucceeded(
                source: "healthkit",
                detail: count > 0 ? "\(count) samples" : "No new samples",
                itemCount: count
            )

            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.info("[healthKit] sync succeeded samples=\(count) duration=\(ms)ms")
        } catch is CancellationError {
            domainStates[.healthKit]?.phase = .idle
        } catch {
            domainStates[.healthKit]?.markFailed(error.localizedDescription)

            let desc = error.localizedDescription.lowercased()
            if desc.contains("authorization") || desc.contains("not determined") {
                UserDefaults.standard.set(false, forKey: "healthKitAuthorizationRequested")
                manager.checkAuthorization()
                domainStates[.healthKit]?.markFailed("HealthKit needs re-authorization")
                logger.warning("[healthKit] auth stale — requesting re-authorization")
            } else {
                let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                logger.error("[healthKit] sync failed duration=\(ms)ms error=\(error.localizedDescription)")
            }
        }
    }

    private func syncCalendar() async {
        domainStates[.calendar]?.markSyncing()
        let start = CFAbsoluteTimeGetCurrent()
        logger.info("[calendar] sync started")

        do {
            try await calendarSync.syncAllData()

            let eventCount = calendarSync.lastSyncEventCount
            var reminderCount = 0

            // Sync reminders separately so failures don't contaminate calendar status
            do {
                try await reminderSync.syncAllData()
                reminderCount = reminderSync.lastSyncReminderCount
            } catch {
                logger.error("[reminders] sync failed error=\(error.localizedDescription)")
            }

            let totalCount = eventCount + reminderCount
            var detail: String?
            if totalCount > 0 {
                var parts: [String] = []
                if eventCount > 0 { parts.append("\(eventCount) events") }
                if reminderCount > 0 { parts.append("\(reminderCount) reminders") }
                detail = parts.joined(separator: ", ")
            }
            domainStates[.calendar]?.markSucceeded(
                source: "eventkit",
                detail: detail,
                itemCount: totalCount
            )

            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.info("[calendar] sync succeeded events=\(totalCount) duration=\(ms)ms")
        } catch is CancellationError {
            domainStates[.calendar]?.phase = .idle
        } catch {
            domainStates[.calendar]?.markFailed(error.localizedDescription)
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.error("[calendar] sync failed duration=\(ms)ms error=\(error.localizedDescription)")
        }
    }

    // MARK: - Documents Sync

    private func syncDocuments() async {
        domainStates[.documents]?.markSyncing()
        notifyDomainStateChanged(.documents)
        let start = CFAbsoluteTimeGetCurrent()
        logger.info("[documents] sync started")

        do {
            let response: DocumentsResponse = try await api.get("/webhook/nexus-documents")
            documentsResult = response.documents
            let count = response.documents.count
            domainStates[.documents]?.markSucceeded(source: "network", itemCount: count)
            notifyDomainStateChanged(.documents)

            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.info("[documents] sync succeeded items=\(count) duration=\(ms)ms")
        } catch is CancellationError {
            domainStates[.documents]?.phase = .idle
            notifyDomainStateChanged(.documents)
        } catch {
            domainStates[.documents]?.markFailed(error.localizedDescription)
            notifyDomainStateChanged(.documents)
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.error("[documents] sync failed duration=\(ms)ms error=\(error.localizedDescription)")
        }
    }

    // MARK: - WHOOP Sync

    private func syncWHOOP() async {
        domainStates[.whoop]?.markSyncing()
        let start = CFAbsoluteTimeGetCurrent()
        logger.info("[whoop] sync started")

        do {
            let response = try await api.refreshWHOOP()

            if response.success {
                var detail: String?
                if let sensors = response.sensorsFound, let recovery = response.recovery {
                    detail = "\(sensors) sensors, recovery \(Int(recovery))%"
                } else if let sensors = response.sensorsFound {
                    detail = "\(sensors) sensors"
                }
                domainStates[.whoop]?.markSucceeded(source: "server", detail: detail)
            } else {
                domainStates[.whoop]?.markFailed(response.message ?? "WHOOP refresh failed")
            }

            updateWhoopDebugFromFeedStatus()

            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            logger.info("[whoop] sync completed duration=\(ms)ms success=\(response.success)")
        } catch is CancellationError {
            domainStates[.whoop]?.phase = .idle
        } catch {
            logger.warning("[whoop] refresh webhook failed, falling back to feed status: \(error.localizedDescription)")
            updateWhoopFromFeedStatus()
        }
    }

    private func updateWhoopFromFeedStatus() {
        guard let feed = dashboardPayload?.feedStatus.first(where: { $0.feed.lowercased().contains("whoop") }) else {
            domainStates[.whoop]?.markFailed("No WHOOP feed in server response")
            updateWhoopDebugFromFeedStatus()
            return
        }

        let parsedDate = parseFeedSyncDate(feed.lastSync)
        if let parsedDate {
            domainStates[.whoop]?.markSucceeded(
                source: "feed_status",
                detail: feed.status == .healthy ? nil : "Status: \(feed.status.rawValue)"
            )
            domainStates[.whoop]?.phase = .succeeded(at: parsedDate)
        }

        if feed.status == .stale || feed.status == .critical {
            domainStates[.whoop]?.markFailed("Data is \(feed.status.rawValue) (\(String(format: "%.0f", feed.hoursSinceSync ?? 0))h old)")
        }

        updateWhoopDebugFromFeedStatus()
    }

    private func updateWhoopDebugFromFeedStatus() {
        let now = Date()
        guard let feed = dashboardPayload?.feedStatus.first(where: { $0.feed.lowercased().contains("whoop") }) else {
            whoopDebugInfo = WhoopDebugInfo(
                rawLastSync: nil, parsedDate: nil, checkedAt: now,
                ageHours: nil, serverStatus: "unknown", serverHoursSinceSync: nil
            )
            return
        }

        let parsedDate = parseFeedSyncDate(feed.lastSync)
        let ageHours = parsedDate.map { now.timeIntervalSince($0) / 3600 }

        whoopDebugInfo = WhoopDebugInfo(
            rawLastSync: feed.lastSync,
            parsedDate: parsedDate,
            checkedAt: now,
            ageHours: ageHours,
            serverStatus: feed.status.rawValue,
            serverHoursSinceSync: feed.hoursSinceSync
        )
    }

    private func parseFeedSyncDate(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        return DomainFreshness.parseTimestamp(dateString)
    }

    // MARK: - Helpers

    var cacheAge: TimeInterval? {
        dashboardService.cacheAge()
    }

    var cacheAgeFormatted: String? {
        guard let age = cacheAge else { return nil }
        let minutes = Int(age / 60)
        if minutes < 1 { return "< 1 min old" }
        if minutes < 60 { return "\(minutes) min old" }
        let hours = minutes / 60
        return "\(hours)h old"
    }

    var anySyncing: Bool {
        domainStates.values.contains { $0.isSyncing }
    }

    // MARK: - Widget Data

    private func updateWidgetData(from payload: DashboardPayload) {
        let storage = SharedStorage.shared

        // Update recovery data for widgets
        if let facts = payload.todayFacts {
            if let recovery = facts.recoveryScore {
                storage.saveRecoveryData(
                    score: recovery,
                    hrv: facts.hrv,
                    rhr: facts.rhr
                )
                logger.info("[widgets] recovery data updated: \(recovery)%")
            }

            // Update daily summary for widgets
            // Note: protein not available in TodayFacts yet
            storage.saveDailySummary(
                calories: facts.caloriesConsumed ?? 0,
                protein: 0,
                water: facts.waterMl ?? 0,
                weight: facts.weightKg
            )
        }

        // Update fasting data for widgets
        if let fasting = payload.fasting {
            storage.saveFastingData(
                lastMealAt: fasting.lastMealDate,
                isActive: fasting.isActive,
                startedAt: fasting.startedAtDate
            )
            if let hours = fasting.hoursSinceMeal ?? fasting.elapsedHours {
                logger.info("[widgets] fasting data updated: \(String(format: "%.1f", hours))h")
            }
        }

        // Update budget data for widgets
        if let budgets = financeSummaryResult?.data?.budgets, !budgets.isEmpty {
            let totalBudget = budgets.reduce(0.0) { $0 + $1.budgetAmount }
            let totalSpent = budgets.reduce(0.0) { $0 + ($1.spent ?? 0) }
            let totalRemaining = totalBudget - totalSpent
            let currency = financeSummaryResult?.data?.currency ?? "AED"

            storage.saveBudgetData(
                totalBudget: totalBudget,
                spent: totalSpent,
                remaining: max(0, totalRemaining),
                currency: currency
            )

            // Find top category by spending
            if let topBudget = budgets.max(by: { ($0.spent ?? 0) < ($1.spent ?? 0) }) {
                storage.saveBudgetTopCategory(
                    name: topBudget.category,
                    spent: topBudget.spent ?? 0,
                    limit: topBudget.budgetAmount
                )
            }

            logger.info("[widgets] budget data updated: \(currency) \(Int(totalRemaining)) remaining of \(Int(totalBudget))")
        }

        // Trigger widget refresh
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Budget Alerts

    private func checkBudgetAlerts(from payload: DashboardPayload) async {
        // Get budgets from finance summary if available
        guard let budgets = financeSummaryResult?.data?.budgets, !budgets.isEmpty else {
            logger.debug("[budget-alerts] no budgets to check")
            return
        }

        // Build category spending map from today's facts
        var categorySpending: [String: Double] = [:]
        if let breakdown = financeSummaryResult?.data?.categoryBreakdown {
            categorySpending = breakdown
        }

        await NotificationManager.shared.checkBudgetAlerts(
            budgets: budgets,
            categorySpending: categorySpending
        )
    }
}
