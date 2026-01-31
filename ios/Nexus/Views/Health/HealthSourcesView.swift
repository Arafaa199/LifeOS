import SwiftUI

// MARK: - Health Sources View

struct HealthSourcesView: View {
    @ObservedObject var viewModel: HealthViewModel
    @State private var isSyncing = false
    @State private var reauthMessage: String?
    @State private var showOpenSettings = false
    @State private var isReauthorizing = false

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
                                .fill(healthKitStatusColor)
                                .frame(width: 8, height: 8)

                            Text(healthKitStatusLabel)
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

                // Reauthorize HealthKit
                Button {
                    isReauthorizing = true
                    reauthMessage = nil
                    showOpenSettings = false
                    Task {
                        do {
                            let result = try await HealthKitManager.shared.checkAndReauthorize()
                            switch result {
                            case .prompted:
                                reauthMessage = "Authorization requested. Try Sync."
                            case .alreadyGranted:
                                reauthMessage = "Already granted. Try Sync."
                            case .likelyDenied:
                                reauthMessage = "Permission may be denied."
                                showOpenSettings = true
                            }
                        } catch {
                            reauthMessage = "HealthKit not available."
                        }
                        isReauthorizing = false
                    }
                } label: {
                    HStack {
                        if isReauthorizing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "lock.rotation")
                        }
                        Text("Reauthorize HealthKit")
                    }
                }
                .disabled(isReauthorizing)

                if let message = reauthMessage {
                    HStack(spacing: 6) {
                        Image(systemName: showOpenSettings ? "exclamationmark.triangle" : "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(showOpenSettings ? .orange : .green)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if showOpenSettings {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open Settings")
                        }
                    }
                }

                // All refresh goes through SyncCoordinator.syncAll
                Button {
                    isSyncing = true
                    SyncCoordinator.shared.syncAll(force: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isSyncing = false
                    }
                } label: {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Sync All")
                    }
                }
                .disabled(isSyncing)
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

    private var healthKitStatusLabel: String {
        switch HealthKitManager.shared.permissionStatus {
        case .working: return "Active"
        case .requested: return "Authorized (no query yet)"
        case .notSetUp: return "Not set up"
        case .failed: return "Not available"
        }
    }

    private var healthKitStatusColor: Color {
        switch HealthKitManager.shared.permissionStatus {
        case .working: return .green
        case .requested: return .orange
        case .notSetUp: return .gray
        case .failed: return .red
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
