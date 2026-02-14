import SwiftUI

/// Placeholder for widget configuration
struct WidgetSettingsView: View {
    var body: some View {
        VStack(spacing: 24) {
            ThemeEmptyState(
                icon: "square.grid.2x2",
                headline: "Widget Settings",
                description: "Configure which data appears on your home screen widgets."
            )
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}
