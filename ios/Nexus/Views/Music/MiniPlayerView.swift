import SwiftUI
import MusicKit

/// Compact mini player bar that shows at bottom of screen
struct MiniPlayerView: View {
    @ObservedObject var musicService: MusicKitService
    @Binding var showFullPlayer: Bool

    var body: some View {
        if musicService.currentEntry != nil {
            HStack(spacing: 12) {
                // Artwork
                Button(action: { showFullPlayer = true }) {
                    HStack(spacing: 12) {
                        if let artwork = musicService.artwork {
                            ArtworkImage(artwork, width: 48, height: 48)
                                .cornerRadius(6)
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundColor(.secondary)
                                )
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(musicService.currentTitle)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)

                            Text(musicService.currentArtist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                // Controls
                HStack(spacing: 20) {
                    Button(action: musicService.togglePlayPause) {
                        Image(systemName: musicService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    Button(action: musicService.skipToNext) {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                // Progress indicator
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.nexusPrimary)
                        .frame(width: geo.size.width * musicService.progress, height: 2)
                }
                .frame(height: 2)
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        MiniPlayerView(musicService: MusicKitService.shared, showFullPlayer: .constant(false))
    }
}
