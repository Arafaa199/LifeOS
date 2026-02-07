import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var coordinator = SyncCoordinator.shared
    @ObservedObject private var offlineQueue = OfflineQueue.shared
    @State private var webhookURL: String = ""
    @State private var apiKey: String = ""
    @State private var showingSaveConfirmation = false
    var embedded: Bool = false

    private static let docsURL = URL(string: "https://github.com/Arafaa199/LifeOS")!
    private static let issuesURL = URL(string: "https://github.com/Arafaa199/LifeOS/issues")!

    @ViewBuilder
    var body: some View {
        if embedded {
            settingsList
        } else {
            NavigationView {
                settingsList
            }
        }
    }

    private var settingsList: some View {
        List {
            SyncStatusSection(coordinator: coordinator)
            DomainTogglesSection(settings: settings)
            SyncIssuesSection(offlineQueue: offlineQueue)

            connectionSection
            ConfigurationSection(
                webhookURL: $webhookURL,
                apiKey: $apiKey,
                onSave: saveSettings
            )
            dataSourcesSection
            extrasSection
            dataSection
            DebugSection(coordinator: coordinator)
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NexusTheme.Colors.background)
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

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section {
            NavigationLink(destination: TestConnectionView()) {
                SettingsRow(
                    icon: "wifi",
                    iconColor: NexusTheme.Colors.accent,
                    title: "Test Connection",
                    subtitle: "Verify your Nexus connection"
                )
            }
        } header: {
            Text("Connection")
        }
    }

    // MARK: - Data Sources Section

    private var dataSourcesSection: some View {
        Section {
            NavigationLink(destination: HealthSourcesView(viewModel: HealthViewModel())) {
                SettingsRow(
                    icon: "antenna.radiowaves.left.and.right",
                    iconColor: NexusTheme.Colors.Semantic.green,
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
    }

    // MARK: - Extras Section

    private var extrasSection: some View {
        Section {
            NavigationLink(destination: WidgetSettingsView()) {
                SettingsRow(
                    icon: "square.grid.2x2",
                    iconColor: NexusTheme.Colors.Semantic.green,
                    title: "Widgets",
                    subtitle: "Configure home screen widgets"
                )
            }

            NavigationLink(destination: SiriShortcutsView()) {
                SettingsRow(
                    icon: "mic.fill",
                    iconColor: NexusTheme.Colors.accent,
                    title: "Siri Shortcuts",
                    subtitle: "Voice commands for quick logging"
                )
            }
        } header: {
            Text("Extras")
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                clearLocalData()
            } label: {
                SettingsRow(
                    icon: "trash",
                    iconColor: NexusTheme.Colors.Semantic.red,
                    title: "Clear Local Data",
                    subtitle: "Remove cached data from this device"
                )
            }
        } header: {
            Text("Data")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            SettingsRow(
                icon: "info.circle",
                iconColor: .secondary,
                title: "Version",
                value: versionString
            )

            Link(destination: Self.docsURL) {
                SettingsRow(
                    icon: "book",
                    iconColor: NexusTheme.Colors.accent,
                    title: "Documentation",
                    subtitle: "View guides and API reference",
                    showChevron: true
                )
            }

            Link(destination: Self.issuesURL) {
                SettingsRow(
                    icon: "exclamationmark.bubble",
                    iconColor: NexusTheme.Colors.Semantic.amber,
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
                    .foregroundColor(NexusTheme.Colors.accent.opacity(0.5))

                Text("Nexus - Life Data Hub")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        }
    }

    // MARK: - Helpers

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

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
