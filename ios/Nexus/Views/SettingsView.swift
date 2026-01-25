import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var healthKitSync = HealthKitSyncService.shared
    @State private var webhookURL: String = ""
    @State private var apiKey: String = ""
    @State private var showingSaveConfirmation = false
    @State private var isRefreshing = false
    @State private var refreshMessage: String?

    var body: some View {
        NavigationView {
            List {
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

                // Integrations Section
                Section {
                    // HealthKit Sync Status
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                            Text("HealthKit Sync")
                                .fontWeight(.medium)
                            Spacer()
                            if healthKitSync.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }

                        if let lastSync = healthKitSync.lastSyncDate {
                            HStack {
                                Text("Last sync:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(lastSync, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("ago")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if healthKitSync.lastSyncSampleCount > 0 {
                                Text("\(healthKitSync.lastSyncSampleCount) samples synced")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Never synced")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button {
                            Task {
                                do {
                                    try await healthKitSync.syncAllData()
                                    let haptics = UINotificationFeedbackGenerator()
                                    haptics.notificationOccurred(.success)
                                } catch {
                                    let haptics = UINotificationFeedbackGenerator()
                                    haptics.notificationOccurred(.error)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Now")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.white)
                        .background(healthKitSync.isSyncing ? Color.gray : Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .disabled(healthKitSync.isSyncing)
                    }
                    .padding(.vertical, 4)

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
                    Text("Integrations")
                } footer: {
                    Text("HealthKit data syncs sleep, HRV, heart rate, steps, and active calories to your Nexus backend.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Data Section
                Section {
                    Button {
                        Task { await refreshServerData() }
                    } label: {
                        SettingsRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: .nexusPrimary,
                            title: "Refresh Server Data",
                            subtitle: "Regenerate summaries from database"
                        )
                    }

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
                        value: "1.0.0 (1)"
                    )

                    Link(destination: URL(string: "https://github.com/yourusername/nexus")!) {
                        SettingsRow(
                            icon: "book",
                            iconColor: .nexusPrimary,
                            title: "Documentation",
                            subtitle: "View guides and API reference",
                            showChevron: true
                        )
                    }

                    Link(destination: URL(string: "https://github.com/yourusername/nexus/issues")!) {
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
        // Clear cached data
        CacheManager.shared.clearAll()
        SharedStorage.shared.resetDailyStats()

        let haptics = UINotificationFeedbackGenerator()
        haptics.notificationOccurred(.success)
    }

    private func refreshServerData() async {
        isRefreshing = true
        refreshMessage = nil

        do {
            let response = try await NexusAPI.shared.refreshSummaries()
            await MainActor.run {
                isRefreshing = false
                refreshMessage = response.success ? "Data refreshed successfully" : (response.message ?? "Refresh failed")
                let haptics = UINotificationFeedbackGenerator()
                haptics.notificationOccurred(response.success ? .success : .error)
            }
        } catch {
            await MainActor.run {
                isRefreshing = false
                refreshMessage = "Failed to refresh: \(error.localizedDescription)"
                let haptics = UINotificationFeedbackGenerator()
                haptics.notificationOccurred(.error)
            }
        }
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

            // Status Icon
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
        .environmentObject(AppSettings())
}
