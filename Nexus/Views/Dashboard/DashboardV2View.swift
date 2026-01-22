import SwiftUI

struct DashboardV2View: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Status indicator
                    if !networkMonitor.isConnected {
                        offlineBanner
                    }

                    // Health card
                    healthCard

                    // Finance card
                    financeCard

                    // Recent activity card
                    recentActivityCard

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await viewModel.refresh()
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { viewModel.loadTodaysSummary() }) {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, isActive: viewModel.isLoading)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundColor(.white)
            Text("Offline - Showing cached data")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.85))
        .cornerRadius(12)
    }

    // MARK: - Health Card

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Health", systemImage: "heart.fill")
                .font(.headline)
                .foregroundColor(.red)

            HStack(spacing: 24) {
                // Recovery
                metricView(
                    value: viewModel.dashboardPayload?.todayFacts.recoveryScore.map { "\($0)%" } ?? "--",
                    label: "Recovery",
                    color: recoveryColor
                )

                // Sleep
                metricView(
                    value: formatSleep(viewModel.dashboardPayload?.todayFacts.sleepMinutes),
                    label: "Sleep",
                    color: .indigo
                )

                // Strain
                metricView(
                    value: viewModel.dashboardPayload?.todayFacts.strain.map { String(format: "%.1f", $0) } ?? "--",
                    label: "Strain",
                    color: .orange
                )

                // HRV
                metricView(
                    value: viewModel.dashboardPayload?.todayFacts.hrv.map { "\($0)" } ?? "--",
                    label: "HRV",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var recoveryColor: Color {
        guard let score = viewModel.dashboardPayload?.todayFacts.recoveryScore else { return .gray }
        switch score {
        case 67...100: return .green
        case 34...66: return .yellow
        default: return .red
        }
    }

    // MARK: - Finance Card

    private var financeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Spending Today", systemImage: "creditcard.fill")
                .font(.headline)
                .foregroundColor(.nexusFinance)

            HStack(spacing: 24) {
                // Total
                metricView(
                    value: formatCurrency(viewModel.dashboardPayload?.todayFacts.spendTotal),
                    label: "Total",
                    color: .nexusFinance
                )

                // Groceries
                metricView(
                    value: formatCurrency(viewModel.dashboardPayload?.todayFacts.spendGroceries),
                    label: "Groceries",
                    color: .green
                )

                // Restaurants
                metricView(
                    value: formatCurrency(viewModel.dashboardPayload?.todayFacts.spendRestaurants),
                    label: "Eating Out",
                    color: .orange
                )
            }

            // Transaction count
            if let count = viewModel.dashboardPayload?.todayFacts.transactionCount, count > 0 {
                Text("\(count) transaction\(count == 1 ? "" : "s") today")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: - Recent Activity Card

    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent Activity", systemImage: "clock.fill")
                .font(.headline)
                .foregroundColor(.secondary)

            if viewModel.recentLogs.isEmpty {
                Text("No recent activity")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(viewModel.recentLogs.prefix(5))) { log in
                    HStack {
                        Circle()
                            .fill(colorForLogType(log.type))
                            .frame(width: 8, height: 8)

                        Text(log.description)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()

                        Text(log.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: - Helpers

    private func metricView(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(value == "--" ? .secondary : color)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatSleep(_ minutes: Int?) -> String {
        guard let minutes = minutes, minutes > 0 else { return "--" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    private func formatCurrency(_ amount: Double?) -> String {
        guard let amount = amount else { return "--" }
        if amount == 0 { return "0" }
        return String(format: "%.0f", abs(amount))
    }

    private func colorForLogType(_ type: LogType) -> Color {
        switch type {
        case .food: return .nexusFood
        case .water: return .nexusWater
        case .weight: return .nexusWeight
        case .mood: return .nexusMood
        case .note: return .nexusPrimary
        case .other: return .gray
        }
    }
}

#Preview {
    DashboardV2View(viewModel: DashboardViewModel())
}
