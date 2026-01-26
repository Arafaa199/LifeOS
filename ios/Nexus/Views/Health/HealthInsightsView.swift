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

    // MARK: - Data Quality Section

    private var dataQualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Sources")
                .font(.headline)

            HStack(spacing: 16) {
                // WHOOP Status
                DataSourceIndicator(
                    name: "WHOOP",
                    icon: "w.circle.fill",
                    color: .orange,
                    status: viewModel.feedStatus.first(where: { $0.feed.lowercased().contains("whoop") })?.status.rawValue ?? "unknown"
                )

                Divider()
                    .frame(height: 40)

                // HealthKit Status
                DataSourceIndicator(
                    name: "HealthKit",
                    icon: "heart.circle.fill",
                    color: .red,
                    status: viewModel.healthKitAuthorized ? "connected" : "disconnected"
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

// MARK: - Data Source Indicator

struct DataSourceIndicator: View {
    let name: String
    let icon: String
    let color: Color
    let status: String

    private var isConnected: Bool {
        status.lowercased() == "healthy" ||
        status.lowercased() == "ok" ||
        status.lowercased() == "connected"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isConnected ? color : .gray)

            Text(name)
                .font(.caption)
                .fontWeight(.medium)

            HStack(spacing: 4) {
                Circle()
                    .fill(isConnected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                Text(isConnected ? "Connected" : "Check status")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
