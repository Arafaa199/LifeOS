import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Interactive Water Widget with Buttons

@available(iOS 17.0, *)
struct InteractiveWaterWidget: Widget {
    let kind: String = "InteractiveWaterWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: InteractiveWaterProvider()) { entry in
            InteractiveWaterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Water Logger")
        .description("Log water with quick buttons.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@available(iOS 17.0, *)
struct InteractiveWaterProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> InteractiveWaterEntry {
        InteractiveWaterEntry(date: Date(), waterToday: 0, configuration: ConfigurationAppIntent())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> InteractiveWaterEntry {
        InteractiveWaterEntry(date: Date(), waterToday: 0, configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<InteractiveWaterEntry> {
        // In a real implementation, fetch from shared storage
        let entry = InteractiveWaterEntry(date: Date(), waterToday: 0, configuration: configuration)
        return Timeline(entries: [entry], policy: .atEnd)
    }
}

@available(iOS 17.0, *)
struct InteractiveWaterEntry: TimelineEntry {
    let date: Date
    let waterToday: Int
    let configuration: ConfigurationAppIntent
}

@available(iOS 17.0, *)
struct InteractiveWaterWidgetView: View {
    var entry: InteractiveWaterProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if family == .systemSmall {
            smallWidget
        } else {
            mediumWidget
        }
    }

    var smallWidget: some View {
        VStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.title2)
                .foregroundColor(.blue)

            Text("Water")
                .font(.title3)
                .bold()

            Button(intent: LogWaterIntent()) {
                Text("Log Water")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .foregroundColor(.blue)

                Text("Water")
                    .font(.headline)

                Spacer()
            }

            Button(intent: LogWaterIntent()) {
                Text("Log Water")
                    .font(.subheadline)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}

@available(iOS 17.0, *)
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configuration"
    static var description = IntentDescription("Configure your water widget")
}

// MARK: - Widget Preview

#if DEBUG
@available(iOS 17.0, *)
#Preview(as: .systemSmall) {
    InteractiveWaterWidget()
} timeline: {
    InteractiveWaterEntry(date: .now, waterToday: 1500, configuration: ConfigurationAppIntent())
    InteractiveWaterEntry(date: .now.addingTimeInterval(3600), waterToday: 1750, configuration: ConfigurationAppIntent())
}

@available(iOS 17.0, *)
#Preview(as: .systemMedium) {
    InteractiveWaterWidget()
} timeline: {
    InteractiveWaterEntry(date: .now, waterToday: 1500, configuration: ConfigurationAppIntent())
}
#endif
