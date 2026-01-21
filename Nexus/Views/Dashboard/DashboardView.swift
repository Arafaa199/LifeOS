import SwiftUI

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

    // WHOOP data from Nexus API
    @State private var whoopData: SleepData?

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

        // Fetch HealthKit local data and WHOOP data from API in parallel
        async let localData = fetchLocalHealthData()
        async let whoopResponse = NexusAPI.shared.fetchSleepData()

        _ = await localData

        if let response = try? await whoopResponse, response.success {
            await MainActor.run { whoopData = response.data }
        }

        await MainActor.run { isHealthSyncing = false }
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

        let weight = try? await weightResult
        let steps = (try? await stepsResult) ?? 0
        let calories = (try? await caloriesResult) ?? 0

        await MainActor.run {
            localWeight = weight?.weight
            localSteps = steps
            localCalories = calories
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
                    ProgressView()
                        .scaleEffect(0.8)
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

            if !healthKit.isAuthorized && healthKit.isHealthDataAvailable {
                // Prompt to connect HealthKit
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
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    // WHOOP Recovery row (from API)
                    if let recovery = whoopData?.recovery {
                        HStack(spacing: 12) {
                            if let score = recovery.recoveryScore {
                                HealthMetricCard(
                                    title: "Recovery",
                                    value: "\(score)",
                                    unit: "%",
                                    icon: "heart.circle.fill",
                                    color: recoveryColor(score)
                                )
                            }

                            if let hrv = recovery.hrv {
                                HealthMetricCard(
                                    title: "HRV",
                                    value: String(format: "%.0f", hrv),
                                    unit: "ms",
                                    icon: "waveform.path.ecg",
                                    color: .purple
                                )
                            }

                            if let rhr = recovery.rhr {
                                HealthMetricCard(
                                    title: "Resting HR",
                                    value: "\(rhr)",
                                    unit: "bpm",
                                    icon: "heart.fill",
                                    color: .red
                                )
                            }
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
                                    color: .indigo
                                )
                            }

                            if let deep = sleep.deepSleepMin, deep > 0 {
                                HealthMetricCard(
                                    title: "Deep",
                                    value: formatDuration(deep),
                                    unit: "",
                                    icon: "moon.zzz.fill",
                                    color: .blue
                                )
                            }

                            if let perf = sleep.sleepPerformance {
                                HealthMetricCard(
                                    title: "Sleep Score",
                                    value: "\(perf)",
                                    unit: "%",
                                    icon: "sparkles",
                                    color: .cyan
                                )
                            }
                        }
                    }

                    // Local HealthKit data (weight, steps, calories)
                    HStack(spacing: 12) {
                        if let weight = localWeight {
                            HealthMetricCard(
                                title: "Weight",
                                value: String(format: "%.1f", weight),
                                unit: "kg",
                                icon: "scalemass.fill",
                                color: .nexusWeight
                            )
                        }

                        HealthMetricCard(
                            title: "Steps",
                            value: formatNumber(localSteps),
                            unit: "",
                            icon: "figure.walk",
                            color: .green
                        )

                        HealthMetricCard(
                            title: "Active Cal",
                            value: "\(localCalories)",
                            unit: "kcal",
                            icon: "flame.fill",
                            color: .orange
                        )
                    }
                }
                .padding(.horizontal)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    DashboardView(viewModel: DashboardViewModel())
}
