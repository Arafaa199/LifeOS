import SwiftUI

struct MedicationsSupplementsView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Medications", selection: $selectedTab) {
                Text("Medications").tag(0)
                Text("Supplements").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, NexusTheme.Spacing.lg)
            .padding(.vertical, NexusTheme.Spacing.sm)

            if selectedTab == 0 {
                MedicationsView()
            } else {
                SupplementsView()
            }
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle("Medications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
