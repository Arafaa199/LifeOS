import SwiftUI

/// Fasting timer card with start/break button
struct FastingCardView: View {
    let fasting: FastingStatus?
    let fastingElapsed: String
    let isLoading: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Timer icon
            Image(systemName: fasting?.isActive == true ? "timer" : "timer.circle")
                .font(.title2)
                .foregroundColor(fasting?.isActive == true ? .orange : .secondary)
                .symbolEffect(.pulse, isActive: fasting?.isActive == true)

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                if fasting?.isActive == true {
                    Text(fastingElapsed)
                        .font(.headline.monospacedDigit())
                        .foregroundColor(.primary)
                    Text("Fasting")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Not fasting")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action button
            Button {
                onToggle()
            } label: {
                Text(fasting?.isActive == true ? "Break" : "Start")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(fasting?.isActive == true ? Color.orange : Color.accentColor)
                    .cornerRadius(8)
            }
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 20) {
        FastingCardView(
            fasting: nil,
            fastingElapsed: "--:--",
            isLoading: false,
            onToggle: {}
        )

        FastingCardView(
            fasting: FastingStatus(isActive: true, sessionId: 1, startedAt: nil, elapsedHours: 14.5),
            fastingElapsed: "14:30",
            isLoading: false,
            onToggle: {}
        )
    }
    .padding()
}
