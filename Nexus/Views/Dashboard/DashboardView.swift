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

            // Stale data indicator when WHOOP data is >1 hour old
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

            VStack(spacing: 8) {
                // WHOOP Error State with Retry (only if no HealthKit fallback available)
                if whoopError != nil && whoopData == nil && !isHealthSyncing && !usingHealthKitFallback {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Couldn't load WHOOP data")
                                    .font(.subheadline.weight(.medium))
                                Text(whoopError ?? "Unknown error")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button(action: { Task { await syncAllHealthData() } }) {
                                Text("Retry")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.nexusPrimary)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // HealthKit Sleep Fallback (when WHOOP unavailable)
                    if usingHealthKitFallback, let hkSleep = healthKitSleep {
                        // Fallback notice
                        HStack(spacing: 8) {
                            Image(systemName: "applewatch")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Sleep data from Apple Watch (WHOOP unavailable)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: { Task { await syncAllHealthData() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundColor(.nexusPrimary)
                            }
                        }
                        .padding(.horizontal, 4)

                        // HealthKit sleep data cards
                        HStack(spacing: 12) {
                            HealthMetricCard(
                                title: "Sleep",
                                value: formatDuration(hkSleep.asleepMinutes),
                                unit: "",
                                icon: "bed.double.fill",
                                color: .indigo,
                                isLoading: false
                            )

                            if hkSleep.deepMinutes > 0 {
                                HealthMetricCard(
                                    title: "Deep",
                                    value: formatDuration(hkSleep.deepMinutes),
                                    unit: "",
                                    icon: "moon.zzz.fill",
                                    color: .blue,
                                    isLoading: false
                                )
                            }

                            if hkSleep.remMinutes > 0 {
                                HealthMetricCard(
                                    title: "REM",
                                    value: formatDuration(hkSleep.remMinutes),
                                    unit: "",
                                    icon: "brain.head.profile",
                                    color: .purple,
                                    isLoading: false
                                )
                            }
                        }

                        // Second row with efficiency if available
                        if hkSleep.sleepEfficiency > 0 {
                            HStack(spacing: 12) {
                                HealthMetricCard(
                                    title: "Efficiency",
                                    value: String(format: "%.0f", hkSleep.sleepEfficiency * 100),
                                    unit: "%",
                                    icon: "chart.bar.fill",
                                    color: .cyan,
                                    isLoading: false
                                )

                                if hkSleep.awakeMinutes > 0 {
                                    HealthMetricCard(
                                        title: "Awake",
                                        value: formatDuration(hkSleep.awakeMinutes),
                                        unit: "",
                                        icon: "eye.fill",
                                        color: .orange,
                                        isLoading: false
                                    )
                                }

                                // Spacer card if needed for alignment
                                if hkSleep.awakeMinutes == 0 {
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }

                    // WHOOP Recovery row (from API)
                    if let recovery = whoopData?.recovery {
                        HStack(spacing: 12) {
                            if let score = recovery.recoveryScore {
                                HealthMetricCard(
                                    title: "Recovery",
                                    value: "\(score)",
                                    unit: "%",
                                    icon: "heart.circle.fill",
                                    color: recoveryColor(score),
                                    isLoading: isHealthSyncing
                                )
                            }

                            if let hrv = recovery.hrv {
                                HealthMetricCard(
                                    title: "HRV",
                                    value: String(format: "%.0f", hrv),
                                    unit: "ms",
                                    icon: "waveform.path.ecg",
                                    color: .purple,
                                    isLoading: isHealthSyncing
                                )
                            }

                            if let rhr = recovery.rhr {
                                HealthMetricCard(
                                    title: "Resting HR",
                                    value: "\(rhr)",
                                    unit: "bpm",
                                    icon: "heart.fill",
                                    color: .red,
                                    isLoading: isHealthSyncing
                                )
                            }
                        }
                    } else if isHealthSyncing {
                        // Show placeholder cards while loading WHOOP data
                        HStack(spacing: 12) {
                            HealthMetricCard(title: "Recovery", value: "--", unit: "%", icon: "heart.circle.fill", color: .gray, isLoading: true)
                            HealthMetricCard(title: "HRV", value: "--", unit: "ms", icon: "waveform.path.ecg", color: .gray, isLoading: true)
                            HealthMetricCard(title: "Resting HR", value: "--", unit: "bpm", icon: "heart.fill", color: .gray, isLoading: true)
                        }
                    }

                    // WHOOP Sleep row (from API)
                    if let sleep = whoopData?.sleep {
                        HStack(spacing: 12) {
                            if sleep.totalSleepMin > 0 {
                                HealthMetricCard(
                                    title: "Sleep",
                                    value: formatDuration(sleep.totalSleepMin),
                                    unit: "",
                                    icon: "bed.double.fill",
                                    color: .indigo,
                                    isLoading: isHealthSyncing
                                )
                            }

                            if let deep = sleep.deepSleepMin, deep > 0 {
                                HealthMetricCard(
                                    title: "Deep",
                                    value: formatDuration(deep),
                                    unit: "",
                                    icon: "moon.zzz.fill",
                                    color: .blue,
                                    isLoading: isHealthSyncing
                                )
                            }

                            if let perf = sleep.sleepPerformance {
                                HealthMetricCard(
                                    title: "Sleep Score",
                                    value: "\(perf)",
                                    unit: "%",
                                    icon: "sparkles",
                                    color: .cyan,
                                    isLoading: isHealthSyncing
                                )
                            }
                        }
                    } else if isHealthSyncing {
                        // Show placeholder cards while loading sleep data
                        HStack(spacing: 12) {
                            HealthMetricCard(title: "Sleep", value: "--", unit: "", icon: "bed.double.fill", color: .gray, isLoading: true)
                            HealthMetricCard(title: "Deep", value: "--", unit: "", icon: "moon.zzz.fill", color: .gray, isLoading: true)
                            HealthMetricCard(title: "Sleep Score", value: "--", unit: "%", icon: "sparkles", color: .gray, isLoading: true)
                        }
                    }

                    // HealthKit Connect Prompt (if not authorized)
                    if !healthKit.isAuthorized && healthKit.isHealthDataAvailable {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.fill")
                                .font(.title2)
                                .foregroundColor(.pink)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connect Apple Health")
                                    .font(.subheadline.weight(.medium))
                                Text("Sync weight & activity from Eufy, Apple Watch")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.nexusCardBackground)
                        .cornerRadius(12)
                        .onTapGesture { showHealthPermission = true }
                    }

                    // Local HealthKit data (weight, steps, calories) - only if authorized
                    if healthKit.isAuthorized {
                        HStack(spacing: 12) {
                            if let weight = localWeight {
                                HealthMetricCard(
                                    title: "Weight",
                                    value: String(format: "%.1f", weight),
                                    unit: "kg",
                                    icon: "scalemass.fill",
                                    color: .nexusWeight,
                                    isLoading: isHealthSyncing
                                )
                                .onTapGesture {
                                    if weightHistory.count >= 2 {
                                        showWeightChart.toggle()
                                    }
                                }
                            }

                            HealthMetricCard(
                                title: "Steps",
                                value: formatNumber(localSteps),
                                unit: "",
                                icon: "figure.walk",
                                color: .green,
                                isLoading: isHealthSyncing
                            )

                            HealthMetricCard(
                                title: "Active Cal",
                                value: "\(localCalories)",
                                unit: "kcal",
                                icon: "flame.fill",
                                color: .orange,
                                isLoading: isHealthSyncing
                            )
                        }

                        // Weight history chart (expandable)
                        if showWeightChart && weightHistory.count >= 2 {
                            WeightHistoryChart(weightData: weightHistory)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal)
        }
    }

    private func recoveryColor(_ score: Int) -> Color {
        switch score {
        case 67...100: return .green
        case 34...66: return .yellow
        default: return .red
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    private func formatNumber(_ number: Int) -> String {
        number >= 1000 ? String(format: "%.1fk", Double(number) / 1000) : "\(number)"
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let minutes = Int(-date.timeIntervalSinceNow / 60)
        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes) min ago"
        } else {
            let hours = minutes / 60
            return hours == 1 ? "1 hr ago" : "\(hours) hrs ago"
        }
    }

    // MARK: - Summary Cards

    private var summaryCardsSection: some View {
        VStack(spacing: 12) {
            NexusStatCard(
                title: "Calories",
                value: "\(viewModel.summary.totalCalories)",
                unit: "kcal",
                icon: "flame.fill",
                color: .nexusFood,
                isLoading: viewModel.isLoading
            )

            NexusStatCard(
                title: "Protein",
                value: String(format: "%.1f", viewModel.summary.totalProtein),
                unit: "g",
                icon: "bolt.fill",
                color: .nexusProtein,
                isLoading: viewModel.isLoading
            )

            NexusStatCard(
                title: "Water",
                value: "\(viewModel.summary.totalWater)",
                unit: "ml",
                icon: "drop.fill",
                color: .nexusWater,
                isLoading: viewModel.isLoading
            )

            if let weight = viewModel.summary.latestWeight {
                NexusStatCard(
                    title: "Weight",
                    value: String(format: "%.1f", weight),
                    unit: "kg",
                    icon: "scalemass.fill",
                    color: .nexusWeight,
                    isLoading: viewModel.isLoading
                )
            }

            if let mood = viewModel.summary.mood {
                NexusStatCard(
                    title: "Mood",
                    value: "\(mood)",
                    unit: "/ 10",
                    icon: "face.smiling.fill",
                    color: .nexusMood,
                    isLoading: viewModel.isLoading
                )
            }
        }
        .padding(.horizontal)
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
        switch type {
        case .food: return .nexusFood
        case .water: return .nexusWater
        case .weight: return .nexusWeight
        case .mood: return .nexusMood
        case .note: return .secondary
        case .other: return .secondary
        }
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

// MARK: - Health Metric Card

struct HealthMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(isLoading ? .secondary : color)
                    .symbolEffect(.pulse, isActive: isLoading && value == "--")
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .opacity(isLoading ? 0.6 : 1.0)
                    .redacted(reason: isLoading && value == "--" ? .placeholder : [])
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(isLoading ? 0.6 : 1.0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((isLoading && value == "--" ? Color.gray : color).opacity(0.1))
        .cornerRadius(10)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

// MARK: - Weight History Chart

struct WeightHistoryChart: View {
    let weightData: [(date: Date, weight: Double)]

    private var chartData: [WeightDataPoint] {
        // Group by day and take the latest reading per day, limit to 30 days
        let calendar = Calendar.current
        var dailyWeights: [Date: Double] = [:]

        for (date, weight) in weightData {
            let day = calendar.startOfDay(for: date)
            // Keep the latest weight for each day
            if dailyWeights[day] == nil || date > day {
                dailyWeights[day] = weight
            }
        }

        return dailyWeights
            .map { WeightDataPoint(date: $0.key, weight: $0.value) }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }

    private var weightRange: (min: Double, max: Double) {
        let weights = chartData.map { $0.weight }
        let minW = (weights.min() ?? 0) - 1
        let maxW = (weights.max() ?? 100) + 1
        return (minW, maxW)
    }

    private var weightChange: Double? {
        guard chartData.count >= 2 else { return nil }
        let first = chartData.first!.weight
        let last = chartData.last!.weight
        return last - first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weight Trend")
                    .font(.subheadline.weight(.medium))

                Spacer()

                if let change = weightChange {
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption)
                        Text(String(format: "%+.1f kg", change))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(change >= 0 ? .orange : .green)
                }

                Text("30 days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if #available(iOS 16.0, *) {
                Chart(chartData) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(Color.nexusWeight.gradient)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.nexusWeight.opacity(0.3), Color.nexusWeight.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(Color.nexusWeight)
                    .symbolSize(20)
                }
                .chartYScale(domain: weightRange.min...weightRange.max)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let weight = value.as(Double.self) {
                                Text(String(format: "%.0f", weight))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 150)
            } else {
                // Fallback for iOS 15
                Text("Chart requires iOS 16+")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color.nexusWeight.opacity(0.08))
        .cornerRadius(12)
    }
}

struct WeightDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
}

#Preview {
    DashboardView(viewModel: DashboardViewModel())
}
