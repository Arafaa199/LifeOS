import SwiftUI

/// Placeholder for widget configuration
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
