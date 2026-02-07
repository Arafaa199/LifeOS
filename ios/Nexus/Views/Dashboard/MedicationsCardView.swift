import SwiftUI

/// Compact medications card for dashboard - shows adherence status
struct MedicationsCardView: View {
    let medications: MedicationsSummary?

    var body: some View {
        if let meds = medications, meds.dueToday > 0 {
            NavigationLink(destination: MedicationsView()) {
                HStack(spacing: 12) {
                    // Icon with adherence indicator
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "pills.fill")
                            .font(.system(size: 18))
                            .foregroundColor(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(statusText)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)

                            if meds.takenToday < meds.dueToday && meds.skippedToday == 0 {
                                Text("pending")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.nexusWarning)
                                    .cornerRadius(4)
                            }
                        }

                        Text(detailText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Adherence percentage
                    if let pct = medications?.adherencePct {
                        Text("\(Int(pct))%")
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundColor(statusColor)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.nexusCardBackground)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusColor: Color {
        guard let meds = medications else { return .gray }
        if meds.takenToday == meds.dueToday {
            return .nexusSuccess
        } else if meds.takenToday > 0 {
            return .nexusWarning
        } else {
            return .cyan
        }
    }

    private var statusText: String {
        guard let meds = medications else { return "" }
        return "Medications: \(meds.takenToday)/\(meds.dueToday)"
    }

    private var detailText: String {
        guard let meds = medications else { return "" }
        if meds.takenToday == meds.dueToday {
            return "All taken"
        } else {
            let remaining = meds.dueToday - meds.takenToday - meds.skippedToday
            if remaining == 1 {
                return "\(remaining) remaining"
            }
            return "\(remaining) remaining"
        }
    }
}

#Preview {
    VStack {
        MedicationsCardView(medications: MedicationsSummary(
            dueToday: 3,
            takenToday: 2,
            skippedToday: 0,
            adherencePct: 67,
            medications: nil
        ))
        MedicationsCardView(medications: MedicationsSummary(
            dueToday: 3,
            takenToday: 3,
            skippedToday: 0,
            adherencePct: 100,
            medications: nil
        ))
    }
    .padding()
    .background(Color.nexusBackground)
}
