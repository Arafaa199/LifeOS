import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var pendingCount = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Network & Sync Status Bar
                    HStack(spacing: 12) {
                        // Network status
                        HStack(spacing: 4) {
                            Image(systemName: networkMonitor.isConnected ? networkMonitor.connectionType.icon : "wifi.slash")
                                .foregroundColor(networkMonitor.isConnected ? .green : .orange)
                                .font(.caption)
                            Text(networkMonitor.isConnected ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundColor(networkMonitor.isConnected ? .secondary : .orange)
                        }

                        // Pending items indicator
                        if pendingCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                    .symbolEffect(.pulse, isActive: true)
                                Text("\(pendingCount) pending")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
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
                    .padding(.top, 8)

                    // Daily Summary Cards
                    VStack(spacing: 15) {
                        SummaryCard(
                            title: "Calories",
                            value: "\(viewModel.summary.totalCalories)",
                            unit: "kcal",
                            icon: "flame.fill",
                            color: .orange,
                            isLoading: viewModel.isLoading
                        )

                        SummaryCard(
                            title: "Protein",
                            value: String(format: "%.1f", viewModel.summary.totalProtein),
                            unit: "g",
                            icon: "bolt.fill",
                            color: .red,
                            isLoading: viewModel.isLoading
                        )

                        SummaryCard(
                            title: "Water",
                            value: "\(viewModel.summary.totalWater)",
                            unit: "ml",
                            icon: "drop.fill",
                            color: .blue,
                            isLoading: viewModel.isLoading
                        )

                        if let weight = viewModel.summary.latestWeight {
                            SummaryCard(
                                title: "Weight",
                                value: String(format: "%.1f", weight),
                                unit: "kg",
                                icon: "scalemass.fill",
                                color: .green,
                                isLoading: viewModel.isLoading
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Recent Logs
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent Logs")
                            .font(.headline)
                            .padding(.horizontal)

                        if viewModel.recentLogs.isEmpty {
                            Text("No logs yet. Start logging!")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            ForEach(viewModel.recentLogs) { log in
                                LogRow(entry: log)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.top)
            }
            .refreshable {
                await viewModel.refresh()
                pendingCount = OfflineQueue.shared.getQueueCount()
            }
            .navigationTitle("Nexus")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { viewModel.loadTodaysSummary() }) {
                        Image(systemName: "arrow.clockwise")
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
}

struct SummaryCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var isLoading: Bool = false

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)
                .symbolEffect(.pulse, isActive: isLoading)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .bold()
                        .redacted(reason: isLoading ? .placeholder : [])
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack {
            Image(systemName: entry.type.icon)
                .foregroundColor(colorForType(entry.type))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.description)
                    .font(.subheadline)
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let calories = entry.calories {
                Text("\(calories) cal")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
    }

    private func colorForType(_ type: LogType) -> Color {
        switch type {
        case .food: return .orange
        case .water: return .blue
        case .weight: return .green
        case .mood: return .purple
        case .note: return .gray
        case .other: return .secondary
        }
    }
}
