import SwiftUI

/// Shows available Siri shortcuts for voice commands
struct SiriShortcutsView: View {
    var body: some View {
        List {
            Section {
                Text("Use these Siri phrases to log data without opening the app.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section {
                ShortcutRow(icon: "drop.fill", iconColor: NexusTheme.Colors.Semantic.blue, title: "Log Water",
                           phrase: "\"Hey Siri, log 500 ml water in Nexus\"")
                ShortcutRow(icon: "face.smiling", iconColor: NexusTheme.Colors.accent, title: "Log Mood",
                           phrase: "\"Hey Siri, log mood 7 in Nexus\"")
                ShortcutRow(icon: "scalemass", iconColor: NexusTheme.Colors.Semantic.green, title: "Log Weight",
                           phrase: "\"Hey Siri, log weight 75 kilos in Nexus\"")
            } header: {
                Text("Logging")
            }

            Section {
                ShortcutRow(icon: "timer", iconColor: NexusTheme.Colors.Semantic.amber, title: "Start Fast",
                           phrase: "\"Hey Siri, start my fast in Nexus\"")
                ShortcutRow(icon: "fork.knife", iconColor: NexusTheme.Colors.Semantic.amber, title: "Break Fast",
                           phrase: "\"Hey Siri, break my fast in Nexus\"")
            } header: {
                Text("Fasting")
            }

            Section {
                Text("Shortcuts are automatically available after installing the app. Say the phrases above to Siri to use them.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NexusTheme.Colors.background)
        .navigationTitle("Siri Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ShortcutRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let phrase: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(phrase)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }
}
