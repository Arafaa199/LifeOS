import SwiftUI

/// Compact music summary card for dashboard
struct MusicCardView: View {
    let music: MusicSummary?

    var body: some View {
        if let music = music, music.hasActivity {
            NavigationLink(destination: MusicView()) {
                HStack(spacing: NexusTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(NexusTheme.Colors.accent.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "music.note")
                            .font(.system(size: 18))
                            .foregroundColor(NexusTheme.Colors.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(summaryText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(NexusTheme.Colors.textPrimary)

                        if let topArtist = music.topArtist {
                            Text("Top: \(topArtist)")
                                .font(.system(size: 11))
                                .foregroundColor(NexusTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(NexusTheme.Colors.textMuted)
                }
                .padding(NexusTheme.Spacing.lg)
                .background(NexusTheme.Colors.card)
                .cornerRadius(NexusTheme.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                        .stroke(NexusTheme.Colors.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var summaryText: String {
        guard let music = music else { return "" }
        let mins = Int(music.totalMinutes)
        if mins >= 60 {
            let hrs = mins / 60
            let remaining = mins % 60
            return "\(hrs)h \(remaining)m • \(music.tracksPlayed) tracks"
        }
        return "\(mins) min • \(music.tracksPlayed) tracks"
    }
}

#Preview {
    VStack {
        MusicCardView(music: MusicSummary(
            tracksPlayed: 18,
            totalMinutes: 47,
            uniqueArtists: 5,
            topArtist: "The Weeknd",
            topAlbum: "After Hours"
        ))
        MusicCardView(music: nil)
    }
    .padding()
    .background(NexusTheme.Colors.background)
}
