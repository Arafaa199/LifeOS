import SwiftUI
import Combine

struct HealthTrendsContent: View {
    @ObservedObject var viewModel: HealthViewModel
    @Binding var selectedPeriod: String
    var showFreshness: Bool = true

    private var availablePeriods: [String] {
        viewModel.trends.map { $0.period }.sorted { periodDays($0) < periodDays($1) }
    }

    private var selectedTrend: TrendPeriod? {
        viewModel.trends.first { $0.period == selectedPeriod }
    }

    var body: some View {
        VStack(spacing: 20) {
            if showFreshness {
                if let freshness = viewModel.healthFreshness {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(freshness.isStale ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.Semantic.green)
                            .frame(width: 6, height: 6)
                        Text(freshness.syncTimeLabel)
                            .font(.caption)
                            .foregroundColor(freshness.isStale ? NexusTheme.Colors.Semantic.amber : .secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                } else if let lastUpdated = viewModel.lastUpdated,
                          Date().timeIntervalSince(lastUpdated) > 300 || viewModel.dataSource == .cache {
                    freshnessIndicator(lastUpdated: lastUpdated, source: viewModel.dataSource)
                }
            }

            if viewModel.timeseriesError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.Semantic.amber)
                    Text("Trends temporarily unavailable — pull to retry")
                        .font(.caption)
                        .foregroundColor(NexusTheme.Colors.Semantic.amber)
                    Spacer()
                }
                .padding(10)
                .background(NexusTheme.Colors.Semantic.amber.opacity(0.1))
                .cornerRadius(8)
            }

            if availablePeriods.count > 1 {
                periodSelector
            }

            if viewModel.isLoading {
                loadingView
            } else if let trend = selectedTrend {
                sleepTrendCard(trend)
                recoveryTrendCard(trend)

                if let facts = viewModel.todayFacts {
                    weightTrendCard(facts, trend: trend)
                }

                if let facts = viewModel.todayFacts {
                    activityConsistencyCard(facts)
                }
            } else if viewModel.trends.isEmpty {
                emptyState
            } else {
                noDataForPeriod
            }
        }
        .padding()
        .onAppear {
            if !availablePeriods.contains(selectedPeriod), let first = availablePeriods.first {
                selectedPeriod = first
            }
        }
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        HStack(spacing: 8) {
            ForEach(availablePeriods, id: \.self) { period in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPeriod = period
                    }
                }) {
                    Text(periodLabel(period))
                        .font(.subheadline)
                        .fontWeight(selectedPeriod == period ? .semibold : .regular)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedPeriod == period ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.card)
                        .foregroundColor(selectedPeriod == period ? .white : .primary)
                        .cornerRadius(20)
                }
                .accessibilityLabel("\(periodLabel(period)) period")
                .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
            }
            Spacer()
        }
    }

    // MARK: - Filtered Timeseries

    private var filteredTimeseries: [DailyHealthPoint] {
        let days = periodDays(selectedPeriod)
        return Array(viewModel.healthTimeseries.suffix(days))
    }

    // MARK: - Sleep Trend

    private func sleepTrendCard(_ trend: TrendPeriod) -> some View {
        TrendCard(title: "Sleep", icon: "moon.zzz.fill", color: NexusTheme.Colors.accent) {
            if let avgSleep = trend.avgSleepMinutes {
                let hours = Int(avgSleep) / 60
                let mins = Int(avgSleep) % 60

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(hours)h \(mins)m")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("avg over \(periodLabel(trend.period))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }

                    if viewModel.hasTimeseriesData {
                        let sleepData = filteredTimeseries.compactMap { point -> Double? in
                            guard let minutes = point.sleepMinutes else { return nil }
                            return Double(minutes) / 60.0
                        }
                        if sleepData.count >= 3 {
                            SparklineView(data: sleepData, color: NexusTheme.Colors.accent, height: 40)
                        } else {
                            noHistoricalDataNote
                        }
                    } else {
                        noHistoricalDataNote
                    }
                }
            } else {
                notAvailable
            }
        }
    }

    // MARK: - Recovery Trend

    private func recoveryTrendCard(_ trend: TrendPeriod) -> some View {
        TrendCard(title: "Recovery", icon: "heart.fill", color: NexusTheme.Colors.Semantic.green) {
            if let avgRecovery = trend.avgRecovery {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(Int(avgRecovery))%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(recoveryColor(Int(avgRecovery)))

                        Text("avg over \(periodLabel(trend.period))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }

                    if let avgHrv = trend.avgHrv {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("HRV avg: \(Int(avgHrv)) ms")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if viewModel.hasTimeseriesData {
                        let recoveryData = filteredTimeseries.compactMap { point -> Double? in
                            guard let recovery = point.recovery else { return nil }
                            return Double(recovery)
                        }
                        if recoveryData.count >= 3 {
                            SparklineView(data: recoveryData, color: NexusTheme.Colors.Semantic.green, height: 40)
                        } else {
                            noHistoricalDataNote
                        }
                    } else {
                        noHistoricalDataNote
                    }
                }
            } else {
                notAvailable
            }
        }
    }

    // MARK: - Weight Trend

    private func weightTrendCard(_ facts: TodayFacts, trend: TrendPeriod) -> some View {
        TrendCard(title: "Weight", icon: "scalemass.fill", color: NexusTheme.Colors.Semantic.purple) {
            if let weight = facts.weightKg {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 8) {
                        Text(String(format: "%.1f kg", weight))
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("latest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }

                    if let delta = facts.weight30dDelta {
                        HStack(spacing: 4) {
                            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                            Text("\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) kg over 30 days")
                                .font(.caption)
                        }
                        .foregroundColor(abs(delta) > 1 ? NexusTheme.Colors.Semantic.amber : .secondary)
                    }

                    if viewModel.hasTimeseriesData {
                        let weightData = filteredTimeseries.compactMap { $0.weight }
                        if weightData.count >= 3 {
                            SparklineView(data: weightData, color: NexusTheme.Colors.Semantic.purple, height: 40)
                        } else {
                            noHistoricalDataNote
                        }
                    } else {
                        noHistoricalDataNote
                    }
                }
            } else {
                notAvailable
            }
        }
    }

    // MARK: - Activity Consistency

    private func activityConsistencyCard(_ facts: TodayFacts) -> some View {
        TrendCard(title: "Activity Consistency", icon: "figure.walk", color: NexusTheme.Colors.Semantic.amber) {
            if let daysWithData = facts.daysWithData7d {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(daysWithData)/7")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("days tracked")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }

                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { day in
                            Circle()
                                .fill(day < daysWithData ? NexusTheme.Colors.Semantic.amber : Color(.tertiarySystemFill))
                                .frame(width: 24, height: 24)
                        }
                    }

                    Text(daysWithData >= 5 ? "Good consistency!" : "Try to track more days")
                        .font(.caption)
                        .foregroundColor(daysWithData >= 5 ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.Semantic.amber)
                }
            } else {
                notAvailable
            }
        }
    }

    // MARK: - Helper Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(NexusTheme.Colors.card)
                    .frame(height: 140)
                    .shimmer()
            }
        }
    }

    private var emptyState: some View {
        ThemeEmptyState(
            icon: "chart.line.uptrend.xyaxis",
            headline: "Not Enough Data for Trends",
            description: "Trends will appear after a few days of tracking."
        )
    }

    private var noDataForPeriod: some View {
        ThemeEmptyState(
            icon: "calendar.badge.exclamationmark",
            headline: "No Data for \(periodLabel(selectedPeriod))",
            description: "Try selecting a different time period."
        )
    }

    private var notAvailable: some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.secondary)
            Text("Collecting data...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var noHistoricalDataNote: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.caption2)
            Text("Daily chart requires more historical data")
                .font(.caption2)
        }
        .foregroundColor(.secondary)
        .padding(.top, 4)
    }

    private func freshnessIndicator(lastUpdated: Date, source: HealthViewModel.DataSourceInfo) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(source == .cache ? NexusTheme.Colors.Semantic.amber : NexusTheme.Colors.Semantic.green)
                .frame(width: 6, height: 6)

            Text("Updated \(lastUpdated, style: .relative) ago")
                .font(.caption)
                .foregroundColor(.secondary)

            if source == .cache {
                Text("(Cached)")
                    .font(.caption)
                    .foregroundColor(NexusTheme.Colors.Semantic.amber)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func recoveryColor(_ score: Int) -> Color {
        if score >= 67 { return NexusTheme.Colors.Semantic.green }
        if score >= 34 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.red
    }

    private func periodDays(_ period: String) -> Int {
        switch period.lowercased() {
        case "7d": return 7
        case "14d": return 14
        case "30d": return 30
        default:
            let digits = period.filter { $0.isNumber }
            return Int(digits) ?? 0
        }
    }

    private func periodLabel(_ period: String) -> String {
        switch period.lowercased() {
        case "7d": return "7 days"
        case "14d": return "14 days"
        case "30d": return "30 days"
        default: return period
        }
    }
}
