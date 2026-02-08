import SwiftUI

struct HealthTodayContent: View {
    @ObservedObject var viewModel: HealthViewModel
    var showFreshness: Bool = true

    // MARK: - Dynamic Type Scaling
    @ScaledMetric(relativeTo: .title) private var recoveryTextSize: CGFloat = 18
    @ScaledMetric(relativeTo: .title) private var sleepTextSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title) private var activityTextSize: CGFloat = 22
    @ScaledMetric(relativeTo: .title) private var bodyTextSize: CGFloat = 24

    var body: some View {
        VStack(spacing: 16) {
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

            if viewModel.isLoading {
                loadingView
            } else if let facts = viewModel.todayFacts {
                recoveryCard(facts)
                sleepCard(facts)
                activityCard(facts)
                bodyCard(facts)
                allMetricsLink(facts)
            } else {
                emptyState
            }
        }
        .padding()
    }

    // MARK: - Recovery Card

    private func recoveryCard(_ facts: TodayFacts) -> some View {
        HealthMetricCard(title: "Recovery") {
            if let recovery = facts.recoveryScore {
                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(recoveryColor(recovery).opacity(0.2), lineWidth: 8)
                            .frame(width: 70, height: 70)

                        Circle()
                            .trim(from: 0, to: CGFloat(recovery) / 100)
                            .stroke(
                                recoveryColor(recovery),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 70, height: 70)
                            .rotationEffect(.degrees(-90))

                        Text("\(recovery)%")
                            .font(.system(size: recoveryTextSize, weight: .bold, design: .rounded))
                            .foregroundColor(recoveryColor(recovery))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let hrv = facts.hrv {
                            MetricRow(icon: "waveform.path.ecg", label: "HRV", value: "\(Int(hrv)) ms", source: .whoop)
                        }
                        if let rhr = facts.rhr {
                            MetricRow(icon: "heart.fill", label: "RHR", value: "\(rhr) bpm", source: .whoop)
                        }
                        if let strain = facts.strain {
                            MetricRow(icon: "flame.fill", label: "Strain", value: String(format: "%.1f", strain), source: .whoop)
                        }
                    }

                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recovery score: \(recovery) percent. Status: \(recoveryStatus(recovery))")
            } else {
                dataStateView(
                    metric: "Recovery",
                    icon: "heart.text.square",
                    pendingMessage: "WHOOP hasn't synced recovery yet today",
                    staleMessage: "Last recovery data is outdated"
                )
            }
        }
    }

    // MARK: - Sleep Card

    private func sleepCard(_ facts: TodayFacts) -> some View {
        HealthMetricCard(title: "Sleep (Last Night)") {
            if let sleepMinutes = facts.sleepMinutes {
                let hours = sleepMinutes / 60
                let mins = sleepMinutes % 60

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(hours)h \(mins)m")
                                .font(.system(size: sleepTextSize, weight: .bold, design: .rounded))

                            if let efficiency = facts.sleepEfficiency {
                                Text("\(Int(efficiency))% efficiency")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        SourceBadgeSmall(source: .whoop)
                    }

                    if let deep = facts.deepSleepMinutes, let rem = facts.remSleepMinutes {
                        let light = facts.lightSleepMinutes ?? (sleepMinutes - deep - rem)
                        SleepStagesBar(deep: deep, rem: rem, light: max(0, light), total: sleepMinutes)
                    }

                    if let vs7d = facts.sleepVs7d {
                        ComparisonBadge(value: vs7d, label: "vs 7-day avg")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sleep: \(hours) hours \(mins) minutes\(facts.sleepEfficiency.map { ", \(Int($0)) percent efficiency" } ?? "")")
            } else {
                dataStateView(
                    metric: "Sleep",
                    icon: "moon.zzz",
                    pendingMessage: "Sleep data not processed yet",
                    staleMessage: "Last sleep data is outdated"
                )
            }
        }
    }

    // MARK: - Activity Card

    private func activityCard(_ facts: TodayFacts) -> some View {
        let steps = facts.steps ?? viewModel.localSteps

        return HealthMetricCard(title: "Activity") {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .foregroundColor(NexusTheme.Colors.Semantic.blue)
                        if let steps {
                            Text(formatNumber(steps))
                                .font(.system(size: activityTextSize, weight: .bold, design: .rounded))
                        } else {
                            Text("—")
                                .font(.system(size: activityTextSize, weight: .bold, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("No step data available")
                        }
                    }
                    HStack(spacing: 4) {
                        Text("Steps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SourceBadgeSmall(source: .healthkit)
                    }
                }

                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(steps.map { "Activity: \(formatNumber($0)) steps" } ?? "Activity: No step data available")
        }
    }

    // MARK: - Body Card

    private func bodyCard(_ facts: TodayFacts) -> some View {
        // Prefer API weight (today's facts). Only fall back to HealthKit if recorded in last 48h.
        let weight: Double? = facts.weightKg ?? {
            guard let lw = viewModel.localWeight,
                  let lwDate = viewModel.localWeightDate,
                  lwDate > Date().addingTimeInterval(-48 * 3600) else { return nil }
            return lw
        }()
        let vs7d = facts.weightVs7d

        return HealthMetricCard(title: "Body") {
            if let weight {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.1f kg", weight))
                                .font(.system(size: bodyTextSize, weight: .bold, design: .rounded))

                            if let vs7d {
                                Text(vs7d >= 0 ? "+\(String(format: "%.1f", vs7d)) kg vs 7d" : "\(String(format: "%.1f", vs7d)) kg vs 7d")
                                    .font(.caption)
                                    .foregroundColor(abs(vs7d) > 1 ? NexusTheme.Colors.Semantic.amber : .secondary)
                            }
                        }

                        Spacer()

                        SourceBadgeSmall(source: .healthkit)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Body: \(String(format: "%.1f", weight)) kilograms\(vs7d.map { delta in delta >= 0 ? ", plus \(String(format: "%.1f", delta)) kilograms vs 7-day average" : ", minus \(String(format: "%.1f", abs(delta))) kilograms vs 7-day average" } ?? "")")
            } else {
                dataStateView(
                    metric: "Weight",
                    icon: "scalemass",
                    pendingMessage: "No weight recorded today",
                    staleMessage: "Weight data is outdated"
                )
            }
        }
    }

    // MARK: - Helper Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<4) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(NexusTheme.Colors.card)
                    .frame(height: 100)
                    .shimmer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)

            Image(systemName: emptyStateIcon)
                .font(.system(size: 44, weight: .light))
                .foregroundColor(hasHealthSourceConnected ? NexusTheme.Colors.Semantic.green.opacity(0.5) : .secondary.opacity(0.4))

            VStack(spacing: 8) {
                Text(emptyStateTitle)
                    .font(.title3.weight(.semibold))

                Text(emptyStateMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if !hasHealthSourceConnected {
                NavigationLink(destination: HealthSourcesView(viewModel: viewModel)) {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                        Text("Connect Sources")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(NexusTheme.Colors.accent)
                    .cornerRadius(10)
                }
            }

            Spacer().frame(height: 20)
        }
        .accessibilityElement(children: .combine)
    }

    private var hasHealthSourceConnected: Bool {
        viewModel.healthFreshness != nil || viewModel.healthKitAuthorized
    }

    private var emptyStateIcon: String {
        hasHealthSourceConnected ? "heart.text.square" : "heart.slash"
    }

    private var emptyStateTitle: String {
        hasHealthSourceConnected ? "No data yet today" : "Health sources not connected"
    }

    private var emptyStateMessage: String {
        if hasHealthSourceConnected {
            return "Your health data will appear here once it syncs from your devices. Pull down to refresh."
        }
        return "Connect WHOOP or Apple Health in Settings to see recovery, sleep, and activity data."
    }

    private func dataStateView(metric: String, icon: String, pendingMessage: String, staleMessage: String) -> some View {
        let isStale = viewModel.healthFreshness?.isStale == true

        return HStack(spacing: 10) {
            Image(systemName: isStale ? "clock.badge.exclamationmark" : icon)
                .font(.title3)
                .foregroundColor(isStale ? NexusTheme.Colors.Semantic.amber : .secondary.opacity(0.6))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(isStale ? staleMessage : pendingMessage)
                    .font(.subheadline)
                    .foregroundColor(isStale ? NexusTheme.Colors.Semantic.amber : .secondary)

                if let freshness = viewModel.healthFreshness {
                    Text("Last update: \(freshness.syncTimeLabel)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Pull to refresh")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .accessibilityLabel("\(metric) data \(isStale ? "is stale" : "not yet available")")
    }

    private func recoveryColor(_ score: Int) -> Color {
        if score >= 67 { return NexusTheme.Colors.Semantic.green }
        if score >= 34 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.red
    }

    private func recoveryStatus(_ score: Int) -> String {
        if score >= 67 { return "excellent" }
        if score >= 34 { return "good" }
        return "fair"
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
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

    // MARK: - All Metrics Link

    private func allMetricsLink(_ facts: TodayFacts) -> some View {
        NavigationLink(destination: HealthMetricsDetailView(facts: facts)) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(NexusTheme.Colors.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("All Health Metrics")
                        .font(.subheadline.weight(.semibold))

                    Text("HRV, RHR, sleep stages, hydration & more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption.weight(.semibold))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NexusTheme.Colors.card)
            .cornerRadius(12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("All Health Metrics")
            .accessibilityHint("Opens detailed view with HRV, RHR, sleep stages, hydration, and more metrics")
        }
        .foregroundColor(.primary)
    }
}
