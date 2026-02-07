import SwiftUI
import MusicKit

/// Full-screen Apple Music-style player
struct MusicPlayerView: View {
    @ObservedObject var musicService = MusicKitService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient from artwork
                artworkBackground

                VStack(spacing: 0) {
                    // Drag indicator
                    dragIndicator

                    Spacer()

                    // Album artwork
                    artworkView(size: geometry.size.width - 64)

                    Spacer()

                    // Track info
                    trackInfoSection

                    // Progress bar
                    progressSection

                    // Main controls
                    mainControls

                    // Secondary controls
                    secondaryControls

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private var artworkBackground: some View {
        ZStack {
            if let artwork = musicService.artwork {
                ArtworkImage(artwork, width: UIScreen.main.bounds.width)
                    .blur(radius: 100)
                    .scaleEffect(1.5)
            }
            Color.black.opacity(0.6)
        }
        .ignoresSafeArea()
    }

    // MARK: - Drag Indicator

    private var dragIndicator: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                Text("Now Playing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Menu {
                    Button(action: {}) {
                        Label("Add to Playlist", systemImage: "plus")
                    }
                    Button(action: {}) {
                        Label("Share Song", systemImage: "square.and.arrow.up")
                    }
                    Button(action: {}) {
                        Label("View Album", systemImage: "music.note.list")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Artwork

    private func artworkView(size: CGFloat) -> some View {
        Group {
            if let artwork = musicService.artwork {
                ArtworkImage(artwork, width: size, height: size)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }
        }
        .scaleEffect(musicService.isPlaying ? 1.0 : 0.9)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: musicService.isPlaying)
    }

    // MARK: - Track Info

    private var trackInfoSection: some View {
        VStack(spacing: 8) {
            Text(musicService.currentTitle)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
                .lineLimit(1)

            Text(musicService.currentArtist)
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            // Progress slider
            Slider(
                value: Binding(
                    get: { isDragging ? dragValue : musicService.progress },
                    set: { newValue in
                        dragValue = newValue
                        if !isDragging {
                            musicService.seek(to: newValue * musicService.duration)
                        }
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        musicService.seek(to: dragValue * musicService.duration)
                    }
                }
            )
            .accentColor(.white)

            // Time labels
            HStack {
                Text(musicService.formatTime(isDragging ? dragValue * musicService.duration : musicService.playbackTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Text("-" + musicService.formatTime(musicService.duration - (isDragging ? dragValue * musicService.duration : musicService.playbackTime)))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Main Controls

    private var mainControls: some View {
        HStack(spacing: 48) {
            // Previous
            Button(action: musicService.restartOrPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }

            // Play/Pause
            Button(action: musicService.togglePlayPause) {
                Image(systemName: musicService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.white)
            }

            // Next
            Button(action: musicService.skipToNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 24)
    }

    // MARK: - Secondary Controls

    private var secondaryControls: some View {
        HStack(spacing: 48) {
            // Shuffle
            Button(action: musicService.toggleShuffle) {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundColor(musicService.shuffleMode == .songs ? .nexusPrimary : .white.opacity(0.6))
            }

            // Volume (placeholder - iOS doesn't allow programmatic volume control easily)
            Image(systemName: "speaker.wave.2.fill")
                .font(.title3)
                .foregroundColor(.white.opacity(0.6))

            // Repeat
            Button(action: musicService.toggleRepeat) {
                Image(systemName: repeatIcon)
                    .font(.title3)
                    .foregroundColor(musicService.repeatMode != .none ? .nexusPrimary : .white.opacity(0.6))
            }

            // Queue
            NavigationLink(destination: QueueView()) {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.vertical, 16)
    }

    private var repeatIcon: String {
        switch musicService.repeatMode {
        case .one: return "repeat.1"
        default: return "repeat"
        }
    }
}

// MARK: - Queue View

struct QueueView: View {
    @ObservedObject var musicService = MusicKitService.shared

    var body: some View {
        List {
            if let current = musicService.currentEntry {
                Section("Now Playing") {
                    QueueEntryRow(entry: current, isCurrent: true)
                }
            }

            Section("Up Next") {
                ForEach(upNextEntries, id: \.id) { entry in
                    QueueEntryRow(entry: entry, isCurrent: false)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Queue")
    }

    private var upNextEntries: [ApplicationMusicPlayer.Queue.Entry] {
        guard let currentIndex = musicService.queue.firstIndex(where: { $0.id == musicService.currentEntry?.id }) else {
            return Array(musicService.queue)
        }
        return Array(musicService.queue.suffix(from: currentIndex + 1))
    }
}

struct QueueEntryRow: View {
    let entry: MusicPlayer.Queue.Entry
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = entry.artwork {
                ArtworkImage(artwork, width: 44, height: 44)
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline)
                    .foregroundColor(isCurrent ? .nexusPrimary : .primary)

                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundColor(.nexusPrimary)
            }
        }
    }
}

#Preview {
    MusicPlayerView()
}
