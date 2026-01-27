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

                // Developer Section
                Section {
                    NavigationLink(destination: DebugView()) {
                        SettingsRow(
                            icon: "ladybug",
                            iconColor: .orange,
                            title: "Debug Panel",
                            subtitle: "Test APIs and view logs"
                        )
                    }
                } header: {
                    Text("Developer")
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
                apiKey = UserDefaults.standard.string(forKey: "nexusAPIKey") ?? ""
            }
            .alert("Settings Saved", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your configuration has been updated.")
            }
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

            // Per-domain rows
            ForEach(SyncCoordinator.SyncDomain.allCases) { domain in
                syncDomainRow(domain)
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

            // WHOOP debug info
            if let debug = coordinator.whoopDebugInfo {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        whoopDebugRow("Raw lastSync", debug.rawLastSync ?? "nil")
                        whoopDebugRow("Parsed date", debug.parsedDate?.description ?? "nil")
                        whoopDebugRow("Checked at", debug.checkedAt.description)
                        whoopDebugRow("Age (hours)", debug.ageHours.map { String(format: "%.1f", $0) } ?? "nil")
                        whoopDebugRow("Server status", debug.serverStatus)
                        whoopDebugRow("Server hours", debug.serverHoursSinceSync.map { String(format: "%.1f", $0) } ?? "nil")
                    }
                    .font(.caption2.monospaced())
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ladybug")
                            .font(.caption)
                        Text("WHOOP Debug")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Sync Center")
        } footer: {
            Text("Shows sync status for all data domains. Tap Sync Now to refresh everything.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Domain Row

    private func syncDomainRow(_ domain: SyncCoordinator.SyncDomain) -> some View {
        let state = coordinator.domainStates[domain] ?? SyncCoordinator.DomainSyncState()

        return HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(domainStatusColor(state))
                .frame(width: 10, height: 10)

            // Icon
            Image(systemName: domain.icon)
                .font(.system(size: 14))
                .foregroundColor(domain.color)
                .frame(width: 20)

            // Name + detail
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(domain.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let subtitle = domain.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = state.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else if let detail = state.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Sync time or spinner
            if state.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
            } else if let lastSync = state.lastSyncDate {
                Text(formatSyncTime(lastSync))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Never")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func whoopDebugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
    }

    private func domainStatusColor(_ state: SyncCoordinator.DomainSyncState) -> Color {
        if state.isSyncing { return .orange }
        if state.lastError != nil { return .red }
        if let lastSync = state.lastSyncDate {
            let age = Date().timeIntervalSince(lastSync)
            if age < 300 { return .green }    // < 5 min
            if age < 3600 { return .orange }  // < 1 hour
            return .red
        }
        return .gray // never synced
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
            UserDefaults.standard.set(apiKey, forKey: "nexusAPIKey")
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
        VStack(spacing: 24) {
            NexusEmptyState(
                icon: "mic.fill",
                title: "Siri Shortcuts",
                message: "Set up voice commands for quick logging with Siri."
            )
        }
        .navigationTitle("Siri Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
