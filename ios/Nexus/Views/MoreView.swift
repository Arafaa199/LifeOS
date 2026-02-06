import SwiftUI

struct MoreView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var documentsVM = DocumentsViewModel()

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
