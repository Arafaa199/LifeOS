import SwiftUI
import Combine

struct HealthInsightsContent: View {
    @ObservedObject var viewModel: HealthViewModel

    var body: some View {
        VStack(spacing: 20) {
            headerSection

            let insights = viewModel.generateInsights()

            if insights.isEmpty {
                collectingDataView
            } else {
                ForEach(insights) { insight in
                    InsightCard(insight: insight)
                }
            }

            dataQualitySection
        }
        .padding()
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

            if let facts = viewModel.todayFacts,
               let daysWithData = facts.daysWithData7d {
                VStack(spacing: 8) {
                    ProgressView(value: Double(daysWithData), total: 7)
                        .tint(NexusTheme.Colors.Semantic.green)

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
        case .healthy, .ok: return .healthy
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
                    color: NexusTheme.Colors.Semantic.amber,
                    status: whoopStatus
                )

                Divider()
                    .frame(height: 40)

                DataSourceIndicator(
                    name: "HealthKit",
                    icon: "heart.circle.fill",
                    color: NexusTheme.Colors.Semantic.purple,
                    status: healthKitStatus
                )
            }
            .padding()
            .background(NexusTheme.Colors.card)
            .cornerRadius(12)
        }
    }
}
