import SwiftUI

/// Compact music summary card for dashboard
struct MusicCardView: View {
    let music: MusicSummary?

    var body: some View {
        if let music = music, music.hasActivity {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .foregroundColor(.pink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryText)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)

                    if let topArtist = music.topArtist {
                        Text("Top: \(topArtist)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                NavigationLink(destination: MusicView()) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.nexusCardBackground)
            .cornerRadius(12)
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
    .background(Color.nexusBackground)
}
