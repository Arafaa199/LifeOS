import SwiftUI

struct WorkCardView: View {
    let work: WorkSummary?

    var body: some View {
        if let work = work, work.hasData {
            HStack(spacing: NexusTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(NexusTheme.Colors.Semantic.blue.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(NexusTheme.Colors.Semantic.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: NexusTheme.Spacing.xs) {
                        Text(primaryText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.textPrimary)

                        if work.isAtWork {
                            Circle()
                                .fill(NexusTheme.Colors.Semantic.green)
                                .frame(width: 6, height: 6)
                        }
                    }

                    if let subtitle = subtitleText {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(NexusTheme.Spacing.lg)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        }
    }

    private var primaryText: String {
        guard let work = work else { return "" }
        if work.isAtWork {
            return "At work \u{2014} \(work.formattedHours)"
        }
        return "\(work.formattedHours) at work"
    }

    private var subtitleText: String? {
        guard let work = work else { return nil }
        if let arrival = work.arrivalTime {
            return "Arrived \(arrival)"
        }
        return nil
    }
}

#Preview {
    VStack {
        WorkCardView(work: WorkSummary(
            workDate: "2026-02-09",
            totalMinutes: 510,
            totalHours: 8.5,
            sessions: 1,
            firstArrival: "2026-02-09T04:30:00Z",
            lastDeparture: "2026-02-09T13:00:00Z",
            isAtWork: false,
            currentSessionStart: nil
        ))
        WorkCardView(work: WorkSummary(
            workDate: "2026-02-09",
            totalMinutes: 270,
            totalHours: 4.5,
            sessions: 1,
            firstArrival: "2026-02-09T04:30:00Z",
            lastDeparture: nil,
            isAtWork: true,
            currentSessionStart: "2026-02-09T04:30:00Z"
        ))
        WorkCardView(work: nil)
    }
    .padding()
    .background(NexusTheme.Colors.background)
}
