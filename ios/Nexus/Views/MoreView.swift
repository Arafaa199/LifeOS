import SwiftUI

struct MoreView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var documentsVM = DocumentsViewModel()
    @StateObject private var homeVM = HomeViewModel()

    var body: some View {
        NavigationView {
            List {
                Section("Life Data") {
                    NavigationLink(destination: DocumentsListView(viewModel: documentsVM)
                        .navigationTitle("Documents")) {
                        SettingsRow(
                            icon: "doc.text.fill",
                            iconColor: .nexusPrimary,
                            title: "Documents",
                            subtitle: "Passports, visas, IDs"
                        )
                    }

                    NavigationLink(destination: MusicView()) {
                        SettingsRow(
                            icon: "music.note",
                            iconColor: .pink,
                            title: "Music",
                            subtitle: "Listening activity"
                        )
                    }

                    NavigationLink(destination: MedicationsView()) {
                        SettingsRow(
                            icon: "pills.fill",
                            iconColor: .cyan,
                            title: "Medications",
                            subtitle: "HealthKit data"
                        )
                    }

                    NavigationLink(destination: SupplementsView()) {
                        SettingsRow(
                            icon: "leaf.fill",
                            iconColor: .green,
                            title: "Supplements",
                            subtitle: "Daily tracking"
                        )
                    }

                    NavigationLink(destination: WorkoutsView()) {
                        SettingsRow(
                            icon: "figure.run",
                            iconColor: .orange,
                            title: "Workouts",
                            subtitle: "Activity tracking"
                        )
                    }
                }

                Section("Wellness") {
                    NavigationLink(destination: WaterLogView()) {
                        SettingsRow(
                            icon: "drop.fill",
                            iconColor: .blue,
                            title: "Water",
                            subtitle: "Track hydration"
                        )
                    }

                    NavigationLink(destination: MoodLogView()) {
                        SettingsRow(
                            icon: "heart.fill",
                            iconColor: .red,
                            title: "Mood & Energy",
                            subtitle: "Log how you feel"
                        )
                    }
                }

                Section("Home") {
                    NavigationLink(destination: HomeControlView(viewModel: homeVM)) {
                        SettingsRow(
                            icon: "house.fill",
                            iconColor: .orange,
                            title: "Home Control",
                            subtitle: "Lights, vacuum, camera"
                        )
                    }
                }

                Section("App") {
                    NavigationLink(destination: SettingsView(embedded: true)) {
                        SettingsRow(
                            icon: "gearshape.fill",
                            iconColor: .secondary,
                            title: "Settings",
                            subtitle: "Connection, sync, data sources"
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.nexusBackground)
            .navigationTitle("More")
        }
    }
}
