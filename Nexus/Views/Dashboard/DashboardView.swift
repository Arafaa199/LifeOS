import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var pendingCount = 0

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

                    // Recent Logs Section
                    recentLogsSection
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await viewModel.refresh()
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
            }
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

#Preview {
    DashboardView(viewModel: DashboardViewModel())
}
