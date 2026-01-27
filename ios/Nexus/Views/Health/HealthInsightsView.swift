import SwiftUI
import Combine

// MARK: - Insights View

struct HealthInsightsView: View {
    @ObservedObject var viewModel: HealthViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Insights
                let insights = viewModel.generateInsights()

                if insights.isEmpty {
                    collectingDataView
                } else {
                    ForEach(insights) { insight in
                        InsightCard(insight: insight)
                    }
                }

                // Data quality indicator
                dataQualitySection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            SyncCoordinator.shared.syncAll(force: true)
            await viewModel.loadData()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Insights")
                .font(.title2)
                .fontWeight(.bold)

            Text("Patterns we've noticed in your data. Only showing conclusions backed by evidence.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Collecting Data View

    private var collectingDataView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hourglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Collecting data — insights will appear soon")
                .font(.headline)

            Text("We need a few more days of tracking to identify meaningful patterns. Keep logging!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Progress indicator
            if let facts = viewModel.todayFacts,
               let daysWithData = facts.daysWithData7d {
                VStack(spacing: 8) {
                    ProgressView(value: Double(daysWithData), total: 7)
                        .tint(.nexusHealth)

                    Text("\(daysWithData) of 7 days tracked this week")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 40)
    }

    private var healthKitStatus: DataSourceStatus {
        if viewModel.healthKitSyncError { return .failed }
        switch HealthKitManager.shared.permissionStatus {
        case .working: return .healthy
        case .requested: return .stale
        case .notSetUp: return .unknown
        case .failed: return .failed
        }
    }

    private var whoopStatus: DataSourceStatus {
        guard let feed = viewModel.feedStatus.first(where: { $0.feed.lowercased().contains("whoop") }) else {
            return .unknown
        }
        switch feed.status {
        case .healthy: return .healthy
        case .stale: return .stale
        case .critical: return .failed
        case .unknown: return .unknown
        }
    }

    // MARK: - Data Quality Section

    private var dataQualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Sources")
                .font(.headline)

            HStack(spacing: 16) {
                DataSourceIndicator(
                    name: "WHOOP",
                    icon: "w.circle.fill",
                    color: .orange,
                    status: whoopStatus
                )

                Divider()
                    .frame(height: 40)

                DataSourceIndicator(
                    name: "HealthKit",
                    icon: "heart.circle.fill",
                    color: .red,
                    status: healthKitStatus
                )
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let insight: HealthInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and confidence
            HStack {
                Image(systemName: insight.icon)
                    .font(.title2)
                    .foregroundColor(insight.color)

                Spacer()

                // Confidence badge
                Text(insight.confidence.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(insight.confidence.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(insight.confidence.color.opacity(0.15))
                    .cornerRadius(8)
            }

            // Title
            Text(insight.title)
                .font(.headline)

            // Detail
            Text(insight.detail)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Data Source Status

enum DataSourceStatus {
    case healthy, stale, failed, unknown

    var dotColor: Color {
        switch self {
        case .healthy: return .green
        case .stale: return .orange
        case .failed: return .red
        case .unknown: return .gray
        }
    }

    var label: String {
        switch self {
        case .healthy: return "Active"
        case .stale: return "Stale"
        case .failed: return "Error"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Data Source Indicator

struct DataSourceIndicator: View {
    let name: String
    let icon: String
    let color: Color
    let status: DataSourceStatus

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(status == .healthy ? color : .gray)

            Text(name)
                .font(.caption)
                .fontWeight(.medium)

            HStack(spacing: 4) {
                Circle()
                    .fill(status.dotColor)
                    .frame(width: 6, height: 6)

                Text(status.label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
