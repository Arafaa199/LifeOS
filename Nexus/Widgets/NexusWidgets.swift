import WidgetKit
import SwiftUI

// Widget Bundle - Entry point for all Nexus widgets
@main
struct NexusWidgets: WidgetBundle {
    var body: some Widget {
        WaterQuickLogWidget()
        DailySummaryWidget()
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
