import SwiftUI

/// Shows server-side data pipeline freshness (feed status)
struct PipelineHealthSection: View {
    @ObservedObject var coordinator: SyncCoordinator

    var body: some View {
        Section {
            if let feeds = coordinator.dashboardPayload?.feedStatus, !feeds.isEmpty {
                ForEach(feeds.sorted(by: { feedSortOrder($0) < feedSortOrder($1) })) { feed in
                    pipelineFeedRow(feed)
                }

                if let stale = coordinator.dashboardPayload?.staleFeeds, !stale.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
                        Text("Stale: \(stale.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                HStack {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                    Text("No pipeline data. Pull to refresh.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Pipeline Health")
        } footer: {
            Text("Server-side data freshness. Shows when each source last wrote to the database.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func pipelineFeedRow(_ feed: FeedStatus) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(feedStatusColor(feed.status))
                .frame(width: 8, height: 8)

            Image(systemName: feedIcon(feed.feed))
                .font(.system(size: 14))
                .foregroundColor(feedStatusColor(feed.status))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(feedDisplayName(feed.feed))
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let hours = feed.hoursSinceSync {
                    Text(formatPipelineAge(hours))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(feed.status.rawValue.capitalized)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(feedStatusColor(feed.status))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feedDisplayName(feed.feed)), \(feed.status.rawValue)")
    }

    private func feedStatusColor(_ status: FeedHealthStatus) -> Color {
        switch status {
        case .healthy, .ok: return NexusTheme.Colors.Semantic.green
        case .stale: return NexusTheme.Colors.Semantic.amber
        case .critical: return NexusTheme.Colors.Semantic.red
        case .unknown: return .secondary
        }
    }

    private func feedIcon(_ feed: String) -> String {
        switch feed.lowercased() {
        case "bank_sms", "transactions": return "creditcard"
        case "healthkit": return "heart"
        case "whoop", "whoop_recovery": return "bolt.heart"
        case "whoop_sleep": return "bed.double"
        case "whoop_strain": return "flame"
        case "receipts": return "doc.text"
        case "github": return "chevron.left.forwardslash.chevron.right"
        case "behavioral": return "figure.walk"
        case "location": return "location"
        case "manual": return "hand.raised"
        default: return "circle"
        }
    }

    private func feedDisplayName(_ feed: String) -> String {
        switch feed.lowercased() {
        case "bank_sms": return "Bank SMS"
        case "healthkit": return "HealthKit"
        case "whoop": return "WHOOP Recovery"
        case "whoop_recovery": return "WHOOP Recovery"
        case "whoop_sleep": return "WHOOP Sleep"
        case "whoop_strain": return "WHOOP Strain"
        case "receipts": return "Email Receipts"
        case "github": return "GitHub"
        case "behavioral": return "Behavioral"
        case "location": return "Location"
        case "manual": return "Manual Entries"
        case "transactions": return "Transactions"
        default: return feed.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func feedSortOrder(_ feed: FeedStatus) -> Int {
        switch feed.status {
        case .critical: return 0
        case .stale: return 1
        case .unknown: return 2
        case .healthy, .ok: return 3
        }
    }

    private func formatPipelineAge(_ hours: Double) -> String {
        if hours < 1 {
            let mins = Int(hours * 60)
            return "\(mins) min ago"
        } else if hours < 24 {
            return String(format: "%.1fh ago", hours)
        } else {
            let days = Int(hours / 24)
            return "\(days)d ago"
        }
    }
}
