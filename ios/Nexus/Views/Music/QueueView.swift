import SwiftUI
import MusicKit

/// View showing the current playback queue
struct QueueView: View {
    @ObservedObject private var musicService = MusicKitService.shared
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            // Now Playing
            if let current = musicService.currentEntry {
                Section("Now Playing") {
                    QueueEntryRow(entry: current, isCurrent: true)
                }
            }

            // Up Next
            if !upNextEntries.isEmpty {
                Section("Up Next") {
                    ForEach(Array(upNextEntries.enumerated()), id: \.element.id) { index, entry in
                        QueueEntryRow(entry: entry, isCurrent: false)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    // Remove from queue would require more API work
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            // History
            if !historyEntries.isEmpty {
                Section("History") {
                    ForEach(Array(historyEntries.enumerated()), id: \.element.id) { index, entry in
                        QueueEntryRow(entry: entry, isCurrent: false)
                            .opacity(0.6)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: musicService.clearQueue) {
                        Label("Clear Queue", systemImage: "trash")
                    }

                    Divider()

                    // Shuffle toggle
                    Button {
                        musicService.toggleShuffle()
                    } label: {
                        Label(
                            musicService.shuffleMode == .off ? "Shuffle On" : "Shuffle Off",
                            systemImage: musicService.shuffleMode == .off ? "shuffle" : "shuffle.circle.fill"
                        )
                    }

                    // Repeat toggle
                    Button {
                        musicService.cycleRepeatMode()
                    } label: {
                        Label(repeatLabel, systemImage: repeatIcon)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if musicService.queue.isEmpty && musicService.currentEntry == nil {
                ContentUnavailableView(
                    "Queue Empty",
                    systemImage: "list.bullet",
                    description: Text("Play some music to see it here")
                )
            }
        }
    }

    // MARK: - Computed Properties

    private var upNextEntries: [ApplicationMusicPlayer.Queue.Entry] {
        guard let current = musicService.currentEntry else {
            return musicService.queue
        }
        if let currentIndex = musicService.queue.firstIndex(where: { $0.id == current.id }) {
            return Array(musicService.queue.dropFirst(currentIndex + 1))
        }
        return []
    }

    private var historyEntries: [ApplicationMusicPlayer.Queue.Entry] {
        guard let current = musicService.currentEntry else { return [] }
        if let currentIndex = musicService.queue.firstIndex(where: { $0.id == current.id }) {
            return Array(musicService.queue.prefix(currentIndex))
        }
        return []
    }

    private var repeatLabel: String {
        switch musicService.repeatMode {
        case .none: return "Repeat All"
        case .all: return "Repeat One"
        case .one: return "Repeat Off"
        @unknown default: return "Repeat"
        }
    }

    private var repeatIcon: String {
        switch musicService.repeatMode {
        case .none: return "repeat"
        case .all: return "repeat.circle.fill"
        case .one: return "repeat.1.circle.fill"
        @unknown default: return "repeat"
        }
    }
}

// MARK: - Queue Entry Row

private struct QueueEntryRow: View {
    let entry: ApplicationMusicPlayer.Queue.Entry
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            if let artwork = entry.artwork {
                ArtworkImage(artwork, width: 50, height: 50)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(NexusTheme.Colors.cardAlt)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.secondary)
                    )
            }

            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)

                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Playing indicator
            if isCurrent {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundColor(NexusTheme.Colors.accent)
                    .symbolEffect(.variableColor.iterative)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationView {
        QueueView()
    }
}
