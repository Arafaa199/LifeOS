import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var healthKit = HealthKitManager.shared
    @State private var pendingCount = 0
    @State private var isHealthSyncing = false
    @State private var showHealthPermission = false

    // Local HealthKit data (weight, steps, calories)
    @State private var localWeight: Double?
    @State private var localSteps: Int = 0
    @State private var localCalories: Int = 0

    // Weight history for chart
    @State private var weightHistory: [(date: Date, weight: Double)] = []
    @State private var showWeightChart = false

    // WHOOP data from Nexus API
    @State private var whoopData: SleepData?
    @State private var whoopError: String?
    @State private var whoopLastFetched: Date?

    // HealthKit sleep fallback (when WHOOP unavailable)
    @State private var healthKitSleep: HealthKitManager.SleepData?
    @State private var usingHealthKitFallback = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with greeting
                    headerSection

                    // Network & Sync Status
                    statusBar

                    // Daily Summary Cards
                    summaryCardsSection

                    // Health Section (HealthKit + WHOOP from API)
                    healthSection

                    // Recent Logs Section
                    recentLogsSection
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await viewModel.refresh()
                await syncAllHealthData()
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
                Task { await syncAllHealthData() }
            }
            .alert("Health Access", isPresented: $showHealthPermission) {
                Button("Enable") {
                    Task {
                        try? await healthKit.requestAuthorization()
                        await syncAllHealthData()
                    }
                }
                Button("Not Now", role: .cancel) { }
            } message: {
                Text("Nexus reads weight and activity from Apple Health (Eufy scale, Apple Watch).")
            }
        }
    }

    // MARK: - Health Sync

    private func syncAllHealthData() async {
        guard !isHealthSyncing else { return }
        isHealthSyncing = true
        whoopError = nil
        usingHealthKitFallback = false

        // Fetch HealthKit local data and WHOOP data from API in parallel
        async let localData = fetchLocalHealthData()
        async let whoopResponse = NexusAPI.shared.fetchSleepData()

        _ = await localData

        do {
            let response = try await whoopResponse
            if response.success {
                await MainActor.run {
                    whoopData = response.data
                    whoopError = nil
                    whoopLastFetched = Date()
                    healthKitSleep = nil
                    usingHealthKitFallback = false

                    // Save to SharedStorage for widget
                    if let recovery = response.data?.recovery,
                       let score = recovery.recoveryScore {
                        SharedStorage.shared.saveRecoveryData(
                            score: score,
                            hrv: recovery.hrv,
                            rhr: recovery.rhr
                        )
                    }
                }
            } else {
                await MainActor.run { whoopError = "Failed to load WHOOP data" }
                await tryHealthKitSleepFallback()
            }
        } catch {
            await MainActor.run { whoopError = error.localizedDescription }
            await tryHealthKitSleepFallback()
        }

        await MainActor.run { isHealthSyncing = false }
    }

    private func tryHealthKitSleepFallback() async {
        guard healthKit.isAuthorized else { return }

        do {
            if let sleepData = try await healthKit.fetchLastNightSleep() {
                await MainActor.run {
                    healthKitSleep = sleepData
                    usingHealthKitFallback = true
                }
            }
        } catch {
            // HealthKit fallback also failed, keep the original error
        }
    }

    private func fetchLocalHealthData() async {
        guard healthKit.isHealthDataAvailable else { return }

        if !healthKit.isAuthorized {
            try? await healthKit.requestAuthorization()
        }

        guard healthKit.isAuthorized else { return }

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
        }

        // Sync weight to Nexus backend
        if let w = weight?.weight {
            _ = try? await NexusAPI.shared.logWeight(kg: w)
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
                        Text("No Internet Connection")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("Changes will sync when back online")
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

            // Error banner
            if let error = viewModel.errorMessage {
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

    // MARK: - Health Section (HealthKit + WHOOP)

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            healthSectionHeader
            staleDataIndicator

            VStack(spacing: 8) {
                // WHOOP Error State
                if whoopError != nil && whoopData == nil && !isHealthSyncing && !usingHealthKitFallback {
                    WHOOPErrorView(errorMessage: whoopError) {
                        Task { await syncAllHealthData() }
                    }
                }

                // HealthKit Sleep Fallback
                if usingHealthKitFallback, let hkSleep = healthKitSleep {
                    HealthKitSleepFallbackView(sleepData: hkSleep) {
                        Task { await syncAllHealthData() }
                    }
                }

                // WHOOP Recovery & Sleep
                WHOOPRecoveryRow(recovery: whoopData?.recovery, isLoading: isHealthSyncing)
                WHOOPSleepRow(sleep: whoopData?.sleep, isLoading: isHealthSyncing)

                // HealthKit Connect Prompt
                if !healthKit.isAuthorized && healthKit.isHealthDataAvailable {
                    HealthKitConnectPrompt { showHealthPermission = true }
                }

                // HealthKit data (weight, steps, calories)
                if healthKit.isAuthorized {
                    HealthKitDataRow(
                        weight: localWeight,
                        steps: localSteps,
                        calories: localCalories,
                        isLoading: isHealthSyncing,
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

            if isHealthSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Syncing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if healthKit.isAuthorized {
                Button(action: { Task { await syncAllHealthData() } }) {
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

    @ViewBuilder
    private var staleDataIndicator: some View {
        if let lastFetched = whoopLastFetched, whoopData != nil {
            let minutesAgo = Int(-lastFetched.timeIntervalSinceNow / 60)
            let isStale = minutesAgo >= 60

            HStack(spacing: 6) {
                if isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.nexusWarning)
                }
                Text("Updated \(formatTimeAgo(lastFetched))")
                    .font(.caption)
                    .foregroundColor(isStale ? .nexusWarning : .secondary)
            }
            .padding(.horizontal)
        }
    }

    private func formatTimeAgo(_ date: Date) -> String {
        TimeFormatter.formatTimeAgo(date)
    }

    // MARK: - Summary Cards

    private var summaryCardsSection: some View {
        SummaryCardsSection(summary: viewModel.summary, isLoading: viewModel.isLoading)
    }

    // MARK: - Recent Logs

    private var recentLogsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)

                Spacer()

                if !viewModel.recentLogs.isEmpty {
                    Text("\(viewModel.recentLogs.count) entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            if viewModel.recentLogs.isEmpty {
                NexusEmptyState(
                    icon: "list.bullet.clipboard",
                    title: "No logs yet",
                    message: "Start tracking your day!\nUse the Log tab to add entries."
                )
                .frame(maxWidth: .infinity)
                .nexusCard()
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.recentLogs.prefix(8).enumerated()), id: \.element.id) { index, log in
                        EnhancedLogRow(entry: log)

                        if index < min(viewModel.recentLogs.count - 1, 7) {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(Color.nexusCardBackground)
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Enhanced Log Row

struct EnhancedLogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 12) {
            // Icon with colored background
            ZStack {
                Circle()
                    .fill(colorForType(entry.type).opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: entry.type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorForType(entry.type))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Nutrition info badges
            VStack(alignment: .trailing, spacing: 4) {
                if let calories = entry.calories {
                    Text("\(calories) cal")
                        .nexusChip(color: .nexusFood)
                }

                if let protein = entry.protein {
                    Text(String(format: "%.0fg", protein))
                        .nexusChip(color: .nexusProtein)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func colorForType(_ type: LogType) -> Color {
        ColorHelper.color(for: type)
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
