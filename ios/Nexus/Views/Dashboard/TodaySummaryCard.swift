import SwiftUI

struct TodaySummaryCard: View {
    let todayFacts: TodayFacts?
    let isLoading: Bool
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 20) {
                recoveryRing

                VStack(alignment: .leading, spacing: 12) {
                    sleepRow
                    strainRow
                }

                Spacer()
            }
            .padding()
            .background(Color.nexusCardBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(onTap == nil)
    }

    // MARK: - Recovery Ring

    private var recoveryRing: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                .frame(width: 80, height: 80)

            Circle()
                .trim(from: 0, to: recoveryProgress)
                .stroke(
                    recoveryColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: recoveryProgress)

            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let score = todayFacts?.recoveryScore {
                    Text("\(score)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(recoveryColor)
                    Text("%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "heart.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var recoveryProgress: CGFloat {
        guard let score = todayFacts?.recoveryScore else { return 0 }
        return CGFloat(score) / 100.0
    }

    private var recoveryColor: Color {
        guard let score = todayFacts?.recoveryScore else { return .gray }
        switch score {
        case 67...100: return .green
        case 34...66: return .yellow
        default: return .red
        }
    }

    // MARK: - Sleep Row

    private var sleepRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "bed.double.fill")
                .font(.subheadline)
                .foregroundColor(.indigo)
                .frame(width: 20)

            if isLoading {
                Text("--")
                    .font(.subheadline.weight(.medium))
                    .redacted(reason: .placeholder)
            } else if let minutes = todayFacts?.sleepMinutes, minutes > 0 {
                Text(formatSleepDuration(minutes))
                    .font(.subheadline.weight(.medium))
                Text("sleep")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No sleep data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatSleepDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    // MARK: - Strain Row

    private var strainRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.subheadline)
                .foregroundColor(strainColor)
                .frame(width: 20)

            if isLoading {
                Text("--")
                    .font(.subheadline.weight(.medium))
                    .redacted(reason: .placeholder)
            } else if let strain = todayFacts?.strain {
                Text(String(format: "%.1f", strain))
                    .font(.subheadline.weight(.medium))
                Text("strain")
                    .font(.caption)
                    .foregroundColor(.secondary)

                strainBadge(for: strain)
            } else {
                Text("No strain data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var strainColor: Color {
        guard let strain = todayFacts?.strain else { return .gray }
        switch strain {
        case 18...: return .red
        case 14..<18: return .orange
        case 10..<14: return .yellow
        default: return .green
        }
    }

    @ViewBuilder
    private func strainBadge(for strain: Double) -> some View {
        let (label, color) = strainLevel(strain)
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }

    private func strainLevel(_ strain: Double) -> (String, Color) {
        switch strain {
        case 18...: return ("All Out", .red)
        case 14..<18: return ("Strenuous", .orange)
        case 10..<14: return ("Moderate", .yellow)
        default: return ("Light", .green)
        }
    }
}

#Preview("With Data") {
    TodaySummaryCard(
        todayFacts: TodayFacts(
            day: "2026-01-22",
            recoveryScore: 72,
            hrv: 45,
            rhr: 58,
            sleepMinutes: 420,
            deepSleepMinutes: 90,
            remSleepMinutes: 105,
            sleepEfficiency: 0.92,
            strain: 14.5,
            steps: 8500,
            weightKg: 78.5,
            spendTotal: 125.50,
            spendGroceries: 45.00,
            spendRestaurants: 30.50,
            incomeTotal: nil,
            transactionCount: 3,
            mealsLogged: 2,
            waterMl: 2000,
            caloriesConsumed: 1850,
            dataCompleteness: 0.85,
            factsComputedAt: nil,
            recoveryVs7d: 5.0,
            recoveryVs30d: -2.0,
            hrvVs7d: 3.5,
            sleepVs7d: -15.0,
            strainVs7d: 2.0,
            spendVs7d: 25.0,
            weightVs7d: -0.5,
            recoveryUnusual: false,
            sleepUnusual: false,
            spendUnusual: false,
            recovery7dAvg: 68.0,
            recovery30dAvg: 70.0,
            hrv7dAvg: 42.0,
            sleepMinutes7dAvg: 435.0,
            weight30dDelta: -1.5,
            daysWithData7d: 7,
            daysWithData30d: 28,
            baselinesComputedAt: nil
        ),
        isLoading: false
    )
    .padding()
}

#Preview("Loading") {
    TodaySummaryCard(
        todayFacts: nil,
        isLoading: true
    )
    .padding()
}

#Preview("No Data") {
    TodaySummaryCard(
        todayFacts: TodayFacts(
            day: "2026-01-22",
            recoveryScore: nil,
            hrv: nil,
            rhr: nil,
            sleepMinutes: nil,
            deepSleepMinutes: nil,
            remSleepMinutes: nil,
            sleepEfficiency: nil,
            strain: nil,
            steps: nil,
            weightKg: nil,
            spendTotal: nil,
            spendGroceries: nil,
            spendRestaurants: nil,
            incomeTotal: nil,
            transactionCount: nil,
            mealsLogged: nil,
            waterMl: nil,
            caloriesConsumed: nil,
            dataCompleteness: nil,
            factsComputedAt: nil,
            recoveryVs7d: nil,
            recoveryVs30d: nil,
            hrvVs7d: nil,
            sleepVs7d: nil,
            strainVs7d: nil,
            spendVs7d: nil,
            weightVs7d: nil,
            recoveryUnusual: nil,
            sleepUnusual: nil,
            spendUnusual: nil,
            recovery7dAvg: nil,
            recovery30dAvg: nil,
            hrv7dAvg: nil,
            sleepMinutes7dAvg: nil,
            weight30dDelta: nil,
            daysWithData7d: nil,
            daysWithData30d: nil,
            baselinesComputedAt: nil
        ),
        isLoading: false
    )
    .padding()
}
