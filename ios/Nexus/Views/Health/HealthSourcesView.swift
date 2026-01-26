import SwiftUI

// MARK: - Health Sources View

struct HealthSourcesView: View {
    @ObservedObject var viewModel: HealthViewModel
    @State private var isSyncing = false

    var body: some View {
        List {
            // WHOOP Section
            Section("WHOOP") {
                let whoopFeed = viewModel.feedStatus.first { $0.feed.lowercased().contains("whoop") }

                HStack {
                    Image(systemName: "w.circle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("WHOOP")
                            .font(.headline)

                        if let feed = whoopFeed {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor(feed.status))
                                    .frame(width: 8, height: 8)

                                Text(feed.status.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Not configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if let feed = whoopFeed, let lastSync = feed.lastSync {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Last sync")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatLastSync(lastSync))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }

                // WHOOP metrics
                VStack(alignment: .leading, spacing: 8) {
                    Text("Metrics from WHOOP:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        MetricBadge(name: "Recovery", enabled: true)
                        MetricBadge(name: "HRV", enabled: true)
                        MetricBadge(name: "RHR", enabled: true)
                        MetricBadge(name: "Sleep", enabled: true)
                        MetricBadge(name: "Strain", enabled: true)
                    }
                }
            }

            // HealthKit Section
            Section("Apple Health") {
                HStack {
                    Image(systemName: "heart.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("HealthKit")
                            .font(.headline)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(viewModel.healthKitAuthorized ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)

                            Text(viewModel.healthKitAuthorized ? "Connected" : "Not authorized")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if let lastSync = viewModel.lastHealthKitSync {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Last sync")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(lastSync, style: .relative)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }

                // HealthKit metrics
                VStack(alignment: .leading, spacing: 8) {
                    Text("Metrics from HealthKit:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        MetricBadge(name: "Steps", enabled: true)
                        MetricBadge(name: "Active Energy", enabled: true)
                        MetricBadge(name: "Weight", enabled: true)
                        MetricBadge(name: "Resting HR", enabled: true)
                    }

                    HStack(spacing: 12) {
                        MetricBadge(name: "HRV", enabled: true)
                        MetricBadge(name: "Sleep", enabled: true)
                    }
                }

                // Sample count
                if viewModel.healthKitSampleCount > 0 {
                    HStack {
                        Text("Samples synced")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(viewModel.healthKitSampleCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }

                // Sync button
                Button(action: syncHealthKit) {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Sync Now")
                    }
                }
                .disabled(isSyncing || !viewModel.healthKitAuthorized)
            }

            // Data Priority Rules
            Section("Data Priority") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("When data overlaps:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    PriorityRow(metric: "Recovery & Sleep", source: "WHOOP wins", reason: "More accurate tracking")
                    PriorityRow(metric: "Steps & Calories", source: "HealthKit", reason: "Native integration")
                    PriorityRow(metric: "Weight", source: "HealthKit", reason: "Eufy scale syncs here")
                    PriorityRow(metric: "HRV", source: "WHOOP wins", reason: "24/7 monitoring")
                }
            }

            // Notes
            Section {
                Text("Data is never silently merged. Each metric has a single deterministic source.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Health Sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func syncHealthKit() {
        isSyncing = true
        Task {
            await viewModel.refreshHealthKit()
            isSyncing = false
        }
    }

    private func statusColor(_ status: FeedHealthStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .stale: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }

    private func formatLastSync(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            let relFormatter = RelativeDateTimeFormatter()
            relFormatter.unitsStyle = .abbreviated
            return relFormatter.localizedString(for: date, relativeTo: Date())
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            let relFormatter = RelativeDateTimeFormatter()
            relFormatter.unitsStyle = .abbreviated
            return relFormatter.localizedString(for: date, relativeTo: Date())
        }

        return dateString
    }
}

// MARK: - Supporting Components

struct MetricBadge: View {
    let name: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(enabled ? Color.green : Color.gray)
                .frame(width: 6, height: 6)

            Text(name)
                .font(.caption2)
        }
        .foregroundColor(enabled ? .primary : .secondary)
    }
}

struct PriorityRow: View {
    let metric: String
    let source: String
    let reason: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric)
                    .font(.subheadline)
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(source)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.nexusHealth)
        }
    }
}

#Preview {
    NavigationView {
        HealthSourcesView(viewModel: HealthViewModel())
    }
}
