import SwiftUI
import MediaPlayer

struct MusicView: View {
    @StateObject private var musicService = MusicService.shared
    @State private var isLoading = false
    
    var body: some View {
        List {
            if !musicService.hasAuthorization {
                authorizationSection
            } else {
                nowPlayingSection
                todaySection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.nexusBackground)
        .navigationTitle("Music")
        .refreshable {
            await musicService.fetchTodayEvents()
        }
        .task {
            if musicService.hasAuthorization {
                await musicService.fetchTodayEvents()
            }
        }
    }
    
    // MARK: - Authorization
    
    private var authorizationSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                
                Text("Music Access Required")
                    .font(.headline)
                
                Text("Nexus needs access to Apple Music to log your listening history.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button(action: requestAuthorization) {
                    Text("Enable Access")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }
    
    private func requestAuthorization() {
        Task {
            let granted = await musicService.requestAuthorization()
            if granted && AppSettings.shared.musicLoggingEnabled {
                musicService.startObserving()
            }
        }
    }
    
    // MARK: - Now Playing

    private var nowPlayingSection: some View {
        Section("Now Playing") {
            if let track = musicService.currentTrack {
                VStack(spacing: 16) {
                    NowPlayingRow(track: track, isPlaying: musicService.isPlaying)
                    playerControls
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "pause.circle")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Not playing")
                            .foregroundColor(.secondary)
                    }
                    playerControls
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Player Controls

    private var playerControls: some View {
        HStack(spacing: 32) {
            Button {
                musicService.skipToPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)

            Button {
                musicService.togglePlayPause()
            } label: {
                Image(systemName: musicService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.nexusPrimary)
            }
            .buttonStyle(.plain)

            Button {
                musicService.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Today's History
    
    private var todaySection: some View {
        Section {
            if musicService.todayEvents.isEmpty {
                HStack {
                    Image(systemName: "music.note.list")
                        .foregroundColor(.secondary)
                    Text("No tracks today")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(musicService.todayEvents) { event in
                    TrackRow(event: event)
                }
            }
        } header: {
            HStack {
                Text("Today")
                Spacer()
                if musicService.pendingCount > 0 {
                    Text("\(musicService.pendingCount) pending")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Now Playing Row

private struct NowPlayingRow: View {
    let track: ListeningEvent
    var isPlaying: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            // Animated indicator
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isPlaying ? Color.nexusPrimary : Color.secondary)
                        .frame(width: 3, height: isPlaying ? CGFloat.random(in: 8...16) : 8)
                }
            }
            .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.trackTitle)
                    .font(.headline)
                    .lineLimit(1)
                
                if let artist = track.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let duration = track.durationSec {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Track Row

private struct TrackRow: View {
    let event: ListeningEvent
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.trackTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if let artist = event.artist {
                        Text(artist)
                            .foregroundColor(.secondary)
                    }
                    if let album = event.album, event.artist != nil {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(album)
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeString(from: event.startedAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let duration = event.durationSec {
                    Text(formatDuration(duration))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func timeString(from iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso8601) else { return "" }
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        timeFormatter.timeZone = TimeZone(identifier: "Asia/Dubai")
        return timeFormatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    NavigationView {
        MusicView()
    }
}
