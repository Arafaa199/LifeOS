import SwiftUI

/// Developer debug section with diagnostic info and manual controls
struct DebugSection: View {
    @ObservedObject var coordinator: SyncCoordinator

    var body: some View {
        Section {
            // Force Sync (debug only)
            Button {
                coordinator.syncAll(force: true)
                let haptics = UINotificationFeedbackGenerator()
                haptics.notificationOccurred(.success)
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                    Text("Force Sync All")
                        .fontWeight(.medium)
                    Spacer()
                    if coordinator.anySyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .disabled(coordinator.anySyncing)

            NavigationLink(destination: DebugView()) {
                SettingsRow(
                    icon: "ladybug",
                    iconColor: .orange,
                    title: "API Debug Panel",
                    subtitle: "Test APIs and view logs"
                )
            }

            // Dashboard Payload Debug
            DisclosureGroup {
                dashboardDebugContent
            } label: {
                SettingsRow(
                    icon: "doc.text.magnifyingglass",
                    iconColor: .blue,
                    title: "Dashboard Payload",
                    subtitle: coordinator.dashboardPayload != nil ? "Loaded" : "Empty"
                )
            }

            // WHOOP Debug
            if let debug = coordinator.whoopDebugInfo {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        debugRow("Raw lastSync", debug.rawLastSync ?? "nil")
                        debugRow("Parsed date", debug.parsedDate?.description ?? "nil")
                        debugRow("Checked at", debug.checkedAt.description)
                        debugRow("Age (hours)", debug.ageHours.map { String(format: "%.1f", $0) } ?? "nil")
                        debugRow("Server status", debug.serverStatus)
                        debugRow("Server hours", debug.serverHoursSinceSync.map { String(format: "%.1f", $0) } ?? "nil")
                    }
                    .font(.caption2.monospaced())
                } label: {
                    SettingsRow(
                        icon: "w.circle.fill",
                        iconColor: .orange,
                        title: "WHOOP Debug",
                        subtitle: debug.serverStatus
                    )
                }
            }

            // Sync State Debug
            DisclosureGroup {
                syncStateDebugContent
            } label: {
                SettingsRow(
                    icon: "arrow.triangle.2.circlepath.circle",
                    iconColor: .green,
                    title: "Sync State",
                    subtitle: coordinator.anySyncing ? "Syncing..." : "Idle"
                )
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Diagnostic info for troubleshooting. Force Sync bypasses debounce.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Debug Content

    @ViewBuilder
    private var dashboardDebugContent: some View {
        if let payload = coordinator.dashboardPayload {
            VStack(alignment: .leading, spacing: 6) {
                debugRow("Schema Version", "\(payload.meta.schemaVersion)")
                debugRow("Generated At", payload.meta.generatedAt)
                debugRow("Target Date", payload.meta.forDate)

                Divider().padding(.vertical, 4)

                if let facts = payload.todayFacts {
                    debugRow("Recovery", facts.recoveryScore.map { "\($0)%" } ?? "nil")
                    debugRow("HRV", facts.hrv.map { String(format: "%.1f", $0) } ?? "nil")
                    debugRow("Sleep Hours", String(format: "%.1f", facts.sleepHours))
                    debugRow("Weight (kg)", facts.weightKg.map { String(format: "%.1f", $0) } ?? "nil")
                    debugRow("Spend Total", facts.spendTotal.map { String(format: "%.2f", $0) } ?? "nil")
                    debugRow("Data Completeness", facts.dataCompleteness.map { String(format: "%.0f%%", $0 * 100) } ?? "nil")
                } else {
                    Text("todayFacts: nil")
                        .foregroundColor(.orange)
                }

                Divider().padding(.vertical, 4)

                debugRow("Feed Status Count", "\(payload.feedStatus.count)")
                debugRow("Stale Feeds", payload.staleFeeds.isEmpty ? "None" : payload.staleFeeds.joined(separator: ", "))
                debugRow("Trends Count", "\(payload.trends.count)")

                if let insights = payload.dailyInsights,
                   let ranked = insights.rankedInsights {
                    debugRow("Insights Count", "\(ranked.count)")
                } else {
                    debugRow("Insights", "nil")
                }
            }
            .font(.caption2.monospaced())
            .padding(.vertical, 4)
        } else {
            Text("No dashboard payload loaded")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var syncStateDebugContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SyncCoordinator.SyncDomain.allCases) { domain in
                let state = coordinator.domainStates[domain] ?? DomainState()
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(domain.displayName)
                            .fontWeight(.medium)
                        Spacer()
                        Text(state.isSyncing ? "Syncing" : "Idle")
                            .foregroundColor(state.isSyncing ? .orange : .secondary)
                    }
                    if let lastSuccess = state.lastSuccessDate {
                        debugRow("Last Success", formatDebugDate(lastSuccess))
                    }
                    if let error = state.lastError {
                        debugRow("Error", error)
                            .foregroundColor(.red)
                    }
                    if let detail = state.detail {
                        debugRow("Detail", detail)
                    }
                    debugRow("Staleness", state.staleness.label)
                }
                .padding(.vertical, 4)

                if domain != SyncCoordinator.SyncDomain.allCases.last {
                    Divider()
                }
            }

            Divider().padding(.vertical, 4)

            if let cacheAge = coordinator.cacheAgeFormatted {
                debugRow("Cache Age", cacheAge)
            }
            debugRow("Any Syncing", coordinator.anySyncing ? "Yes" : "No")
        }
        .font(.caption2.monospaced())
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatDebugDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
