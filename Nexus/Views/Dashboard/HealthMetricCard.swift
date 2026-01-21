import SwiftUI

struct HealthMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(isLoading ? .secondary : color)
                    .symbolEffect(.pulse, isActive: isLoading && value == "--")
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .opacity(isLoading ? 0.6 : 1.0)
                    .redacted(reason: isLoading && value == "--" ? .placeholder : [])
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(isLoading ? 0.6 : 1.0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((isLoading && value == "--" ? Color.gray : color).opacity(0.1))
        .cornerRadius(10)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack(spacing: 12) {
            HealthMetricCard(title: "Recovery", value: "72", unit: "%", icon: "heart.circle.fill", color: .green)
            HealthMetricCard(title: "HRV", value: "45", unit: "ms", icon: "waveform.path.ecg", color: .purple)
        }
        HStack(spacing: 12) {
            HealthMetricCard(title: "Loading", value: "--", unit: "%", icon: "heart.fill", color: .gray, isLoading: true)
            HealthMetricCard(title: "Weight", value: "108.2", unit: "kg", icon: "scalemass.fill", color: .nexusWeight)
        }
    }
    .padding()
}
