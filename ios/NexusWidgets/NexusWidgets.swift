import WidgetKit
import SwiftUI

// Widget Bundle - Entry point for all Nexus widgets
@main
struct NexusWidgets: WidgetBundle {
    var body: some Widget {
        WaterQuickLogWidget()
        DailySummaryWidget()
        RecoveryScoreWidget()
        FastingTimerWidget()
        BudgetRemainingWidget()
    }
}

// MARK: - Water Quick Log Widget

struct WaterQuickLogWidget: Widget {
    let kind: String = "WaterQuickLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WaterWidgetProvider()) { entry in
            WaterQuickLogWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Water Log")
        .description("Quickly log water intake with one tap.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct WaterWidgetEntry: TimelineEntry {
    let date: Date
    let waterToday: Int
}

struct WaterWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterWidgetEntry {
        WaterWidgetEntry(date: Date(), waterToday: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (WaterWidgetEntry) -> Void) {
        let entry = WaterWidgetEntry(date: Date(), waterToday: 0)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterWidgetEntry>) -> Void) {
        // In a real implementation, this would fetch from UserDefaults or CoreData
        let entry = WaterWidgetEntry(date: Date(), waterToday: 0)
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

struct WaterQuickLogWidgetView: View {
    var entry: WaterWidgetProvider.Entry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.title)
                .foregroundColor(.blue)

            Text("\(entry.waterToday)ml")
                .font(.title3)
                .bold()

            Text("Tap to log 250ml")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Daily Summary Widget

struct DailySummaryWidget: Widget {
    let kind: String = "DailySummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummaryWidgetProvider()) { entry in
            DailySummaryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Summary")
        .description("View your daily nutrition and health stats.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SummaryWidgetEntry: TimelineEntry {
    let date: Date
    let calories: Int
    let protein: Double
    let water: Int
    let weight: Double?
}

struct SummaryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryWidgetEntry {
        SummaryWidgetEntry(date: Date(), calories: 0, protein: 0, water: 0, weight: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryWidgetEntry) -> Void) {
        let entry = SummaryWidgetEntry(date: Date(), calories: 0, protein: 0, water: 0, weight: nil)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryWidgetEntry>) -> Void) {
        // In a real implementation, this would fetch from UserDefaults or CoreData
        let entry = SummaryWidgetEntry(date: Date(), calories: 0, protein: 0, water: 0, weight: nil)
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

struct DailySummaryWidgetView: View {
    var entry: SummaryWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if family == .systemMedium {
            mediumWidget
        } else {
            largeWidget
        }
    }

    var mediumWidget: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    StatView(icon: "flame.fill", value: "\(entry.calories)", unit: "kcal", color: .orange)
                    StatView(icon: "drop.fill", value: "\(entry.water)", unit: "ml", color: .blue)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatView(icon: "bolt.fill", value: String(format: "%.1f", entry.protein), unit: "g", color: .green)

                if let weight = entry.weight {
                    StatView(icon: "scalemass.fill", value: String(format: "%.1f", weight), unit: "kg", color: .purple)
                }
            }
        }
        .padding()
    }

    var largeWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Summary")
                .font(.headline)
                .foregroundColor(.secondary)

            Divider()

            VStack(spacing: 12) {
                WideStatRow(icon: "flame.fill", label: "Calories", value: "\(entry.calories)", unit: "kcal", color: .orange)
                WideStatRow(icon: "bolt.fill", label: "Protein", value: String(format: "%.1f", entry.protein), unit: "g", color: .green)
                WideStatRow(icon: "drop.fill", label: "Water", value: "\(entry.water)", unit: "ml", color: .blue)

                if let weight = entry.weight {
                    WideStatRow(icon: "scalemass.fill", label: "Weight", value: String(format: "%.1f", weight), unit: "kg", color: .purple)
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Recovery Score Widget

struct RecoveryScoreWidget: Widget {
    let kind: String = "RecoveryScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecoveryWidgetProvider()) { entry in
            RecoveryScoreWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recovery Score")
        .description("View your WHOOP recovery score at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RecoveryWidgetEntry: TimelineEntry {
    let date: Date
    let recoveryScore: Int?
    let hrv: Double?
    let rhr: Int?
    let lastUpdated: Date?
}

struct RecoveryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryWidgetEntry {
        RecoveryWidgetEntry(date: Date(), recoveryScore: 65, hrv: 45.0, rhr: 52, lastUpdated: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoveryWidgetEntry) -> Void) {
        let storage = SharedStorage.shared
        let entry = RecoveryWidgetEntry(
            date: Date(),
            recoveryScore: storage.getRecoveryScore(),
            hrv: storage.getRecoveryHRV(),
            rhr: storage.getRecoveryRHR(),
            lastUpdated: storage.getRecoveryDate()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryWidgetEntry>) -> Void) {
        let storage = SharedStorage.shared
        let entry = RecoveryWidgetEntry(
            date: Date(),
            recoveryScore: storage.getRecoveryScore(),
            hrv: storage.getRecoveryHRV(),
            rhr: storage.getRecoveryRHR(),
            lastUpdated: storage.getRecoveryDate()
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct RecoveryScoreWidgetView: View {
    var entry: RecoveryWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .accessoryCircular:
            circularWidget
        case .accessoryRectangular:
            rectangularWidget
        case .accessoryInline:
            inlineWidget
        default:
            smallWidget
        }
    }

    @ViewBuilder
    var inlineWidget: some View {
        if let score = entry.recoveryScore {
            if let hrv = entry.hrv {
                Label("\(score)% Recovery · HRV \(String(format: "%.0f", hrv))", systemImage: "heart.fill")
            } else {
                Label("\(score)% Recovery", systemImage: "heart.fill")
            }
        } else {
            Label("No Recovery Data", systemImage: "heart.circle")
        }
    }

    var smallWidget: some View {
        VStack(spacing: 8) {
            if let score = entry.recoveryScore {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100.0)
                        .stroke(recoveryColor(for: score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(score)")
                            .font(.title)
                            .bold()
                        Text("%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, height: 80)

                Text("Recovery")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    if let hrv = entry.hrv {
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f", hrv))
                                .font(.caption2)
                                .bold()
                            Text("HRV")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                    if let rhr = entry.rhr {
                        VStack(spacing: 2) {
                            Text("\(rhr)")
                                .font(.caption2)
                                .bold()
                            Text("RHR")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Image(systemName: "heart.circle")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                Text("No Data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Open app to sync")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    var circularWidget: some View {
        ZStack {
            if let score = entry.recoveryScore {
                AccessoryWidgetBackground()
                Gauge(value: Double(score), in: 0...100) {
                    Text("")
                } currentValueLabel: {
                    Text("\(score)")
                        .font(.title3)
                        .bold()
                }
                .gaugeStyle(.accessoryCircular)
                .tint(recoveryColor(for: score))
            } else {
                Image(systemName: "heart.circle")
                    .font(.title2)
            }
        }
    }

    var rectangularWidget: some View {
        HStack {
            if let score = entry.recoveryScore {
                Gauge(value: Double(score), in: 0...100) {
                    Text("")
                }
                .gaugeStyle(.accessoryLinear)
                .tint(recoveryColor(for: score))
                .frame(width: 50)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(score)% Recovery")
                        .font(.caption.weight(.semibold))
                    if let hrv = entry.hrv {
                        Text("HRV \(String(format: "%.0f", hrv))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Image(systemName: "heart.circle")
                Text("No Data")
                    .font(.caption)
            }
        }
    }

    private func recoveryColor(for score: Int) -> Color {
        switch score {
        case 67...100: return .green
        case 34...66: return .yellow
        default: return .red
        }
    }
}

struct StatView: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)

            Text(value)
                .font(.caption)
                .bold()

            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct WideStatRow: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text("\(value) \(unit)")
                .bold()
        }
    }
}

// MARK: - Fasting Timer Widget

struct FastingTimerWidget: Widget {
    let kind: String = "FastingTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastingWidgetProvider()) { entry in
            FastingTimerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fasting Timer")
        .description("Track your intermittent fasting progress.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct FastingWidgetEntry: TimelineEntry {
    let date: Date
    let hoursSinceMeal: Double?
    let isActiveSession: Bool
    let sessionElapsedHours: Double?
    let goalHours: Int
    let lastMealTime: Date?
}

struct FastingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingWidgetEntry {
        FastingWidgetEntry(
            date: Date(),
            hoursSinceMeal: 14.5,
            isActiveSession: false,
            sessionElapsedHours: nil,
            goalHours: 16,
            lastMealTime: Date().addingTimeInterval(-14.5 * 3600)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FastingWidgetEntry) -> Void) {
        let storage = SharedStorage.shared
        let entry = FastingWidgetEntry(
            date: Date(),
            hoursSinceMeal: storage.getHoursSinceLastMeal(),
            isActiveSession: storage.isFastingActive(),
            sessionElapsedHours: storage.getFastingElapsedHours(),
            goalHours: storage.getFastingGoalHours(),
            lastMealTime: storage.getLastMealTime()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingWidgetEntry>) -> Void) {
        let storage = SharedStorage.shared
        let currentDate = Date()

        // Create entries for the next hour (update every 15 minutes for timer accuracy)
        var entries: [FastingWidgetEntry] = []
        for minuteOffset in stride(from: 0, through: 60, by: 15) {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate) ?? currentDate
            let entry = FastingWidgetEntry(
                date: entryDate,
                hoursSinceMeal: storage.getHoursSinceLastMeal().map { $0 + Double(minuteOffset) / 60.0 },
                isActiveSession: storage.isFastingActive(),
                sessionElapsedHours: storage.getFastingElapsedHours().map { $0 + Double(minuteOffset) / 60.0 },
                goalHours: storage.getFastingGoalHours(),
                lastMealTime: storage.getLastMealTime()
            )
            entries.append(entry)
        }

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct FastingTimerWidgetView: View {
    var entry: FastingWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    /// The effective fasting hours (active session takes priority)
    private var effectiveHours: Double? {
        if entry.isActiveSession, let sessionHours = entry.sessionElapsedHours {
            return sessionHours
        }
        return entry.hoursSinceMeal
    }

    /// Progress toward goal (0.0 to 1.0)
    private var progress: Double {
        guard let hours = effectiveHours else { return 0 }
        return min(hours / Double(entry.goalHours), 1.0)
    }

    /// Color based on progress
    private var progressColor: Color {
        guard let hours = effectiveHours else { return .gray }
        if hours >= Double(entry.goalHours) {
            return .green
        } else if hours >= Double(entry.goalHours) * 0.75 {
            return .yellow
        } else {
            return .orange
        }
    }

    /// Format hours as HH:MM
    private var timerDisplay: String {
        guard let hours = effectiveHours else { return "--:--" }
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return String(format: "%d:%02d", h, m)
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        case .accessoryCircular:
            circularWidget
        case .accessoryRectangular:
            rectangularWidget
        default:
            smallWidget
        }
    }

    var smallWidget: some View {
        VStack(spacing: 8) {
            if effectiveHours != nil {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(timerDisplay)
                            .font(.title2)
                            .bold()
                            .monospacedDigit()
                        Text("\(entry.goalHours)h goal")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, height: 80)

                if entry.isActiveSession {
                    Text("Fasting")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .bold()
                } else {
                    Text("Since meal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if progress >= 1.0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption2)
                        Text("Goal reached!")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            } else {
                Image(systemName: "fork.knife.circle")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                Text("No Data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Log a meal to start")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    var mediumWidget: some View {
        HStack(spacing: 16) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(timerDisplay)
                        .font(.title3)
                        .bold()
                        .monospacedDigit()
                }
            }
            .frame(width: 70, height: 70)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "fork.knife.circle")
                        .foregroundColor(.orange)
                    Text(entry.isActiveSession ? "Fasting Session" : "Intermittent Fasting")
                        .font(.headline)
                }

                if let hours = effectiveHours {
                    Text("\(String(format: "%.1f", hours))h of \(entry.goalHours)h goal")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if progress >= 1.0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Goal reached!")
                            .font(.caption)
                            .foregroundColor(.green)
                            .bold()
                    }
                } else {
                    let remaining = max(0, Double(entry.goalHours) - (effectiveHours ?? 0))
                    let remainingH = Int(remaining)
                    let remainingM = Int((remaining - Double(remainingH)) * 60)
                    Text("\(remainingH)h \(remainingM)m to go")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Goal badges
                HStack(spacing: 8) {
                    ForEach([16, 18, 20], id: \.self) { goal in
                        goalBadge(hours: goal)
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func goalBadge(hours: Int) -> some View {
        let achieved = (effectiveHours ?? 0) >= Double(hours)
        Text("\(hours)h")
            .font(.caption2)
            .bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(achieved ? Color.green.opacity(0.8) : Color.gray.opacity(0.3))
            .foregroundColor(achieved ? .white : .secondary)
            .cornerRadius(4)
    }

    var circularWidget: some View {
        ZStack {
            if effectiveHours != nil {
                Gauge(value: progress) {
                    Text("")
                } currentValueLabel: {
                    Text(timerDisplay)
                        .font(.caption2)
                        .bold()
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .tint(progressColor)
            } else {
                Image(systemName: "fork.knife.circle")
                    .font(.title2)
            }
        }
    }

    var rectangularWidget: some View {
        HStack {
            if effectiveHours != nil {
                Gauge(value: progress) {
                    Text("")
                }
                .gaugeStyle(.accessoryLinear)
                .tint(progressColor)
                .frame(width: 60)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.isActiveSession ? "Fasting" : "Since meal")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(timerDisplay)
                        .font(.headline)
                        .bold()
                        .monospacedDigit()
                }
            } else {
                Image(systemName: "fork.knife.circle")
                Text("No Data")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Widget Previews

#Preview(as: .systemSmall) {
    WaterQuickLogWidget()
} timeline: {
    WaterWidgetEntry(date: .now, waterToday: 1500)
}

#Preview(as: .systemMedium) {
    DailySummaryWidget()
} timeline: {
    SummaryWidgetEntry(date: .now, calories: 1850, protein: 120.5, water: 2000, weight: 75.2)
}

#Preview(as: .systemLarge) {
    DailySummaryWidget()
} timeline: {
    SummaryWidgetEntry(date: .now, calories: 1850, protein: 120.5, water: 2000, weight: 75.2)
}

#Preview(as: .systemSmall) {
    RecoveryScoreWidget()
} timeline: {
    RecoveryWidgetEntry(date: .now, recoveryScore: 72, hrv: 48.5, rhr: 54, lastUpdated: .now)
    RecoveryWidgetEntry(date: .now, recoveryScore: nil, hrv: nil, rhr: nil, lastUpdated: nil)
}

#Preview(as: .systemSmall) {
    FastingTimerWidget()
} timeline: {
    FastingWidgetEntry(date: .now, hoursSinceMeal: 14.5, isActiveSession: false, sessionElapsedHours: nil, goalHours: 16, lastMealTime: .now.addingTimeInterval(-14.5 * 3600))
    FastingWidgetEntry(date: .now, hoursSinceMeal: 17.2, isActiveSession: false, sessionElapsedHours: nil, goalHours: 16, lastMealTime: .now.addingTimeInterval(-17.2 * 3600))
}

#Preview(as: .systemMedium) {
    FastingTimerWidget()
} timeline: {
    FastingWidgetEntry(date: .now, hoursSinceMeal: 12.3, isActiveSession: true, sessionElapsedHours: 12.3, goalHours: 16, lastMealTime: .now.addingTimeInterval(-12.3 * 3600))
}

// MARK: - Budget Remaining Widget

struct BudgetRemainingWidget: Widget {
    let kind: String = "BudgetRemainingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BudgetWidgetProvider()) { entry in
            BudgetRemainingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Budget Remaining")
        .description("Track your monthly budget at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct BudgetWidgetEntry: TimelineEntry {
    let date: Date
    let remaining: Double
    let total: Double
    let spent: Double
    let currency: String
    let topCategory: (name: String, spent: Double, limit: Double)?

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(spent / total, 1.0)
    }

    var progressColor: Color {
        let remaining = 1.0 - progress
        if remaining > 0.5 { return .green }
        if remaining > 0.2 { return .yellow }
        return .red
    }

    static var placeholder: BudgetWidgetEntry {
        BudgetWidgetEntry(
            date: .now,
            remaining: 2500,
            total: 5000,
            spent: 2500,
            currency: "AED",
            topCategory: nil
        )
    }
}

struct BudgetWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetWidgetEntry) -> Void) {
        let entry = createEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetWidgetEntry>) -> Void) {
        let entry = createEntry()
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func createEntry() -> BudgetWidgetEntry {
        let storage = SharedStorage.shared
        return BudgetWidgetEntry(
            date: .now,
            remaining: storage.getBudgetRemaining(),
            total: storage.getBudgetTotal(),
            spent: storage.getBudgetSpent(),
            currency: storage.getBudgetCurrency(),
            topCategory: storage.getBudgetTopCategory()
        )
    }
}

struct BudgetRemainingWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: BudgetWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .accessoryCircular:
            circularWidget
        case .accessoryRectangular:
            rectangularWidget
        default:
            smallWidget
        }
    }

    // MARK: - Small Widget

    private var smallWidget: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(entry.progressColor)
                Text("Budget")
                    .font(.caption.weight(.semibold))
                Spacer()
            }

            Spacer()

            // Amount remaining
            VStack(spacing: 2) {
                Text(formatCurrency(entry.remaining))
                    .font(.title2.weight(.bold))
                    .foregroundColor(entry.progressColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("left of \(formatCurrency(entry.total))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(entry.progressColor)
                        .frame(width: geo.size.width * entry.progress, height: 6)
                }
            }
            .frame(height: 6)

            // Percentage
            Text("\(Int(entry.progress * 100))% spent")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Circular Accessory

    private var circularWidget: some View {
        Gauge(value: 1.0 - entry.progress, in: 0...1) {
            Image(systemName: "creditcard.fill")
        } currentValueLabel: {
            Text("\(Int((1.0 - entry.progress) * 100))")
                .font(.system(.body, design: .rounded).weight(.bold))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(entry.progressColor)
    }

    // MARK: - Rectangular Accessory

    private var rectangularWidget: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "creditcard.fill")
                Text("Budget")
                    .font(.caption.weight(.semibold))
            }

            Text("\(entry.currency) \(Int(entry.remaining)) left")
                .font(.system(.body, design: .rounded).weight(.bold))

            Gauge(value: 1.0 - entry.progress, in: 0...1) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
            .tint(entry.progressColor)
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = entry.currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(entry.currency) \(Int(amount))"
    }
}

#Preview(as: .systemSmall) {
    BudgetRemainingWidget()
} timeline: {
    BudgetWidgetEntry(date: .now, remaining: 2500, total: 5000, spent: 2500, currency: "AED", topCategory: nil)
    BudgetWidgetEntry(date: .now, remaining: 800, total: 5000, spent: 4200, currency: "AED", topCategory: nil)
    BudgetWidgetEntry(date: .now, remaining: 0, total: 5000, spent: 5000, currency: "AED", topCategory: nil)
}
