import SwiftUI

struct SleepView: View {
    @State private var sleepData: SleepData?
    @State private var sleepHistory: [SleepData] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        sleepSkeletonView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if let data = sleepData {
                        // Recovery Score Hero
                        if let recovery = data.recovery {
                            recoveryHeroCard(recovery)
                        }

                        // Sleep Stats
                        if let sleep = data.sleep {
                            sleepStatsSection(sleep)
                            sleepStagesSection(sleep)
                        }

                        // History Chart
                        if !sleepHistory.isEmpty {
                            sleepHistorySection
                        }
                    } else {
                        emptyStateView
                    }
                }
                .padding(.vertical)
            }
            .background(Color.nexusBackground)
            .navigationTitle("Sleep & Recovery")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadData()
            }
            .task {
                await loadData()
            }
        }
    }

    // MARK: - Recovery Hero Card

    private func recoveryHeroCard(_ recovery: RecoveryMetrics) -> some View {
        VStack(spacing: 16) {
            // Recovery Score Circle
            ZStack {
                Circle()
                    .stroke(recoveryColor(recovery.recoveryScore ?? 0).opacity(0.2), lineWidth: 12)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: CGFloat(recovery.recoveryScore ?? 0) / 100)
                    .stroke(
                        recoveryColor(recovery.recoveryScore ?? 0),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Text("\(recovery.recoveryScore ?? 0)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(recoveryColor(recovery.recoveryScore ?? 0))

                    Text("Recovery")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // HRV & RHR Stats
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.caption)
                            .foregroundColor(.nexusMood)
                        Text(String(format: "%.0f", recovery.hrv ?? 0))
                            .font(.title3.weight(.bold))
                    }
                    Text("HRV (ms)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 30)

                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.nexusError)
                        Text("\(recovery.rhr ?? 0)")
                            .font(.title3.weight(.bold))
                    }
                    Text("RHR (bpm)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let spo2 = recovery.spo2, spo2 > 0 {
                    Divider()
                        .frame(height: 30)

                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "lungs.fill")
                                .font(.caption)
                                .foregroundColor(.nexusWater)
                            Text(String(format: "%.0f", spo2))
                                .font(.title3.weight(.bold))
                        }
                        Text("SpO2 (%)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.nexusCardBackground)
        .cornerRadius(20)
        .padding(.horizontal)
    }

    // MARK: - Sleep Stats Section

    private func sleepStatsSection(_ sleep: SleepMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stats")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SleepStatCard(
                    title: "Time Asleep",
                    value: formatMinutes(sleep.totalSleepMin),
                    icon: "moon.zzz.fill",
                    color: .nexusMood
                )

                SleepStatCard(
                    title: "Time in Bed",
                    value: formatMinutes(sleep.timeInBedMin ?? 0),
                    icon: "bed.double.fill",
                    color: .nexusPrimary
                )

                SleepStatCard(
                    title: "Efficiency",
                    value: String(format: "%.0f%%", sleep.sleepEfficiency ?? 0),
                    icon: "chart.line.uptrend.xyaxis",
                    color: .nexusSuccess
                )

                SleepStatCard(
                    title: "Performance",
                    value: "\(sleep.sleepPerformance ?? 0)%",
                    icon: "star.fill",
                    color: .nexusFood
                )

                SleepStatCard(
                    title: "Sleep Cycles",
                    value: "\(sleep.cycles ?? 0)",
                    icon: "arrow.2.circlepath",
                    color: .nexusWater
                )

                SleepStatCard(
                    title: "Disturbances",
                    value: "\(sleep.disturbances ?? 0)",
                    icon: "exclamationmark.triangle",
                    color: .nexusWarning
                )
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Sleep Stages Section

    private func sleepStagesSection(_ sleep: SleepMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Stages")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                let total = Double(sleep.totalSleepMin)

                SleepStageRow(
                    stage: "Deep Sleep",
                    minutes: sleep.deepSleepMin ?? 0,
                    percentage: total > 0 ? Double(sleep.deepSleepMin ?? 0) / total : 0,
                    color: .nexusMood
                )

                SleepStageRow(
                    stage: "REM Sleep",
                    minutes: sleep.remSleepMin ?? 0,
                    percentage: total > 0 ? Double(sleep.remSleepMin ?? 0) / total : 0,
                    color: .nexusMood
                )

                SleepStageRow(
                    stage: "Light Sleep",
                    minutes: sleep.lightSleepMin ?? 0,
                    percentage: total > 0 ? Double(sleep.lightSleepMin ?? 0) / total : 0,
                    color: .nexusPrimary
                )

                SleepStageRow(
                    stage: "Awake",
                    minutes: sleep.awakeMin ?? 0,
                    percentage: (sleep.timeInBedMin ?? 0) > 0 ? Double(sleep.awakeMin ?? 0) / Double(sleep.timeInBedMin ?? 1) : 0,
                    color: .secondary
                )
            }
            .padding()
            .background(Color.nexusCardBackground)
            .cornerRadius(16)
            .padding(.horizontal)
        }
    }

    // MARK: - Sleep History

    private var sleepHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sleepHistory.reversed()) { day in
                        SleepHistoryBar(data: day)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Supporting Views

    private var sleepSkeletonView: some View {
        VStack(spacing: 20) {
            // Recovery Hero Skeleton
            VStack(spacing: 16) {
                // Recovery Score Circle placeholder
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                        .frame(width: 140, height: 140)

                    VStack(spacing: 4) {
                        Text("--%")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .redacted(reason: .placeholder)

                        Text("Recovery")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // HRV & RHR placeholders
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("--")
                                .font(.title3.weight(.bold))
                                .redacted(reason: .placeholder)
                        }
                        Text("HRV (ms)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Divider()
                        .frame(height: 30)

                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("--")
                                .font(.title3.weight(.bold))
                                .redacted(reason: .placeholder)
                        }
                        Text("RHR (bpm)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color.nexusCardBackground)
            .cornerRadius(20)
            .padding(.horizontal)

            // Sleep Stats Skeleton
            VStack(alignment: .leading, spacing: 12) {
                Text("Sleep Stats")
                    .font(.headline)
                    .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonStatCard()
                    }
                }
                .padding(.horizontal)
            }

            // Sleep Stages Skeleton
            VStack(alignment: .leading, spacing: 12) {
                Text("Sleep Stages")
                    .font(.headline)
                    .padding(.horizontal)

                VStack(spacing: 8) {
                    ForEach(["Deep Sleep", "REM Sleep", "Light Sleep", "Awake"], id: \.self) { stage in
                        SkeletonStageRow(stage: stage)
                    }
                }
                .padding()
                .background(Color.nexusCardBackground)
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }

    private var emptyStateView: some View {
        NexusEmptyState(
            icon: "moon.zzz",
            title: "No Sleep Data",
            message: "Sleep data from Whoop will appear here once synced."
        )
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.nexusWarning)

            Text("Couldn't Load Sleep Data")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await loadData() }
            }
            .nexusSecondaryButton()
            .frame(width: 140)
        }
        .padding()
    }

    // MARK: - Helpers

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let todayResponse = NexusAPI.shared.fetchSleepData()
            async let historyResponse = NexusAPI.shared.fetchSleepHistory(days: 7)

            let (today, history) = try await (todayResponse, historyResponse)

            await MainActor.run {
                if today.success {
                    sleepData = today.data
                }
                if history.success {
                    sleepHistory = history.data ?? []
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        TimeFormatter.formatMinutes(minutes)
    }

    private func recoveryColor(_ score: Int) -> Color {
        ColorHelper.recoveryColor(for: score)
    }
}

// MARK: - Skeleton Views

struct SkeletonStatCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 16, height: 12)
                Spacer()
            }

            Text("--")
                .font(.title2.weight(.bold))
                .redacted(reason: .placeholder)

            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
                .redacted(reason: .placeholder)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nexusCardBackground)
        .cornerRadius(12)
    }
}

struct SkeletonStageRow: View {
    let stage: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 10, height: 10)

                Text(stage)
                    .font(.subheadline)

                Spacer()

                Text("--")
                    .font(.subheadline.weight(.medium))
                    .redacted(reason: .placeholder)

                Text("--%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
                    .redacted(reason: .placeholder)
            }

            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Sleep Stat Card

struct SleepStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title2.weight(.bold))

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nexusCardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Sleep Stage Row

struct SleepStageRow: View {
    let stage: String
    let minutes: Int
    let percentage: Double
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)

                Text(stage)
                    .font(.subheadline)

                Spacer()

                Text(formatMinutes(minutes))
                    .font(.subheadline.weight(.medium))

                Text(String(format: "%.0f%%", percentage * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geometry.size.width * percentage, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        TimeFormatter.formatMinutes(minutes)
    }
}

// MARK: - Sleep History Bar

struct SleepHistoryBar: View {
    let data: SleepData

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: data.date) else { return "" }
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private var recoveryScore: Int {
        data.recovery?.recoveryScore ?? 0
    }

    private var sleepHours: Double {
        Double(data.sleep?.totalSleepMin ?? 0) / 60.0
    }

    var body: some View {
        VStack(spacing: 8) {
            // Recovery score
            Text("\(recoveryScore)%")
                .font(.caption2.weight(.medium))
                .foregroundColor(recoveryColor)

            // Sleep bar
            VStack(spacing: 0) {
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.nexusMood, .nexusPrimary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 24, height: CGFloat(min(sleepHours * 12, 96)))
            }
            .frame(height: 96)

            // Hours
            Text(String(format: "%.1fh", sleepHours))
                .font(.caption2)
                .foregroundColor(.secondary)

            // Day label
            Text(dayLabel)
                .font(.caption2.weight(.medium))
        }
        .frame(width: 44)
    }

    private var recoveryColor: Color {
        ColorHelper.recoveryColor(for: recoveryScore)
    }
}

#Preview {
    SleepView()
}
