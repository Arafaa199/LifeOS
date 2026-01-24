import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var healthKit = HealthKitManager.shared
    @State private var pendingCount = 0
    @State private var isHealthKitSyncing = false
    @State private var showHealthPermission = false

    // Local HealthKit data (weight, steps, calories) - device-local reads, not API calls
    @State private var localWeight: Double?
    @State private var localSteps: Int = 0
    @State private var localCalories: Int = 0

    // Weight history for chart
    @State private var weightHistory: [(date: Date, weight: Double)] = []
    @State private var showWeightChart = false

    // Stale feeds banner dismissal (resets on new fetch)
    @State private var staleBannerDismissed = false
    @State private var lastPayloadDate: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with greeting
                    headerSection

                    // Network & Sync Status
                    statusBar

                    // Empty state when no data and no network
                    if viewModel.dashboardPayload == nil && !networkMonitor.isConnected && !viewModel.isLoading {
                        emptyStateView
                    } else {
                        // Daily Summary Cards
                        summaryCardsSection

                        // Health Section (WHOOP from unified payload + local HealthKit)
                        healthSection

                        // Recent Logs Section
                        recentLogsSection
                    }
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                staleBannerDismissed = false  // Reset banner on refresh
                await viewModel.refresh()
                await syncLocalHealthKit()
                pendingCount = OfflineQueue.shared.getQueueCount()
            }
            .navigationTitle("Nexus")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { viewModel.loadTodaysSummary() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.medium))
                            .foregroundColor(.nexusPrimary)
                            .symbolEffect(.rotate, isActive: viewModel.isLoading)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .onAppear {
                pendingCount = OfflineQueue.shared.getQueueCount()
                Task { await syncLocalHealthKit() }
            }
            .onChange(of: viewModel.dashboardPayload?.meta.forDate) { _, newDate in
                // Reset stale banner when payload date changes (new fetch)
                if newDate != lastPayloadDate {
                    staleBannerDismissed = false
                    lastPayloadDate = newDate
                }
            }
            .alert("Health Access", isPresented: $showHealthPermission) {
                Button("Enable") {
                    Task {
                        try? await healthKit.requestAuthorization()
                        await syncLocalHealthKit()
                    }
                }
                Button("Not Now", role: .cancel) { }
            } message: {
                Text("Nexus reads weight and activity from Apple Health (Eufy scale, Apple Watch).")
            }
        }
    }

    // MARK: - Local HealthKit Sync (device-local, no API calls)

    private func syncLocalHealthKit() async {
        guard !isHealthKitSyncing else { return }
        guard healthKit.isHealthDataAvailable else { return }

        isHealthKitSyncing = true

        if !healthKit.isAuthorized {
            try? await healthKit.requestAuthorization()
        }

        guard healthKit.isAuthorized else {
            await MainActor.run { isHealthKitSyncing = false }
            return
        }

        async let weightResult = healthKit.fetchLatestWeight()
        async let stepsResult = healthKit.fetchTodaysSteps()
        async let caloriesResult = healthKit.fetchTodaysActiveCalories()
        async let weightHistoryResult = healthKit.fetchWeightHistory(days: 30)

        let weight = try? await weightResult
        let steps = (try? await stepsResult) ?? 0
        let calories = (try? await caloriesResult) ?? 0
        let history = (try? await weightHistoryResult) ?? []

        await MainActor.run {
            localWeight = weight?.weight
            localSteps = steps
            localCalories = calories
            weightHistory = history
            isHealthKitSyncing = false
        }

        // Sync weight to Nexus backend (fire-and-forget)
        if let w = weight?.weight {
            _ = try? await NexusAPI.shared.logWeight(kg: w)
        }

        // Save recovery to widget storage from unified payload
        if let payload = viewModel.dashboardPayload,
           let score = payload.todayFacts.recoveryScore {
            SharedStorage.shared.saveRecoveryData(
                score: score,
                hrv: payload.todayFacts.hrv,
                rhr: payload.todayFacts.rhr
            )
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting)
                .font(.title2)
                .fontWeight(.bold)

            Text(Date(), style: .date)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 8) {
            // Offline banner - prominent indicator when network unavailable
            if !networkMonitor.isConnected {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.slash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offline")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text(viewModel.dashboardPayload != nil ? "Showing cached data" : "Connect to load data")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    // Pending queue count if any
                    if pendingCount > 0 {
                        Text("\(pendingCount) queued")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.85))
                .cornerRadius(12)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            // Cache fallback banner - when online but showing cached data due to fetch failure
            else if viewModel.dataSource == .cache && viewModel.errorMessage != nil {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise.icloud")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Showing Cached Data")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        if let lastSync = viewModel.lastSyncDate {
                            Text("Last synced \(lastSync, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Retry") {
                        viewModel.errorMessage = nil
                        viewModel.loadTodaysSummary()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Error banner (only show if not already showing cache fallback banner)
            if let error = viewModel.errorMessage, viewModel.dataSource != .cache {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.nexusWarning)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Retry") {
                        viewModel.errorMessage = nil
                        viewModel.loadTodaysSummary()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.nexusPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.nexusWarning.opacity(0.12))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Stale feeds banner - shows when data sources are outdated
            if viewModel.hasStaleFeeds && !staleBannerDismissed {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundColor(.orange)
                    Text("Some data may be outdated: \(viewModel.staleFeeds.map { formatFeedName($0) }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        withAnimation { staleBannerDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                // Network status badge
                NexusStatusBadge(status: networkMonitor.isConnected ? .online : .offline)

                // Pending items indicator
                if pendingCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .symbolEffect(.pulse, isActive: true)
                        Text("\(pendingCount) pending")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.nexusWarning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.nexusWarning.opacity(0.12))
                    .cornerRadius(8)
                }

                Spacer()

                // Last sync
                if let lastSync = viewModel.lastSyncDate {
                    Text("Updated \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Health Section (WHOOP from unified payload + local HealthKit)

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            healthSectionHeader

            VStack(spacing: 8) {
                // WHOOP Recovery & Sleep (from unified dashboard payload)
                WHOOPRecoveryRow(recovery: viewModel.recoveryMetrics, isLoading: viewModel.isLoading)
                WHOOPSleepRow(sleep: viewModel.sleepMetrics, isLoading: viewModel.isLoading)

                // HealthKit Connect Prompt
                if !healthKit.isAuthorized && healthKit.isHealthDataAvailable {
                    HealthKitConnectPrompt { showHealthPermission = true }
                }

                // HealthKit data (weight, steps, calories) - local device reads
                if healthKit.isAuthorized {
                    HealthKitDataRow(
                        weight: localWeight,
                        steps: localSteps,
                        calories: localCalories,
                        isLoading: isHealthKitSyncing,
                        hasWeightHistory: weightHistory.count >= 2
                    ) {
                        showWeightChart.toggle()
                    }

                    if showWeightChart && weightHistory.count >= 2 {
                        WeightHistoryChart(weightData: weightHistory)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var healthSectionHeader: some View {
        HStack {
            Text("Health")
                .font(.headline)

            Spacer()

            if isHealthKitSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Syncing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if healthKit.isAuthorized {
                Button(action: { Task { await syncLocalHealthKit() } }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.nexusPrimary)
                }
            } else if healthKit.isHealthDataAvailable {
                Button("Connect") { showHealthPermission = true }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.nexusPrimary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Data Available")
                .font(.headline)

            Text("Connect to the internet to load your dashboard.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.loadTodaysSummary()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.nexusPrimary)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helper Functions

    private func formatFeedName(_ feed: String) -> String {
        switch feed {
        case "whoop_recovery": return "WHOOP Recovery"
        case "whoop_sleep": return "WHOOP Sleep"
        case "whoop_strain": return "WHOOP Strain"
        case "weight": return "Weight"
        case "transactions": return "Transactions"
        default: return feed.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Summary Cards

    private var summaryCardsSection: some View {
        SummaryCardsSection(summary: viewModel.summary, isLoading: viewModel.isLoading)
    }

    // MARK: - Recent Logs

    private var recentLogsSection: some View {
        RecentLogsSection(recentLogs: viewModel.recentLogs)
    }
}

// MARK: - Legacy Support (keep SummaryCard for backwards compatibility)

struct SummaryCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var isLoading: Bool = false

    var body: some View {
        NexusStatCard(
            title: title,
            value: value,
            unit: unit,
            icon: icon,
            color: color,
            isLoading: isLoading
        )
    }
}

struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        EnhancedLogRow(entry: entry)
    }
}

#Preview {
    DashboardView(viewModel: DashboardViewModel())
}
