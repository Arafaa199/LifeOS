import Foundation
import SwiftUI
import Combine
import os

@MainActor
class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    enum SyncDomain: String, CaseIterable, Identifiable {
        case dashboard, finance, healthKit, calendar, whoop

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .finance: return "Finance"
            case .healthKit: return "HealthKit"
            case .calendar: return "Calendar"
            case .whoop: return "WHOOP"
            }
        }

        var icon: String {
            switch self {
            case .dashboard: return "square.grid.2x2"
            case .finance: return "chart.pie"
            case .healthKit: return "heart.fill"
            case .calendar: return "calendar"
            case .whoop: return "w.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .dashboard: return .nexusPrimary
            case .finance: return .nexusFinance
            case .healthKit: return .red
            case .calendar: return .blue
            case .whoop: return .orange
            }
        }

        var subtitle: String? {
            switch self {
            case .whoop: return "Server status (read-only)"
            default: return nil
            }
        }
    }

    struct DomainSyncState {
        var isSyncing: Bool = false
        var lastSyncDate: Date?
        var lastError: String?
        var source: String?
        var detail: String?
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

    @Published var domainStates: [SyncDomain: DomainSyncState] = {
        var states: [SyncDomain: DomainSyncState] = [:]
        for domain in SyncDomain.allCases {
            states[domain] = DomainSyncState()
        }
        return states
    }()

    @Published var dashboardPayload: DashboardPayload?
    @Published var financeSummaryResult: FinanceResponse?
    @Published var isSyncingAll = false
    @Published var whoopDebugInfo: WhoopDebugInfo?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "sync")
    private let dashboardService = DashboardService.shared
    private let healthKitSync = HealthKitSyncService.shared
    private let calendarSync = CalendarSyncService.shared
    private let api = NexusAPI.shared

    private var lastSyncAllDate: Date?
    private let minSyncInterval: TimeInterval = 15
    private var syncAllTask: Task<Void, Never>?

    private init() {
        // Load cached dashboard on init
        if let cached = dashboardService.loadCached() {
            dashboardPayload = cached.payload
            domainStates[.dashboard] = DomainSyncState(
                lastSyncDate: cached.lastUpdated,
                source: "cache"
            )
            updateWhoopStatus()
        }
    }

    // MARK: - Sync All

    func syncAll(force: Bool = false) {
        // Debounce unless forced
        if !force,
           let last = lastSyncAllDate,
           Date().timeIntervalSince(last) < minSyncInterval {
            logger.info("syncAll debounced")
            return
        }

        syncAllTask?.cancel()

        // Freshness contract: these are synchronous (@MainActor),
        // so any subscriber sees the change within the same run-loop pass.
        // UI must reflect a visible state change within 300ms of app foreground.
        isSyncingAll = true
        lastSyncAllDate = Date()

        syncAllTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.syncDashboard() }
                group.addTask { await self.syncFinance() }
                group.addTask { await self.syncHealthKit() }
                group.addTask { await self.syncCalendar() }
                // WHOOP is read-only server status, updated after dashboard sync
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
            // Read-only: refresh from current dashboard payload
            updateWhoopStatus()
        }
    }

    // MARK: - Per-Domain Sync

    private func syncDashboard() async {
        domainStates[.dashboard]?.isSyncing = true
        domainStates[.dashboard]?.lastError = nil

        do {
            let result = try await dashboardService.fetchDashboard()
            dashboardPayload = result.payload
            domainStates[.dashboard] = DomainSyncState(
                lastSyncDate: Date(),
                source: result.source == .network ? "network" : "cache"
            )
            // WHOOP status derives from dashboard feedStatus
            updateWhoopStatus()
        } catch {
            domainStates[.dashboard]?.isSyncing = false
            domainStates[.dashboard]?.lastError = error.localizedDescription
            logger.error("Dashboard sync failed: \(error.localizedDescription)")
        }
    }

    private func syncFinance() async {
        domainStates[.finance]?.isSyncing = true
        domainStates[.finance]?.lastError = nil

        do {
            let response = try await api.fetchFinanceSummary()
            financeSummaryResult = response
            domainStates[.finance] = DomainSyncState(
                lastSyncDate: Date(),
                source: "network"
            )
        } catch {
            domainStates[.finance]?.isSyncing = false
            domainStates[.finance]?.lastError = error.localizedDescription
            logger.error("Finance sync failed: \(error.localizedDescription)")
        }
    }

    private func syncHealthKit() async {
        let manager = HealthKitManager.shared
        domainStates[.healthKit]?.isSyncing = true
        domainStates[.healthKit]?.lastError = nil

        guard manager.isAuthorized else {
            domainStates[.healthKit] = DomainSyncState(
                lastError: "HealthKit not authorized"
            )
            return
        }

        do {
            try await healthKitSync.syncAllData()
            let count = healthKitSync.lastSyncSampleCount
            domainStates[.healthKit] = DomainSyncState(
                lastSyncDate: Date(),
                source: "healthkit",
                detail: count > 0 ? "\(count) samples" : "No new samples"
            )
        } catch {
            domainStates[.healthKit]?.isSyncing = false
            domainStates[.healthKit]?.lastError = error.localizedDescription
            logger.error("HealthKit sync failed: \(error.localizedDescription)")
        }
    }

    private func syncCalendar() async {
        domainStates[.calendar]?.isSyncing = true
        domainStates[.calendar]?.lastError = nil

        do {
            try await calendarSync.syncAllData()
            let count = calendarSync.lastSyncEventCount
            domainStates[.calendar] = DomainSyncState(
                lastSyncDate: Date(),
                source: "eventkit",
                detail: count > 0 ? "\(count) events" : nil
            )
        } catch {
            domainStates[.calendar]?.isSyncing = false
            domainStates[.calendar]?.lastError = error.localizedDescription
            logger.error("Calendar sync failed: \(error.localizedDescription)")
        }
    }

    // WHOOP status is read-only — no upstream trigger available.
    // Reads from dashboardPayload.feedStatus (populated by syncDashboard).
    private func updateWhoopStatus() {
        let now = Date()

        guard let feed = dashboardPayload?.feedStatus.first(where: { $0.feed.lowercased().contains("whoop") }) else {
            domainStates[.whoop] = DomainSyncState(
                lastError: "No WHOOP feed in server response"
            )
            whoopDebugInfo = WhoopDebugInfo(
                rawLastSync: nil, parsedDate: nil, checkedAt: now,
                ageHours: nil, serverStatus: "missing", serverHoursSinceSync: nil
            )
            return
        }

        let parsedDate = parseFeedSyncDate(feed.lastSync)
        let ageHours = parsedDate.map { now.timeIntervalSince($0) / 3600 }

        domainStates[.whoop] = DomainSyncState(
            lastSyncDate: parsedDate,
            source: "server (read-only)",
            detail: feed.status == .healthy ? nil : "Status: \(feed.status.rawValue)"
        )

        if feed.status == .stale || feed.status == .critical {
            domainStates[.whoop]?.lastError = "Data is \(feed.status.rawValue) (\(String(format: "%.0f", feed.hoursSinceSync ?? 0))h old)"
        }

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
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: dateString) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: dateString)
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
}
