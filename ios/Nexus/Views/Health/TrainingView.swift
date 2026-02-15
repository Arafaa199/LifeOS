import SwiftUI

struct TrainingView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Training", selection: $selectedTab) {
                Text("Workouts").tag(0)
                Text("BJJ").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, NexusTheme.Spacing.lg)
            .padding(.vertical, NexusTheme.Spacing.sm)

            if selectedTab == 0 {
                WorkoutsView()
            } else {
                BJJView()
            }
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
    }
}
