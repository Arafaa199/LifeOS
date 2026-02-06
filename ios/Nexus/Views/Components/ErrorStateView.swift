import SwiftUI

/// Reusable error state view for major views when network fails
/// Shows: icon, message, and "Try Again" button
struct ErrorStateView: View {
    let title: String
    let message: String
    let onRetry: () -> Void

    init(
        title: String = "Something went wrong",
        message: String,
        onRetry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.nexusWarning.opacity(0.7))

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                onRetry()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.nexusPrimary)
                .cornerRadius(12)
            }

            Spacer().frame(height: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message). Tap Try Again to refresh.")
    }
}

#Preview("Error State") {
    ErrorStateView(
        message: "Unable to load your data. Check your connection and try again.",
        onRetry: {}
    )
}
