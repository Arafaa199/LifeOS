import SwiftUI

/// Toggles for enabling/disabling sync domains
struct DomainTogglesSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
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
            Toggle(isOn: $settings.musicLoggingEnabled) {
                Label("Music Logging", systemImage: "music.note")
            }
        } header: {
            Text("Domain Sync")
        } footer: {
            Text("Disable domains to skip them during sync. Dashboard always syncs.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
