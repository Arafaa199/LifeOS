import SwiftUI

struct MoreView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var documentsVM = DocumentsViewModel()
    @StateObject private var receiptsVM = ReceiptsViewModel()
    @ObservedObject private var homeVM = HomeViewModel.shared

    var body: some View {
        NavigationView {
            List {
                Section("Life Data") {
                    NavigationLink(destination: DocumentsListView(viewModel: documentsVM)
                        .navigationTitle("Documents")) {
                        SettingsRow(
                            icon: "doc.text.fill",
                            iconColor: NexusTheme.Colors.accent,
                            title: "Documents",
                            subtitle: "Passports, visas, IDs"
                        )
                    }

                    NavigationLink(destination: ReceiptsListView(viewModel: receiptsVM)
                        .navigationTitle("Receipts")) {
                        SettingsRow(
                            icon: "receipt",
                            iconColor: NexusTheme.Colors.Semantic.amber,
                            title: "Receipts",
                            subtitle: "Grocery shopping + nutrition"
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

                    NavigationLink(destination: NotesView()) {
                        SettingsRow(
                            icon: "note.text",
                            iconColor: .purple,
                            title: "Notes",
                            subtitle: "Obsidian vault search"
                        )
                    }

                    NavigationLink(destination: RemindersView()) {
                        SettingsRow(
                            icon: "checklist",
                            iconColor: .orange,
                            title: "Reminders",
                            subtitle: "Tasks and to-dos"
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

                    NavigationLink(destination: BJJView()) {
                        SettingsRow(
                            icon: "figure.martial.arts",
                            iconColor: .blue,
                            title: "BJJ",
                            subtitle: "Training log & streaks"
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
                    NavigationLink(destination: PipelineHealthView()) {
                        SettingsRow(
                            icon: "waveform.path.ecg",
                            iconColor: NexusTheme.Colors.Semantic.green,
                            title: "Pipeline Health",
                            subtitle: "Data feeds, sync status"
                        )
                    }

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
            .background(NexusTheme.Colors.background)
            .navigationTitle("More")
        }
    }
}
