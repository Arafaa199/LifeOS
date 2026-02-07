import SwiftUI

/// Compact medications card for dashboard - shows adherence status
struct MedicationsCardView: View {
    let medications: MedicationsSummary?

    var body: some View {
        if let meds = medications, meds.dueToday > 0 {
            NavigationLink(destination: MedicationsView()) {
                HStack(spacing: NexusTheme.Spacing.md) {
                    // Icon with adherence indicator
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "pills.fill")
                            .font(.system(size: 18))
                            .foregroundColor(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: NexusTheme.Spacing.xxxs) {
                            Text(statusText)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(NexusTheme.Colors.textPrimary)

                            if meds.takenToday < meds.dueToday && meds.skippedToday == 0 {
                                Text("pending")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, NexusTheme.Spacing.xxs)
                                    .padding(.vertical, 2)
                                    .background(NexusTheme.Colors.Semantic.amber)
                                    .cornerRadius(NexusTheme.Radius.xs)
                            }
                        }

                        Text(detailText)
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                    }

                    Spacer()

                    // Adherence percentage
                    if let pct = medications?.adherencePct {
                        Text("\(Int(pct))%")
                            .font(.system(size: 22, weight: .semibold).monospacedDigit())
                            .foregroundColor(statusColor)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(NexusTheme.Colors.textMuted)
                }
                .padding(NexusTheme.Spacing.lg)
                .background(NexusTheme.Colors.card)
                .cornerRadius(NexusTheme.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                        .stroke(NexusTheme.Colors.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var statusColor: Color {
        guard let meds = medications else { return NexusTheme.Colors.textTertiary }
        if meds.takenToday == meds.dueToday {
            return NexusTheme.Colors.Semantic.green
        } else if meds.takenToday > 0 {
            return NexusTheme.Colors.Semantic.amber
        } else {
            return NexusTheme.Colors.Semantic.blue
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
    .background(NexusTheme.Colors.background)
}
