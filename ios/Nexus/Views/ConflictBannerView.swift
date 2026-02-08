import SwiftUI

/// Displays a banner when sync conflicts are auto-resolved by the server
struct ConflictBannerView: View {
    @State private var showBanner = false
    @State private var conflictMessage = ""
    @State private var resolution = ""
    @State private var bannerTask: Task<Void, Never>?
    @State private var notificationQueue: [(message: String, resolution: String)] = []

    var body: some View {
        VStack(spacing: 0) {
            if showBanner {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync Conflict Resolved")
                            .font(.system(.caption, design: .default))
                            .fontWeight(.semibold)

                        Text(conflictMessage)
                            .font(.system(.caption2, design: .default))
                            .lineLimit(2)
                            .opacity(0.8)
                    }

                    Spacer()

                    Button(action: { dismissBanner() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: showBanner)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncConflictResolved)) { notification in
            handleConflictNotification(notification)
        }
        .onDisappear {
            bannerTask?.cancel()
            bannerTask = nil
        }
    }

    private func handleConflictNotification(_ notification: Notification) {
        if let message = notification.userInfo?["conflict"] as? String {
            let resolutionText = (notification.userInfo?["resolution"] as? String) ?? "auto-resolved"

            // If banner is already showing, queue this notification
            if showBanner {
                notificationQueue.append((message: message, resolution: resolutionText))
                return
            }

            conflictMessage = message
            resolution = resolutionText

            showBanner = true

            // Auto-dismiss after 5 seconds
            bannerTask?.cancel()
            bannerTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled {
                    dismissBanner()
                }
            }
        }
    }

    private func dismissBanner() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showBanner = false
        }
        bannerTask?.cancel()

        // If there are queued notifications, show the next one after a brief delay
        if !notificationQueue.isEmpty {
            let nextNotification = notificationQueue.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                conflictMessage = nextNotification.message
                resolution = nextNotification.resolution
                showBanner = true

                // Auto-dismiss after 5 seconds
                bannerTask?.cancel()
                bannerTask = Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if !Task.isCancelled {
                        dismissBanner()
                    }
                }
            }
        }
    }
}

#Preview {
    VStack {
        ConflictBannerView()
        Spacer()
    }
    .background(Color(.systemBackground))
}
