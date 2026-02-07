import SwiftUI
import Combine

// MARK: - Insights View

struct HealthInsightsView: View {
    @ObservedObject var viewModel: HealthViewModel

    var body: some View {
        ScrollView {
            HealthInsightsContent(viewModel: viewModel)
        }
        .background(NexusTheme.Colors.background)
        .refreshable {
            SyncCoordinator.shared.syncAll(force: true)
            await viewModel.loadData()
        }
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let insight: HealthInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: insight.icon)
                    .font(.title2)
                    .foregroundColor(insight.color)

                Spacer()

                Text(insight.confidence.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(insight.confidence.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(insight.confidence.color.opacity(0.15))
                    .cornerRadius(8)
            }

            Text(insight.title)
                .font(.headline)

            Text(insight.detail)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusTheme.Colors.card)
        .cornerRadius(16)
    }
}

// MARK: - Data Source Status

enum DataSourceStatus {
    case healthy, stale, failed, unknown

    var dotColor: Color {
        switch self {
        case .healthy: return NexusTheme.Colors.Semantic.green
        case .stale: return NexusTheme.Colors.Semantic.amber
        case .failed: return NexusTheme.Colors.Semantic.red
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

#Preview {
    HealthView()
}
