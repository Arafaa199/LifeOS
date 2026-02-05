import SwiftUI

// MARK: - Today View (Confidence Screen)

struct HealthTodayView: View {
    @ObservedObject var viewModel: HealthViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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

                if viewModel.isLoading {
                    loadingView
                } else if let facts = viewModel.todayFacts {
                    // Recovery / Readiness Card
                    recoveryCard(facts)

                    // Sleep Card
                    sleepCard(facts)

                    // Activity Card
                    activityCard(facts)

                    // Body Card
                    bodyCard(facts)

                } else {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            // Fetch fresh HealthKit data locally first
            await viewModel.fetchLocalHealthKit()
            // Then trigger full sync (push to server, then fetch dashboard)
            SyncCoordinator.shared.syncAll(force: true)
            await viewModel.loadData()
        }
    }

    // MARK: - Recovery Card

    private func recoveryCard(_ facts: TodayFacts) -> some View {
        HealthMetricCard(title: "Recovery") {
            if let recovery = facts.recoveryScore {
                HStack(spacing: 20) {
                    // Recovery Ring
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
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(recoveryColor(recovery))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        // HRV
                        if let hrv = facts.hrv {
                            MetricRow(icon: "waveform.path.ecg", label: "HRV", value: "\(Int(hrv)) ms", source: .whoop)
                        }

                        // RHR
                        if let rhr = facts.rhr {
                            MetricRow(icon: "heart.fill", label: "RHR", value: "\(rhr) bpm", source: .whoop)
                        }

                        // Strain
                        if let strain = facts.strain {
                            MetricRow(icon: "flame.fill", label: "Strain", value: String(format: "%.1f", strain), source: .whoop)
                        }
                    }

                    Spacer()
                }
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
                                .font(.system(size: 28, weight: .bold, design: .rounded))

                            if let efficiency = facts.sleepEfficiency {
                                Text("\(Int(efficiency))% efficiency")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        SourceBadgeSmall(source: .whoop)
                    }

                    // Sleep stages mini bar
                    if let deep = facts.deepSleepMinutes, let rem = facts.remSleepMinutes {
                        let light = facts.lightSleepMinutes ?? (sleepMinutes - deep - rem)
                        SleepStagesBar(deep: deep, rem: rem, light: max(0, light), total: sleepMinutes)
                    }

                    // Comparison
                    if let vs7d = facts.sleepVs7d {
                        ComparisonBadge(value: vs7d, label: "vs 7-day avg")
                    }
                }
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
                            .foregroundColor(.nexusWater)
                        if let steps {
                            Text(formatNumber(steps))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                        } else {
                            Text("--")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
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
        }
    }

    // MARK: - Body Card

    private func bodyCard(_ facts: TodayFacts) -> some View {
        let weight = facts.weightKg ?? viewModel.localWeight
        let vs7d = facts.weightVs7d

        return HealthMetricCard(title: "Body") {
            if let weight {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.1f kg", weight))
                                .font(.system(size: 24, weight: .bold, design: .rounded))

                            if let vs7d {
                                Text(vs7d >= 0 ? "+\(String(format: "%.1f", vs7d)) kg vs 7d" : "\(String(format: "%.1f", vs7d)) kg vs 7d")
                                    .font(.caption)
                                    .foregroundColor(abs(vs7d) > 1 ? .nexusWarning : .secondary)
                            }
                        }

                        Spacer()

                        SourceBadgeSmall(source: .healthkit)
                    }
                }
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
                    .fill(Color.nexusCardBackground)
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
                .foregroundColor(hasHealthSourceConnected ? .nexusHealth.opacity(0.5) : .secondary.opacity(0.4))

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
                    .background(Color.nexusPrimary)
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

    /// Shows different states: stale data (warning), or pending (neutral)
    private func dataStateView(metric: String, icon: String, pendingMessage: String, staleMessage: String) -> some View {
        let isStale = viewModel.healthFreshness?.isStale == true

        return HStack(spacing: 10) {
            Image(systemName: isStale ? "clock.badge.exclamationmark" : icon)
                .font(.title3)
                .foregroundColor(isStale ? .nexusWarning : .secondary.opacity(0.6))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(isStale ? staleMessage : pendingMessage)
                    .font(.subheadline)
                    .foregroundColor(isStale ? .nexusWarning : .secondary)

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
        if score >= 67 { return .nexusSuccess }
        if score >= 34 { return .nexusWarning }
        return .nexusError
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
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
}

// MARK: - Supporting Components

struct HealthMetricCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }
}

struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let source: DataSourceType

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
                .font(.subheadline)
                .fontWeight(.medium)

            SourceBadgeSmall(source: source)
        }
    }
}

enum DataSourceType {
    case whoop, healthkit

    var icon: String {
        switch self {
        case .whoop: return "w.circle.fill"
        case .healthkit: return "heart.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .whoop: return .nexusWarning
        case .healthkit: return .nexusProtein
        }
    }
}

struct SourceBadgeSmall: View {
    let source: DataSourceType

    var body: some View {
        Image(systemName: source.icon)
            .font(.system(size: 10))
            .foregroundColor(source.color)
    }
}

struct SleepStagesBar: View {
    let deep: Int
    let rem: Int
    let light: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color.nexusMood)
                    .frame(width: geo.size.width * CGFloat(deep) / CGFloat(total))

                Rectangle()
                    .fill(Color.nexusPrimary)
                    .frame(width: geo.size.width * CGFloat(rem) / CGFloat(total))

                Rectangle()
                    .fill(Color.cyan.opacity(0.5))
                    .frame(width: geo.size.width * CGFloat(light) / CGFloat(total))
            }
            .cornerRadius(3)
        }
        .frame(height: 6)

        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(Color.nexusMood).frame(width: 8, height: 8)
                Text("Deep").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.nexusPrimary).frame(width: 8, height: 8)
                Text("REM").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.cyan.opacity(0.5)).frame(width: 8, height: 8)
                Text("Light").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

struct ComparisonBadge: View {
    let value: Double
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2)
                .foregroundColor(value >= 0 ? .nexusSuccess : .nexusWarning)

            Text("\(value >= 0 ? "+" : "")\(Int(value))% \(label)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Shimmer Effect

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.3), .clear]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = UIScreen.main.bounds.width
                }
            }
    }
}
