import WidgetKit
import SwiftUI

// Widget Bundle - Entry point for all Nexus widgets
// Note: This will be moved to a Widget Extension target
// @main - Commented out to avoid conflict with NexusApp.swift
// Uncomment this when widgets are in their own extension target
struct NexusWidgets: WidgetBundle {
    var body: some Widget {
        WaterQuickLogWidget()
        DailySummaryWidget()
        RecoveryScoreWidget()
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
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
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
        default:
            smallWidget
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
                .frame(width: 60)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recovery")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(score)%")
                        .font(.headline)
                        .bold()
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
