import SwiftUI
import Combine

// MARK: - Trends View

struct HealthTrendsView: View {
    @ObservedObject var viewModel: HealthViewModel
    @State private var selectedPeriod: String = "7d"

    // Available periods from backend
    private var availablePeriods: [String] {
        viewModel.trends.map { $0.period }.sorted { periodDays($0) < periodDays($1) }
    }

    // Get trend data for selected period
    private var selectedTrend: TrendPeriod? {
        viewModel.trends.first { $0.period == selectedPeriod }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Freshness indicator
                if let freshness = viewModel.healthFreshness {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(freshness.isStale ? Color.nexusWarning : Color.nexusSuccess)
                            .frame(width: 6, height: 6)
                        Text(freshness.syncTimeLabel)
                            .font(.caption)
                            .foregroundColor(freshness.isStale ? .nexusWarning : .secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                } else if let lastUpdated = viewModel.lastUpdated,
                          Date().timeIntervalSince(lastUpdated) > 300 || viewModel.dataSource == .cache {
                    freshnessIndicator(lastUpdated: lastUpdated, source: viewModel.dataSource)
                }

                // Timeseries error banner
                if viewModel.timeseriesError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.nexusWarning)
                        Text("Trends temporarily unavailable — pull to retry")
                            .font(.caption)
                            .foregroundColor(.nexusWarning)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.nexusWarning.opacity(0.1))
                    .cornerRadius(8)
                }

                // Period Selector - only show if backend provides multiple periods
                if availablePeriods.count > 1 {
                    periodSelector
                }

                if viewModel.isLoading {
                    loadingView
                } else if let trend = selectedTrend {
                    // Sleep Trend
                    sleepTrendCard(trend)

                    // Recovery Trend
                    recoveryTrendCard(trend)

                    // Weight Trend (uses TodayFacts for latest + delta)
                    if let facts = viewModel.todayFacts {
                        weightTrendCard(facts, trend: trend)
                    }

                    // Activity Consistency (uses TodayFacts)
                    if let facts = viewModel.todayFacts {
                        activityConsistencyCard(facts)
                    }
                } else if viewModel.trends.isEmpty {
                    emptyState
                } else {
                    // Have trends but none match selected period
                    noDataForPeriod
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            SyncCoordinator.shared.syncAll(force: true)
            await viewModel.loadData()
        }
        .onAppear {
            // Default to first available period if current selection not available
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
                        .background(selectedPeriod == period ? Color.nexusHealth : Color.nexusCardBackground)
                        .foregroundColor(selectedPeriod == period ? .white : .primary)
                        .cornerRadius(20)
                }
                .accessibilityLabel("\(periodLabel(period)) period")
                .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
            }
            Spacer()
        }
    }

    // MARK: - Filtered Timeseries for Selected Period

    private var filteredTimeseries: [DailyHealthPoint] {
        let days = periodDays(selectedPeriod)
        return Array(viewModel.healthTimeseries.suffix(days))
    }

    // MARK: - Sleep Trend

    private func sleepTrendCard(_ trend: TrendPeriod) -> some View {
        TrendCard(title: "Sleep", icon: "moon.zzz.fill", color: .nexusMood) {
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

                    // Sparkline if timeseries data available
                    if viewModel.hasTimeseriesData {
                        let sleepData = filteredTimeseries.compactMap { point -> Double? in
                            guard let minutes = point.sleepMinutes else { return nil }
                            return Double(minutes) / 60.0  // Convert to hours
                        }
                        if sleepData.count >= 3 {
                            SparklineView(data: sleepData, color: .nexusMood, height: 40)
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
        TrendCard(title: "Recovery", icon: "heart.fill", color: .nexusSuccess) {
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

                    // Additional metrics if available
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

                    // Sparkline if timeseries data available
                    if viewModel.hasTimeseriesData {
                        let recoveryData = filteredTimeseries.compactMap { point -> Double? in
                            guard let recovery = point.recovery else { return nil }
                            return Double(recovery)
                        }
                        if recoveryData.count >= 3 {
                            SparklineView(data: recoveryData, color: .nexusSuccess, height: 40)
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
        TrendCard(title: "Weight", icon: "scalemass.fill", color: .nexusWeight) {
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

                    // Show 30-day delta if available
                    if let delta = facts.weight30dDelta {
                        HStack(spacing: 4) {
                            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                            Text("\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) kg over 30 days")
                                .font(.caption)
                        }
                        .foregroundColor(abs(delta) > 1 ? .nexusWarning : .secondary)
                    }

                    // Sparkline if timeseries data available
                    if viewModel.hasTimeseriesData {
                        let weightData = filteredTimeseries.compactMap { $0.weight }
                        if weightData.count >= 3 {
                            SparklineView(data: weightData, color: .nexusWeight, height: 40)
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
        TrendCard(title: "Activity Consistency", icon: "figure.walk", color: .nexusWarning) {
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

                    // Days indicator (real data)
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { day in
                            Circle()
                                .fill(day < daysWithData ? Color.nexusWarning : Color(.tertiarySystemFill))
                                .frame(width: 24, height: 24)
                        }
                    }

                    Text(daysWithData >= 5 ? "Good consistency!" : "Try to track more days")
                        .font(.caption)
                        .foregroundColor(daysWithData >= 5 ? .nexusSuccess : .nexusWarning)
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
                    .fill(Color.nexusCardBackground)
                    .frame(height: 140)
                    .shimmer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Not enough data for trends")
                .font(.headline)

            Text("Trends will appear after a few days of tracking")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
    }

    private var noDataForPeriod: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No data for \(periodLabel(selectedPeriod))")
                .font(.headline)

            Text("Try selecting a different time period")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 60)
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
                .fill(source == .cache ? Color.nexusWarning : Color.nexusSuccess)
                .frame(width: 6, height: 6)

            Text("Updated \(lastUpdated, style: .relative) ago")
                .font(.caption)
                .foregroundColor(.secondary)

            if source == .cache {
                Text("(Cached)")
                    .font(.caption)
                    .foregroundColor(.nexusWarning)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func recoveryColor(_ score: Int) -> Color {
        if score >= 67 { return .nexusSuccess }
        if score >= 34 { return .nexusWarning }
        return .nexusError
    }

    // Convert period string to days for sorting
    private func periodDays(_ period: String) -> Int {
        switch period.lowercased() {
        case "7d": return 7
        case "14d": return 14
        case "30d": return 30
        default:
            // Try to extract number
            let digits = period.filter { $0.isNumber }
            return Int(digits) ?? 0
        }
    }

    // Human-readable period label
    private func periodLabel(_ period: String) -> String {
        switch period.lowercased() {
        case "7d": return "7 days"
        case "14d": return "14 days"
        case "30d": return "30 days"
        default: return period
        }
    }
}

// MARK: - Trend Card

struct TrendCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }
}

// MARK: - Sparkline View

struct SparklineView: View {
    let data: [Double]
    let color: Color
    var height: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            if data.count >= 2 {
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = maxVal - minVal
                let effectiveRange = range > 0 ? range : 1

                Path { path in
                    let stepX = geo.size.width / CGFloat(data.count - 1)

                    for (index, value) in data.enumerated() {
                        let x = stepX * CGFloat(index)
                        let normalizedY = (value - minVal) / effectiveRange
                        let y = geo.size.height * (1 - normalizedY)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Add gradient fill
                Path { path in
                    let stepX = geo.size.width / CGFloat(data.count - 1)

                    path.move(to: CGPoint(x: 0, y: geo.size.height))

                    for (index, value) in data.enumerated() {
                        let x = stepX * CGFloat(index)
                        let normalizedY = (value - minVal) / effectiveRange
                        let y = geo.size.height * (1 - normalizedY)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [color.opacity(0.3), color.opacity(0.05)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(height: height)
    }
}
