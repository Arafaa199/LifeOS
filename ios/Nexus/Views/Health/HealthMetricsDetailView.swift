import SwiftUI

struct HealthMetricsDetailView: View {
    let facts: TodayFacts
    @Environment(\.dismiss) var dismiss

    // MARK: - CSV Export State
    @State private var showingShareSheet = false
    @State private var csvURL: URL?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Vitals Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Vitals")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            hrvCard
                            rhrCard
                            recoveryCard
                            strainCard
                        }
                    }

                    // Sleep Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sleep")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            sleepDurationCard
                            deepSleepCard
                            remSleepCard
                            sleepEfficiencyCard
                        }
                    }

                    // Activity Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Activity")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            stepsCard
                            workoutCard
                        }
                    }

                    // Body Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Body")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                            weightCard
                        }
                    }

                    // Nutrition Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nutrition & Hydration")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            waterCard
                            caloriesCard
                        }
                    }

                    Spacer().frame(height: 20)
                }
                .padding(.vertical)
            }
            .background(NexusTheme.Colors.background)
            .navigationTitle("Health Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(NexusTheme.Colors.accent)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: exportCSV) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(NexusTheme.Colors.accent)
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = csvURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }

    // MARK: - Metric Cards

    private var hrvCard: some View {
        MetricDetailCard(
            title: "HRV",
            icon: "waveform.path.ecg",
            value: facts.hrv.map { "\(Int($0))" } ?? "—",
            unit: "ms",
            status: hrvStatus,
            statusColor: hrvColor,
            range: "Optimal: 50+ ms",
            interpretation: hrvInterpretation
        )
    }

    private var rhrCard: some View {
        MetricDetailCard(
            title: "Resting HR",
            icon: "heart.fill",
            value: facts.rhr.map { "\($0)" } ?? "—",
            unit: "bpm",
            status: rhrStatus,
            statusColor: rhrColor,
            range: "Optimal: <70 bpm",
            interpretation: rhrInterpretation
        )
    }

    private var recoveryCard: some View {
        MetricDetailCard(
            title: "Recovery",
            icon: "bolt.heart.fill",
            value: facts.recoveryScore.map { "\($0)" } ?? "—",
            unit: "%",
            status: recoveryStatus,
            statusColor: recoveryColor,
            range: nil,
            interpretation: recoveryInterpretation
        )
    }

    private var strainCard: some View {
        MetricDetailCard(
            title: "Strain",
            icon: "flame.fill",
            value: facts.strain.map { String(format: "%.1f", $0) } ?? "—",
            unit: "",
            status: nil,
            statusColor: nil,
            range: "Scale: 0-21",
            interpretation: strainInterpretation
        )
    }

    private var sleepDurationCard: some View {
        let hours = (facts.sleepMinutes ?? 0) / 60
        let mins = (facts.sleepMinutes ?? 0) % 60

        return MetricDetailCard(
            title: "Sleep Duration",
            icon: "moon.zzz.fill",
            value: facts.sleepMinutes.map { _ in "\(hours)h \(mins)m" } ?? "—",
            unit: "",
            status: sleepStatus,
            statusColor: sleepColor,
            range: "Goal: 7-9 hours",
            interpretation: sleepInterpretation
        )
    }

    private var deepSleepCard: some View {
        let hours = (facts.deepSleepMinutes ?? 0) / 60
        let mins = (facts.deepSleepMinutes ?? 0) % 60

        return MetricDetailCard(
            title: "Deep Sleep",
            icon: "moon.stars.fill",
            value: facts.deepSleepMinutes.map { _ in "\(hours)h \(mins)m" } ?? "—",
            unit: "",
            status: nil,
            statusColor: nil,
            range: "Goal: 1-3 hours",
            interpretation: deepSleepInterpretation
        )
    }

    private var remSleepCard: some View {
        let hours = (facts.remSleepMinutes ?? 0) / 60
        let mins = (facts.remSleepMinutes ?? 0) % 60

        return MetricDetailCard(
            title: "REM Sleep",
            icon: "zzz",
            value: facts.remSleepMinutes.map { _ in "\(hours)h \(mins)m" } ?? "—",
            unit: "",
            status: nil,
            statusColor: nil,
            range: "Goal: 1-2 hours",
            interpretation: remSleepInterpretation
        )
    }

    private var sleepEfficiencyCard: some View {
        MetricDetailCard(
            title: "Sleep Efficiency",
            icon: "percent",
            value: facts.sleepEfficiency.map { String(format: "%.0f", $0) } ?? "—",
            unit: "%",
            status: nil,
            statusColor: nil,
            range: "Optimal: >85%",
            interpretation: sleepEfficiencyInterpretation
        )
    }

    private var stepsCard: some View {
        MetricDetailCard(
            title: "Steps",
            icon: "figure.walk",
            value: facts.steps.map { formatNumber($0) } ?? "—",
            unit: "steps",
            status: nil,
            statusColor: nil,
            range: "Goal: 10,000+",
            interpretation: stepsInterpretation
        )
    }

    private var workoutCard: some View {
        MetricDetailCard(
            title: "Workouts",
            icon: "figure.strengthtraining.traditional",
            value: facts.workoutCount.map { "\($0)" } ?? "—",
            unit: facts.workoutMinutes.map { " • \($0)m" } ?? "",
            status: nil,
            statusColor: nil,
            range: nil,
            interpretation: workoutInterpretation
        )
    }

    private var weightCard: some View {
        MetricDetailCard(
            title: "Weight",
            icon: "scalemass.fill",
            value: facts.weightKg.map { String(format: "%.1f", $0) } ?? "—",
            unit: "kg",
            status: weightStatus,
            statusColor: weightColor,
            range: nil,
            interpretation: weightInterpretation
        )
    }

    private var waterCard: some View {
        let liters = Double(facts.waterMl ?? 0) / 1000.0

        return MetricDetailCard(
            title: "Water",
            icon: "drop.fill",
            value: facts.waterMl.map { _ in liters > 0 ? String(format: "%.1f", liters) : "0" } ?? "—",
            unit: "L",
            status: waterStatus,
            statusColor: waterColor,
            range: "Goal: 2-3 L",
            interpretation: waterInterpretation
        )
    }

    private var caloriesCard: some View {
        MetricDetailCard(
            title: "Calories",
            icon: "flame.circle.fill",
            value: facts.caloriesConsumed.map { formatNumber($0) } ?? "—",
            unit: "kcal",
            status: nil,
            statusColor: nil,
            range: "Typical: 1500-2500",
            interpretation: caloriesInterpretation
        )
    }

    // MARK: - Status & Color Logic

    private var hrvStatus: String? {
        guard let hrv = facts.hrv else { return nil }
        if hrv > 50 { return "Excellent" }
        if hrv > 30 { return "Good" }
        return "Low"
    }

    private var hrvColor: Color? {
        guard let hrv = facts.hrv else { return nil }
        if hrv > 50 { return NexusTheme.Colors.Semantic.green }
        if hrv > 30 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.red
    }

    private var hrvInterpretation: String {
        guard let hrv = facts.hrv else { return "No data available" }
        if hrv > 50 { return "Your heart rate variability is excellent. You're well recovered." }
        if hrv > 30 { return "Your HRV is moderate. Keep monitoring rest and recovery." }
        return "Low HRV may indicate stress or fatigue. Consider rest days."
    }

    private var rhrStatus: String? {
        guard let rhr = facts.rhr else { return nil }
        if rhr < 70 { return "Excellent" }
        if rhr < 85 { return "Good" }
        return "High"
    }

    private var rhrColor: Color? {
        guard let rhr = facts.rhr else { return nil }
        if rhr < 70 { return NexusTheme.Colors.Semantic.green }
        if rhr < 85 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.red
    }

    private var rhrInterpretation: String {
        guard let rhr = facts.rhr else { return "No data available" }
        if rhr < 70 { return "Excellent resting heart rate. Great cardiovascular fitness." }
        if rhr < 85 { return "Good resting heart rate. Continue your fitness routine." }
        return "Your resting HR is elevated. More rest and recovery may help."
    }

    private var recoveryStatus: String? {
        guard let recovery = facts.recoveryScore else { return nil }
        if recovery >= 67 { return "High" }
        if recovery >= 34 { return "Moderate" }
        return "Low"
    }

    private var recoveryColor: Color? {
        guard let recovery = facts.recoveryScore else { return nil }
        if recovery >= 67 { return NexusTheme.Colors.Semantic.green }
        if recovery >= 34 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.red
    }

    private var recoveryInterpretation: String {
        guard let recovery = facts.recoveryScore else { return "No data available" }
        if recovery >= 67 { return "You're fully recovered. Push your limits today." }
        if recovery >= 34 { return "Moderate recovery. Good day for moderate activity." }
        return "Your recovery is low. Take it easy today. Rest is important."
    }

    private var strainInterpretation: String {
        guard let strain = facts.strain else { return "No data available" }
        if strain > 15 { return "Very high strain accumulated. Focus on recovery." }
        if strain > 10 { return "High strain from activity. Get good rest tonight." }
        if strain > 5 { return "Moderate strain. You're pushing yourself well." }
        return "Low strain. Consider increasing activity intensity."
    }

    private var sleepStatus: String? {
        guard let sleepMinutes = facts.sleepMinutes else { return nil }
        let hours = Double(sleepMinutes) / 60.0
        if hours >= 7 && hours <= 9 { return "Optimal" }
        if hours >= 6.5 && hours <= 9.5 { return "Good" }
        if hours < 6.5 { return "Low" }
        return "High"
    }

    private var sleepColor: Color? {
        guard let sleepMinutes = facts.sleepMinutes else { return nil }
        let hours = Double(sleepMinutes) / 60.0
        if hours >= 7 && hours <= 9 { return NexusTheme.Colors.Semantic.green }
        if hours >= 6.5 && hours <= 9.5 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.red
    }

    private var sleepInterpretation: String {
        guard let sleepMinutes = facts.sleepMinutes else { return "No data available" }
        let hours = Double(sleepMinutes) / 60.0
        if hours >= 7 && hours <= 9 { return "Excellent sleep duration. This supports recovery." }
        if hours >= 6.5 && hours <= 9.5 { return "Good sleep. Close to optimal range." }
        if hours < 6.5 { return "Sleep was short. Try to get more tonight." }
        return "Sleep was long. You may be fatigued or need extra recovery."
    }

    private var deepSleepInterpretation: String {
        guard let deepSleepMinutes = facts.deepSleepMinutes else { return "No data available" }
        let hours = Double(deepSleepMinutes) / 60.0
        if hours >= 1 && hours <= 3 { return "Good deep sleep. Important for physical recovery." }
        if hours < 1 { return "Limited deep sleep. Check sleep environment." }
        return "Extended deep sleep phase. Excellent recovery time."
    }

    private var remSleepInterpretation: String {
        guard let remSleepMinutes = facts.remSleepMinutes else { return "No data available" }
        let hours = Double(remSleepMinutes) / 60.0
        if hours >= 1 && hours <= 2 { return "Good REM sleep. Important for mental recovery." }
        if hours < 1 { return "Low REM sleep. May need more sleep time." }
        return "Extended REM phase. Good for cognitive function."
    }

    private var sleepEfficiencyInterpretation: String {
        guard let efficiency = facts.sleepEfficiency else { return "No data available" }
        if efficiency > 85 { return "Excellent efficiency. Minimal time awake." }
        if efficiency > 75 { return "Good sleep efficiency. Minor disturbances." }
        return "Sleep efficiency is lower than desired. Check for disturbances."
    }

    private var stepsInterpretation: String {
        guard let steps = facts.steps else { return "No data available" }
        if steps >= 10000 { return "Great daily activity. You hit your goal." }
        if steps >= 7500 { return "Good activity level. Keep moving." }
        if steps >= 5000 { return "Moderate activity. Try to increase movement." }
        return "Low activity. Consider adding more movement throughout the day."
    }

    private var workoutInterpretation: String {
        guard let workoutCount = facts.workoutCount else { return "No workout data" }
        if workoutCount == 0 { return "No workouts logged today. Consider some activity." }
        if workoutCount == 1 { return "Good, one workout. Keep it up." }
        return "Multiple workouts today. Make sure to balance with recovery."
    }

    private var weightStatus: String? {
        guard let weightVs7d = facts.weightVs7d else { return nil }
        if abs(weightVs7d) < 0.5 { return "Stable" }
        if weightVs7d > 0 { return "Up" }
        return "Down"
    }

    private var weightColor: Color? {
        guard let weightVs7d = facts.weightVs7d else { return nil }
        if abs(weightVs7d) < 0.5 { return NexusTheme.Colors.Semantic.green }
        return NexusTheme.Colors.Semantic.amber
    }

    private var weightInterpretation: String {
        guard let weight = facts.weightKg else { return "No data available" }
        if let vs7d = facts.weightVs7d {
            if abs(vs7d) < 0.5 { return "Your weight is stable vs last week. Good consistency." }
            if vs7d > 0 { return "Weight up \(String(format: "%.1f", vs7d))kg vs 7-day avg. Check nutrition." }
            return "Weight down \(String(format: "%.1f", abs(vs7d)))kg vs 7-day avg. Good progress."
        }
        return "Current weight: \(String(format: "%.1f", weight))kg. Track trends over time."
    }

    private var waterStatus: String? {
        guard let waterMl = facts.waterMl else { return nil }
        let liters = Double(waterMl) / 1000.0
        if liters >= 2 && liters <= 3 { return "On track" }
        if liters > 3 { return "Good" }
        return "Low"
    }

    private var waterColor: Color? {
        guard let waterMl = facts.waterMl else { return nil }
        let liters = Double(waterMl) / 1000.0
        if liters >= 2 { return NexusTheme.Colors.Semantic.green }
        if liters >= 1.5 { return NexusTheme.Colors.Semantic.amber }
        return NexusTheme.Colors.Semantic.red
    }

    private var waterInterpretation: String {
        guard let waterMl = facts.waterMl else { return "No hydration data" }
        let liters = Double(waterMl) / 1000.0
        if liters >= 2 && liters <= 3 { return "Excellent hydration. You're on track." }
        if liters < 2 { return "Low water intake. Try to drink more." }
        return "High water intake. Great job staying hydrated."
    }

    private var caloriesInterpretation: String {
        guard let calories = facts.caloriesConsumed else { return "No nutrition data" }
        if calories >= 1500 && calories <= 2500 { return "Reasonable calorie intake for the day." }
        if calories < 1500 { return "Lower calorie consumption. Check if this was intentional." }
        return "Higher calorie consumption. Monitor intake if needed."
    }

    // MARK: - CSV Export

    private func exportCSV() {
        var csv = "Metric,Value,Unit,Status\n"

        if let hrv = facts.hrv {
            csv += "HRV,\(Int(hrv)),ms,\(hrvStatus ?? "Unknown")\n"
        }

        if let rhr = facts.rhr {
            csv += "Resting HR,\(rhr),bpm,\(rhrStatus ?? "Unknown")\n"
        }

        if let recovery = facts.recoveryScore {
            csv += "Recovery,\(recovery),%,\(recoveryStatus ?? "Unknown")\n"
        }

        if let strain = facts.strain {
            csv += "Strain,\(String(format: "%.1f", strain)),,\n"
        }

        if let sleepMinutes = facts.sleepMinutes {
            let hours = sleepMinutes / 60
            let mins = sleepMinutes % 60
            csv += "Sleep Duration,\(hours)h \(mins)m,min,\(sleepStatus ?? "Unknown")\n"
        }

        if let deepSleep = facts.deepSleepMinutes {
            let hours = deepSleep / 60
            let mins = deepSleep % 60
            csv += "Deep Sleep,\(hours)h \(mins)m,min,\n"
        }

        if let remSleep = facts.remSleepMinutes {
            let hours = remSleep / 60
            let mins = remSleep % 60
            csv += "REM Sleep,\(hours)h \(mins)m,min,\n"
        }

        if let efficiency = facts.sleepEfficiency {
            csv += "Sleep Efficiency,\(String(format: "%.1f", efficiency)),%,\n"
        }

        if let steps = facts.steps {
            csv += "Steps,\(steps),steps,\n"
        }

        if let weight = facts.weightKg {
            csv += "Weight,\(String(format: "%.1f", weight)),kg,\(weightStatus ?? "Unknown")\n"
        }

        if let water = facts.waterMl {
            let liters = Double(water) / 1000.0
            csv += "Water,\(String(format: "%.1f", liters)),L,\(waterStatus ?? "Unknown")\n"
        }

        if let calories = facts.caloriesConsumed {
            csv += "Calories,\(calories),kcal,\n"
        }

        if let workouts = facts.workoutCount {
            csv += "Workouts,\(workouts),count,\n"
        }

        if let workoutMins = facts.workoutMinutes {
            csv += "Workout Duration,\(workoutMins),minutes,\n"
        }

        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: Date())
        let filename = "health-metrics-\(timestamp.prefix(10)).csv"

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.write(to: tmpURL, atomically: true, encoding: .utf8)
            csvURL = tmpURL
            showingShareSheet = true
        } catch {
            print("Failed to write CSV: \(error)")
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Metric Detail Card Component

struct MetricDetailCard: View {
    let title: String
    let icon: String
    let value: String
    let unit: String
    let status: String?
    let statusColor: Color?
    let range: String?
    let interpretation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(statusColor ?? .secondary)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value)
                            .font(.system(size: 18, weight: .bold, design: .rounded))

                        if !unit.isEmpty {
                            Text(unit)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let status = status {
                        Text(status)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(statusColor ?? .secondary)
                            .padding(.top, 2)
                    }
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                if let range = range {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text(range)
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }

                Text(interpretation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusTheme.Colors.card)
        .cornerRadius(12)
    }
}


#Preview {
    let sampleFacts = TodayFacts(
        day: "2026-02-08",
        recoveryScore: 72,
        hrv: 45.2,
        rhr: 62,
        sleepMinutes: 480,
        deepSleepMinutes: 120,
        remSleepMinutes: 90,
        sleepEfficiency: 88.5,
        strain: 8.2,
        steps: 10250,
        weightKg: 75.5,
        spendTotal: nil,
        spendGroceries: nil,
        spendRestaurants: nil,
        incomeTotal: nil,
        transactionCount: nil,
        mealsLogged: nil,
        waterMl: 2400,
        caloriesConsumed: 2150,
        proteinG: nil,
        dataCompleteness: nil,
        factsComputedAt: nil,
        workoutCount: 1,
        workoutMinutes: 45,
        recoveryVs7d: nil,
        recoveryVs30d: nil,
        hrvVs7d: nil,
        sleepVs7d: nil,
        strainVs7d: nil,
        spendVs7d: nil,
        weightVs7d: -0.2,
        recoveryUnusual: nil,
        sleepUnusual: nil,
        spendUnusual: nil,
        recovery7dAvg: nil,
        recovery30dAvg: nil,
        hrv7dAvg: nil,
        sleepMinutes7dAvg: nil,
        weight30dDelta: 0.5,
        daysWithData7d: nil,
        daysWithData30d: nil,
        baselinesComputedAt: nil
    )

    HealthMetricsDetailView(facts: sampleFacts)
}
