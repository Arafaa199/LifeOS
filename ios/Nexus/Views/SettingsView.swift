import SwiftUI
import EventKit

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var coordinator = SyncCoordinator.shared
    @State private var webhookURL: String = ""
    @State private var apiKey: String = ""
    @State private var showingSaveConfirmation = false

    var body: some View {
        NavigationView {
            List {
                // Sync Center
                syncCenterSection

                // Pipeline Health (server-side data freshness)
                pipelineHealthSection

                // Domain Sync
                domainSyncSection

                // Sync Issues (failed offline items)
                syncIssuesSection

                // Connection Section
                Section {
                    NavigationLink(destination: TestConnectionView()) {
                        SettingsRow(
                            icon: "wifi",
                            iconColor: .nexusPrimary,
                            title: "Test Connection",
                            subtitle: "Verify your Nexus connection"
                        )
                    }
                } header: {
                    Text("Connection")
                }

                // Configuration Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Webhook URL", systemImage: "link")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("https://n8n.rfanw", text: $webhookURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("API Key", systemImage: "key")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        SecureField("Enter your API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    .padding(.vertical, 4)

                    Button(action: saveSettings) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Configuration")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.white)
                    .background(webhookURL.isEmpty ? Color.gray : Color.nexusPrimary)
                    .cornerRadius(10)
                    .disabled(webhookURL.isEmpty)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Configuration")
                }

                // Health & Data Sources
                Section {
                    NavigationLink(destination: HealthSourcesView(viewModel: HealthViewModel())) {
                        SettingsRow(
                            icon: "antenna.radiowaves.left.and.right",
                            iconColor: .nexusHealth,
                            title: "Health Sources",
                            subtitle: "WHOOP, Apple Health, data priority"
                        )
                    }

                    NavigationLink(destination: GitHubActivityView()) {
                        SettingsRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            iconColor: .primary,
                            title: "GitHub Activity",
                            subtitle: "Streaks, daily pushes, active repos"
                        )
                    }
                } header: {
                    Text("Data Sources")
                }

                // Extras
                Section {
                    NavigationLink(destination: WidgetSettingsView()) {
                        SettingsRow(
                            icon: "square.grid.2x2",
                            iconColor: .nexusFinance,
                            title: "Widgets",
                            subtitle: "Configure home screen widgets"
                        )
                    }

                    NavigationLink(destination: SiriShortcutsView()) {
                        SettingsRow(
                            icon: "mic.fill",
                            iconColor: .nexusMood,
                            title: "Siri Shortcuts",
                            subtitle: "Voice commands for quick logging"
                        )
                    }
                } header: {
                    Text("Extras")
                }

                // Data Section
                Section {
                    Button(role: .destructive) {
                        clearLocalData()
                    } label: {
                        SettingsRow(
                            icon: "trash",
                            iconColor: .nexusError,
                            title: "Clear Local Data",
                            subtitle: "Remove cached data from this device"
                        )
                    }
                } header: {
                    Text("Data")
                }

                // Developer / Debug Section
                Section {
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
                    Text("Diagnostic info for troubleshooting. Expand sections to see raw data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // About Section
                Section {
                    SettingsRow(
                        icon: "info.circle",
                        iconColor: .secondary,
                        title: "Version",
                        value: versionString
                    )

                    Link(destination: URL(string: "https://github.com/Arafaa199/LifeOS")!) {
                        SettingsRow(
                            icon: "book",
                            iconColor: .nexusPrimary,
                            title: "Documentation",
                            subtitle: "View guides and API reference",
                            showChevron: true
                        )
                    }

                    Link(destination: URL(string: "https://github.com/Arafaa199/LifeOS/issues")!) {
                        SettingsRow(
                            icon: "exclamationmark.bubble",
                            iconColor: .nexusWarning,
                            title: "Report an Issue",
                            subtitle: "Help us improve Nexus",
                            showChevron: true
                        )
                    }
                } header: {
                    Text("About")
                } footer: {
                    VStack(spacing: 8) {
                        Image(systemName: "n.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.nexusPrimary.opacity(0.5))

                        Text("Nexus - Life Data Hub")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .onAppear {
                webhookURL = settings.webhookBaseURL
                apiKey = KeychainManager.shared.apiKey ?? ""
            }
            .alert("Settings Saved", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your configuration has been updated.")
            }
        }
    }

    // MARK: - Pipeline Health Section (Server-side Data Trust)

    private var pipelineHealthSection: some View {
        Section {
            if let feeds = coordinator.dashboardPayload?.feedStatus, !feeds.isEmpty {
                ForEach(feeds.sorted(by: { feedSortOrder($0) < feedSortOrder($1) })) { feed in
                    pipelineFeedRow(feed)
                }

                if let stale = coordinator.dashboardPayload?.staleFeeds, !stale.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Stale: \(stale.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                HStack {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                    Text("No pipeline data. Sync dashboard first.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Pipeline Health")
        } footer: {
            Text("Server-side data pipeline freshness. Shows when each data source last wrote to the database.")
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
    }

    private func feedStatusColor(_ status: FeedHealthStatus) -> Color {
        switch status {
        case .healthy, .ok: return .green
        case .stale: return .orange
        case .critical: return .red
        case .unknown: return .gray
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
        // Critical first, then stale, then healthy
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

    // MARK: - Sync Center Section

    private var syncCenterSection: some View {
        Section {
            // Sync All button
            Button {
                coordinator.syncAll(force: true)
                let haptics = UINotificationFeedbackGenerator()
                haptics.notificationOccurred(.success)
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                    Text("Sync Now (All)")
                        .fontWeight(.medium)
                    Spacer()
                    if coordinator.anySyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.white)
            .background(coordinator.anySyncing ? Color.gray : Color.nexusPrimary)
            .cornerRadius(8)
            .disabled(coordinator.anySyncing)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // Per-domain rows (tap to sync individual domain)
            ForEach(SyncCoordinator.SyncDomain.allCases) { domain in
                Button {
                    Task { await coordinator.sync(domain) }
                } label: {
                    syncDomainRow(domain)
                }
                .buttonStyle(.plain)
            }

            // Cache age
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
            Text("Sync Center")
        } footer: {
            Text("Shows sync status for all data domains. Tap Sync Now to refresh everything.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Domain Sync Section

    private var domainSyncSection: some View {
        Section {
            Toggle(isOn: $settings.whoopSyncEnabled) {
                Label("WHOOP", systemImage: "w.circle.fill")
            }
            Toggle(isOn: $settings.financeSyncEnabled) {
                Label("Finance", systemImage: "chart.pie")
            }
            Toggle(isOn: $settings.healthKitSyncEnabled) {
                Label("HealthKit", systemImage: "heart.fill")
            }
            Toggle(isOn: $settings.calendarSyncEnabled) {
                Label("Calendar", systemImage: "calendar")
            }
        } header: {
            Text("Domain Sync")
        } footer: {
            Text("Disable domains to skip them during sync. Dashboard always syncs.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Sync Issues Section

    @StateObject private var offlineQueue = OfflineQueue.shared

    private var syncIssuesSection: some View {
        let failedCount = offlineQueue.failedItemCount
        let pendingCount = offlineQueue.pendingItemCount

        return Group {
            if failedCount > 0 || pendingCount > 0 {
                Section {
                    if pendingCount > 0 {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.orange)
                            Text("\(pendingCount) items pending sync")
                            Spacer()
                            if !NetworkMonitor.shared.isConnected {
                                Text("Offline")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if failedCount > 0 {
                        NavigationLink {
                            FailedItemsView()
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("\(failedCount) items failed to sync")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                } header: {
                    Text("Sync Issues")
                } footer: {
                    if failedCount > 0 {
                        Text("Failed items need your attention. Tap to review and retry or discard.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Domain Row

    private func syncDomainRow(_ domain: SyncCoordinator.SyncDomain) -> some View {
        let state = coordinator.domainStates[domain] ?? DomainState()

        return HStack(spacing: 10) {
            // Health indicator
            Image(systemName: state.isSyncing ? "arrow.triangle.2.circlepath" : state.staleness.icon)
                .font(.system(size: 12))
                .foregroundColor(domainStatusColor(state))
                .frame(width: 16)

            // Domain icon
            Image(systemName: domain.icon)
                .font(.system(size: 14))
                .foregroundColor(domain.color)
                .frame(width: 20)

            // Name + status
            VStack(alignment: .leading, spacing: 2) {
                Text(domain.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let error = state.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(2)
                } else if let detail = state.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Source badge (cache vs network)
            if !state.isSyncing && state.isFromCache {
                Text("Cached")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }

            // Sync time or spinner
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

    // MARK: - Debug Helpers

    @ViewBuilder
    private var dashboardDebugContent: some View {
        if let payload = coordinator.dashboardPayload {
            VStack(alignment: .leading, spacing: 6) {
                debugRow("Schema Version", "\(payload.meta.schemaVersion)")
                debugRow("Generated At", payload.meta.generatedAt)
                debugRow("Target Date", payload.meta.forDate)

                Divider()
                    .padding(.vertical, 4)

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

                Divider()
                    .padding(.vertical, 4)

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

            Divider()
                .padding(.vertical, 4)

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

    // MARK: - Domain Helpers

    private func domainStatusColor(_ state: DomainState) -> Color {
        if state.isSyncing { return .orange }
        return state.staleness.color
    }

    private func formatSyncTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func saveSettings() {
        settings.webhookBaseURL = webhookURL
        if !apiKey.isEmpty {
            KeychainManager.shared.apiKey = apiKey
        }
        showingSaveConfirmation = true

        let haptics = UINotificationFeedbackGenerator()
        haptics.notificationOccurred(.success)
    }

    private func clearLocalData() {
        CacheManager.shared.clearAll()
        SharedStorage.shared.resetDailyStats()

        let haptics = UINotificationFeedbackGenerator()
        haptics.notificationOccurred(.success)
    }
}

// MARK: - Settings Row Component

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let value = value {
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if showChevron {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Test Connection View

struct TestConnectionView: View {
    @State private var isTesting = false
    @State private var testResult = ""
    @State private var testSuccess = false
    @State private var responseTime: Double? = nil

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 160, height: 160)

                Image(systemName: statusIcon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(statusColor)
                    .symbolEffect(.pulse, isActive: isTesting)
            }

            VStack(spacing: 12) {
                Text(statusTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(testResult.isEmpty ? "Tap the button below to test your connection to the Nexus backend." : testResult)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let time = responseTime {
                    Text("Response time: \(String(format: "%.0f", time))ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }

            Spacer()

            Button(action: testConnection) {
                HStack(spacing: 10) {
                    if isTesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "wifi")
                            .font(.body.weight(.semibold))
                    }
                    Text(isTesting ? "Testing..." : "Test Connection")
                        .fontWeight(.semibold)
                }
            }
            .nexusPrimaryButton(disabled: isTesting)
            .disabled(isTesting)
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Connection Test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusIcon: String {
        if isTesting { return "wifi" }
        if testResult.isEmpty { return "wifi.exclamationmark" }
        return testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        if isTesting { return .nexusPrimary }
        if testResult.isEmpty { return .secondary }
        return testSuccess ? .nexusSuccess : .nexusError
    }

    private var statusTitle: String {
        if isTesting { return "Testing..." }
        if testResult.isEmpty { return "Ready to Test" }
        return testSuccess ? "Connected" : "Connection Failed"
    }

    private func testConnection() {
        isTesting = true
        testResult = ""
        responseTime = nil

        let startTime = Date()

        Task {
            do {
                let response = try await NexusAPI.shared.fetchFinanceSummary()
                let elapsed = Date().timeIntervalSince(startTime) * 1000

                await MainActor.run {
                    isTesting = false
                    testSuccess = response.success
                    responseTime = elapsed

                    if response.success {
                        testResult = "Successfully connected to your Nexus backend. All systems operational."
                    } else {
                        testResult = response.message ?? "Connection established but received an error response."
                    }

                    let haptics = UINotificationFeedbackGenerator()
                    haptics.notificationOccurred(response.success ? .success : .error)
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testSuccess = false
                    testResult = "Could not reach the server. Check your URL and network connection."

                    let haptics = UINotificationFeedbackGenerator()
                    haptics.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Placeholder Views

struct WidgetSettingsView: View {
    var body: some View {
        VStack(spacing: 24) {
            NexusEmptyState(
                icon: "square.grid.2x2",
                title: "Widget Settings",
                message: "Configure which data appears on your home screen widgets."
            )
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SiriShortcutsView: View {
    var body: some View {
        List {
            Section {
                Text("Use these Siri phrases to log data without opening the app.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section {
                ShortcutRow(
                    icon: "drop.fill",
                    iconColor: .nexusWater,
                    title: "Log Water",
                    phrase: "\"Hey Siri, log 500 ml water in Nexus\""
                )

                ShortcutRow(
                    icon: "face.smiling",
                    iconColor: .nexusMood,
                    title: "Log Mood",
                    phrase: "\"Hey Siri, log mood 7 in Nexus\""
                )

                ShortcutRow(
                    icon: "scalemass",
                    iconColor: .nexusHealth,
                    title: "Log Weight",
                    phrase: "\"Hey Siri, log weight 75 kilos in Nexus\""
                )
            } header: {
                Text("Logging")
            }

            Section {
                ShortcutRow(
                    icon: "timer",
                    iconColor: .nexusWarning,
                    title: "Start Fast",
                    phrase: "\"Hey Siri, start my fast in Nexus\""
                )

                ShortcutRow(
                    icon: "fork.knife",
                    iconColor: .nexusFood,
                    title: "Break Fast",
                    phrase: "\"Hey Siri, break my fast in Nexus\""
                )
            } header: {
                Text("Fasting")
            }

            Section {
                Text("Shortcuts are automatically available after installing the app. Say the phrases above to Siri to use them.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Siri Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ShortcutRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let phrase: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(phrase)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
