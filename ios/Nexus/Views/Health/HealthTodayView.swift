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
                            .fill(freshness.isStale ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(freshness.syncTimeLabel)
                            .font(.caption)
                            .foregroundColor(freshness.isStale ? .orange : .secondary)
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
                notAvailableView("Recovery data not available yet")
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
                notAvailableView("Sleep data not available yet")
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
                            .foregroundColor(.blue)
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
                                    .foregroundColor(abs(vs7d) > 1 ? .orange : .secondary)
                            }
                        }

                        Spacer()

                        SourceBadgeSmall(source: .healthkit)
                    }
                }
            } else {
                notAvailableView("Weight not logged yet")
            }
        }
    }

    // MARK: - Helper Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<4) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 100)
                    .shimmer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No health data available")
                .font(.headline)

            Text("Connect WHOOP or Apple Health to see your metrics")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
    }

    private func notAvailableView(_ message: String) -> some View {
        HStack {
            Image(systemName: "questionmark.circle")
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func recoveryColor(_ score: Int) -> Color {
        if score >= 67 { return .green }
        if score >= 34 { return .yellow }
        return .red
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func freshnessIndicator(lastUpdated: Date, source: HealthViewModel.DataSourceInfo) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(source == .cache ? Color.orange : Color.green)
                .frame(width: 6, height: 6)

            Text("Updated \(lastUpdated, style: .relative) ago")
                .font(.caption)
                .foregroundColor(.secondary)

            if source == .cache {
                Text("(Cached)")
                    .font(.caption)
                    .foregroundColor(.orange)
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
        .background(Color(.secondarySystemBackground))
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
        case .whoop: return .orange
        case .healthkit: return .red
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
            HStack(spacing: 4) {
                Circle().fill(Color.indigo).frame(width: 8, height: 8)
                Text("Deep").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.blue).frame(width: 8, height: 8)
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
                .foregroundColor(value >= 0 ? .green : .orange)

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
