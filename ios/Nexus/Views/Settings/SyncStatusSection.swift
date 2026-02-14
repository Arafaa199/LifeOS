import SwiftUI

/// Displays sync status for all domains (read-only, no manual buttons)
/// Pull-to-refresh on any tab handles sync - this just shows status
struct SyncStatusSection: View {
    @ObservedObject var coordinator: SyncCoordinator

    var body: some View {
        Section {
            ForEach(SyncCoordinator.SyncDomain.allCases) { domain in
                syncDomainRow(domain)
            }

            if let cacheAge = coordinator.cacheAgeFormatted {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Cache: \(cacheAge)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack {
                Text("Sync Status")
                Spacer()
                if coordinator.anySyncing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        } footer: {
            Text("Pull down on any tab to refresh all data.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func syncDomainRow(_ domain: SyncCoordinator.SyncDomain) -> some View {
        let state = coordinator.domainStates[domain] ?? DomainState()

        return HStack(spacing: 10) {
            Image(systemName: state.isSyncing ? "arrow.triangle.2.circlepath" : state.staleness.icon)
                .font(.system(size: 12))
                .foregroundColor(domainStatusColor(state))
                .frame(width: 16)

            Image(systemName: domain.icon)
                .font(.system(size: 14))
                .foregroundColor(domain.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(domain.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let error = state.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(NexusTheme.Colors.Semantic.amber)
                        .lineLimit(2)
                } else if let detail = state.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !state.isSyncing && state.isFromCache {
                Text("Cached")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(NexusTheme.Colors.Semantic.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(NexusTheme.Colors.Semantic.blue.opacity(0.1))
                    .cornerRadius(4)
            }

            if state.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
            } else if let lastSync = state.lastSuccessDate {
                Text(formatSyncTime(lastSync))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Not synced")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func domainStatusColor(_ state: DomainState) -> Color {
        if state.isSyncing { return .orange }
        return state.staleness.color
    }

    private func formatSyncTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
