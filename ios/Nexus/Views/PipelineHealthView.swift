import SwiftUI

struct PipelineHealthView: View {
    @StateObject private var coordinator = SyncCoordinator.shared

    var body: some View {
        List {
            syncStatusSection
            pipelineFeedsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.nexusBackground)
        .navigationTitle("Pipeline Health")
        .refreshable {
            await coordinator.sync(SyncCoordinator.SyncDomain.dashboard)
        }
    }

    // MARK: - Sync Status Section

    private var syncStatusSection: some View {
        Section {
            ForEach(SyncCoordinator.SyncDomain.allCases, id: \.self) { domain in
                if let state = coordinator.domainStates[domain] {
                    HStack(spacing: 12) {
                        Image(systemName: domainIcon(domain))
                            .font(.system(size: 14))
                            .foregroundColor(domainColor(domain))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(domain.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if let lastSync = state.lastSuccessDate {
                                Text(formatAge(lastSync))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if state.isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: state.lastError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(state.lastError == nil ? .nexusSuccess : .nexusWarning)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("App Sync Status")
        } footer: {
            Text("Shows when this app last fetched data from the server.")
        }
    }

    // MARK: - Pipeline Feeds Section

    private var pipelineFeedsSection: some View {
        Section {
            if let feeds = coordinator.dashboardPayload?.feedStatus, !feeds.isEmpty {
                ForEach(feeds.sorted(by: { feedSortOrder($0) < feedSortOrder($1) })) { feed in
                    pipelineFeedRow(feed)
                }

                if let stale = coordinator.dashboardPayload?.staleFeeds, !stale.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.nexusWarning)
                        Text("Stale: \(stale.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.nexusWarning)
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
            Text("Server Pipeline")
        } footer: {
            Text("Shows when each data source last wrote to the database. Critical/stale feeds may need attention.")
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
    }

    // MARK: - Helpers

    private func domainIcon(_ domain: SyncCoordinator.SyncDomain) -> String {
        domain.icon
    }

    private func domainColor(_ domain: SyncCoordinator.SyncDomain) -> Color {
        domain.color
    }

    private func formatAge(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }

    private func feedStatusColor(_ status: FeedHealthStatus) -> Color {
        switch status {
        case .healthy, .ok: return .nexusSuccess
        case .stale: return .nexusWarning
        case .critical: return .nexusError
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
        case "receipts": return "receipt"
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
