import SwiftUI

// MARK: - Health View Redesign
// Single dashboard with hierarchy: Today → Trends → Insights
// Max 8 cards, premium calm design

struct HealthViewRedesign: View {
    @StateObject private var viewModel = HealthViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Freshness Badge
                    FreshnessBadge(
                        lastUpdated: viewModel.lastUpdated,
                        isOffline: viewModel.dataSource == .cache
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    if viewModel.isLoading && viewModel.dashboardPayload == nil {
                        loadingState
                    } else if viewModel.dashboardPayload == nil {
                        emptyState
                    } else {
                        // 1. Recovery (Hero Card)
                        recoveryCard

                        // 2. Sleep
                        sleepCard

                        // 3. Body (Weight)
                        bodyCard

                        // 4. Activity
                        activityCard

                        // 5. 7-Day Trend
                        if !recovery7d.isEmpty {
                            trendCard
                        }

                        // 6. Insight
                        if let insight = viewModel.generateInsights().first {
                            insightCard(insight)
                        }
                    }

                    // Error banner
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }
                }
                .padding(16)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .refreshable {
                await viewModel.loadData()
            }
            .task {
                await viewModel.loadData()
            }
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: HealthSourcesView(viewModel: viewModel)) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.nexusHealth)
                    }
                }
            }
        }
    }

    // MARK: - Data Accessors (from HealthViewModel's dashboardPayload)

    private var facts: TodayFacts? {
        viewModel.todayFacts
    }

    private var recoveryScore: Int? {
        facts?.recoveryScore
    }

    private var isRecoveryUnusual: Bool {
        facts?.recoveryUnusual ?? false
    }

    private var hrv: Double? {
        facts?.hrv
    }

    private var hrvVs7d: Double? {
        facts?.hrvVs7d
    }

    private var rhr: Int? {
        facts?.rhr
    }

    private var strain: Double? {
        facts?.strain
    }

    private var steps: Int? {
        facts?.steps
    }

    private var sleepMinutes: Int? {
        facts?.sleepMinutes
    }

    private var sleepEfficiency: Double? {
        facts?.sleepEfficiency
    }

    private var deepSleepMinutes: Int? {
        facts?.deepSleepMinutes
    }

    private var remSleepMinutes: Int? {
        facts?.remSleepMinutes
    }

    private var lightSleepMinutes: Int? {
        guard let total = sleepMinutes, let deep = deepSleepMinutes, let rem = remSleepMinutes else {
            return nil
        }
        return max(0, total - deep - rem)
    }

    private var sleepVs7d: Double? {
        facts?.sleepVs7d
    }

    private var weightKg: Double? {
        facts?.weightKg
    }

    private var weightVs7d: Double? {
        facts?.weightVs7d
    }

    private var weight30dDelta: Double? {
        facts?.weight30dDelta
    }

    private var recovery7d: [Double] {
        // Use timeseries data if available, otherwise empty
        viewModel.healthTimeseries.compactMap { $0.recovery.map { Double($0) } }
    }

    private var avg7dRecovery: Double? {
        facts?.recovery7dAvg
    }

    // MARK: - 1. Recovery Card (Hero)

    private var recoveryCard: some View {
        HeroCard(accentColor: recoveryColor) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Recovery")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    if isRecoveryUnusual {
                        HStack(spacing: 4) {
                            Image(systemName: recoveryScore ?? 0 < 40 ? "exclamationmark.triangle.fill" : "sparkles")
                                .font(.caption)
                            Text(recoveryScore ?? 0 < 40 ? "Low" : "High")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(recoveryScore ?? 0 < 40 ? .orange : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((recoveryScore ?? 0 < 40 ? Color.orange : Color.green).opacity(0.12))
                        .cornerRadius(8)
                    }

                    SourceBadgeSmall(source: .whoop)
                }

                HStack(spacing: 24) {
                    if let recovery = recoveryScore {
                        ZStack {
                            ProgressRing(
                                progress: Double(recovery) / 100,
                                color: recoveryColor,
                                lineWidth: 8,
                                size: 80
                            )

                            VStack(spacing: 0) {
                                Text("\(recovery)")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(recoveryColor)
                                Text("%")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        recoveryPlaceholder
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if let hrv = hrv {
                            MetricLine(
                                icon: "waveform.path.ecg",
                                label: "HRV",
                                value: "\(Int(hrv)) ms",
                                delta: hrvVs7d
                            )
                        }

                        if let rhr = rhr {
                            MetricLine(
                                icon: "heart.fill",
                                label: "RHR",
                                value: "\(rhr) bpm",
                                delta: nil
                            )
                        }

                        if let strain = strain {
                            MetricLine(
                                icon: "flame.fill",
                                label: "Strain",
                                value: String(format: "%.1f", strain),
                                delta: nil
                            )
                        }
                    }

                    Spacer()
                }
            }
        }
    }

    private var recoveryPlaceholder: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                .frame(width: 80, height: 80)

            Text("--")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    private var recoveryColor: Color {
        guard let score = recoveryScore else { return .gray }
        if score >= 67 { return .green }
        if score >= 34 { return .yellow }
        return .red
    }

    // MARK: - 2. Sleep Card

    private var sleepCard: some View {
        SimpleCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sleep")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    SourceBadgeSmall(source: .whoop)
                }

                if let sleepMinutes = sleepMinutes {
                    let hours = sleepMinutes / 60
                    let mins = sleepMinutes % 60

                    HStack(alignment: .firstTextBaseline) {
                        Text("\(hours)h \(mins)m")
                            .font(.title2.weight(.bold))

                        if let efficiency = sleepEfficiency {
                            Text("• \(Int(efficiency))% efficiency")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if let delta = sleepVs7d {
                            DeltaBadge(delta, suffix: "%")
                        }
                    }

                    if let deep = deepSleepMinutes,
                       let rem = remSleepMinutes,
                       let light = lightSleepMinutes {
                        SleepStagesBarCompact(
                            deep: deep,
                            rem: rem,
                            light: light,
                            total: sleepMinutes
                        )
                    }
                } else {
                    noDataRow("Sleep data not available")
                }
            }
        }
    }

    // MARK: - 3. Body Card

    private var bodyCard: some View {
        SimpleCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Body")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    SourceBadgeSmall(source: .healthkit)
                }

                if let weight = weightKg {
                    HStack {
                        Text(String(format: "%.1f kg", weight))
                            .font(.title2.weight(.bold))

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            if let delta7d = weightVs7d {
                                HStack(spacing: 4) {
                                    Image(systemName: delta7d >= 0 ? "arrow.up" : "arrow.down")
                                        .font(.caption2)
                                    Text(String(format: "%.1f kg", abs(delta7d)))
                                        .font(.caption)
                                }
                                .foregroundColor(abs(delta7d) > 1 ? .orange : .secondary)
                            }

                            if let delta30d = weight30dDelta {
                                Text("\(delta30d >= 0 ? "+" : "")\(String(format: "%.1f", delta30d)) kg / 30d")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    noDataRow("Weight not logged")
                }
            }
        }
    }

    // MARK: - 4. Activity Card

    private var activityCard: some View {
        SimpleCard(padding: 12) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Steps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let steps = steps {
                        Text(formatNumber(steps))
                            .font(.title3.weight(.bold))
                    } else {
                        Text("--")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()
                    .frame(height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("Strain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let strain = strain {
                        Text(String(format: "%.1f", strain))
                            .font(.title3.weight(.bold))
                    } else {
                        Text("--")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    SourceBadgeSmall(source: .healthkit)
                    SourceBadgeSmall(source: .whoop)
                }
            }
        }
    }

    // MARK: - 5. Trend Card

    private var trendCard: some View {
        SimpleCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("7-Day Recovery")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    if let avg = avg7dRecovery {
                        Text("Avg: \(Int(avg))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                MiniSparkline(
                    data: recovery7d,
                    color: .nexusHealth,
                    height: 40
                )
            }
        }
    }

    // MARK: - 6. Insight Card

    private func insightCard(_ insight: HealthInsight) -> some View {
        SimpleCard(padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: insight.icon)
                    .font(.title3)
                    .foregroundColor(insight.color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(insight.title)
                            .font(.subheadline.weight(.medium))

                        Text(insight.confidence.rawValue)
                            .font(.caption2)
                            .foregroundColor(insight.confidence.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(insight.confidence.color.opacity(0.12))
                            .cornerRadius(4)
                    }

                    Text(insight.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(height: 100)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No health data")
                .font(.headline)

            Text("Connect WHOOP or Apple Health to see your metrics")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
    }

    private func noDataRow(_ message: String) -> some View {
        HStack {
            Image(systemName: "questionmark.circle")
                .foregroundColor(.secondary.opacity(0.5))
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Supporting Components

private struct MetricLine: View {
    let icon: String
    let label: String
    let value: String
    let delta: Double?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.subheadline.weight(.medium))

            if let delta = delta, delta != 0 {
                HStack(spacing: 2) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                    Text("\(Int(abs(delta)))%")
                        .font(.caption2)
                }
                .foregroundColor(delta >= 0 ? .green : .orange)
            }
        }
    }
}

private struct SleepStagesBarCompact: View {
    let deep: Int
    let rem: Int
    let light: Int
    let total: Int

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.indigo)
                        .frame(width: geo.size.width * CGFloat(deep) / CGFloat(total))

                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(rem) / CGFloat(total))

                    Rectangle()
                        .fill(Color.cyan.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(light) / CGFloat(total))
                }
                .cornerRadius(3)
            }
            .frame(height: 6)

            HStack(spacing: 12) {
                StageLegend(color: .indigo, label: "Deep", minutes: deep)
                StageLegend(color: .blue, label: "REM", minutes: rem)
                StageLegend(color: .cyan.opacity(0.5), label: "Light", minutes: light)
                Spacer()
            }
        }
    }
}

private struct StageLegend: View {
    let color: Color
    let label: String
    let minutes: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text("\(label) \(minutes / 60)h\(minutes % 60)m")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Normal Recovery") {
    HealthViewRedesign()
}
