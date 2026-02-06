import SwiftUI

/// Offline banner for Today view with queue indicator
struct TodayOfflineBanner: View {
    let pendingCount: Int

    init(pendingCount: Int = 0) {
        self.pendingCount = pendingCount
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)
            Text(bannerText)
                .font(.caption.weight(.medium))
            Spacer()
            if pendingCount > 0 {
                queueBadge
            }
        }
        .foregroundColor(.nexusWarning)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.nexusWarning.opacity(0.1))
        .cornerRadius(10)
        .accessibilityLabel(accessibilityText)
    }

    private var bannerText: String {
        if pendingCount > 0 {
            return "Offline — \(pendingCount) item\(pendingCount == 1 ? "" : "s") queued"
        }
        return "Offline — showing saved data"
    }

    private var queueBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2)
            Text("\(pendingCount)")
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.nexusWarning)
        .cornerRadius(12)
    }

    private var accessibilityText: String {
        if pendingCount > 0 {
            return "Network offline. \(pendingCount) item\(pendingCount == 1 ? "" : "s") queued for sync."
        }
        return "Network offline. Showing locally saved data."
    }
}

/// Stale data banner for Today view
struct TodayStaleBanner: View {
    let text: String
    let onRefresh: () -> Void

    var body: some View {
        Button {
            onRefresh()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                Text(text)
                    .font(.caption.weight(.medium))
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
            }
            .foregroundColor(.nexusWarning)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.nexusWarning.opacity(0.12))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

/// Cached data banner for Today view
struct TodayCachedBanner: View {
    let cacheAge: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
            Text("Showing cached data")
                .font(.caption.weight(.medium))
            if let age = cacheAge {
                Text("(\(age))")
                    .font(.caption)
            }
            Spacer()
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
        .accessibilityLabel("Showing cached data\(cacheAge.map { ", \($0) old" } ?? "")")
    }
}

/// Syncing queue banner (online but has pending items)
struct TodaySyncingBanner: View {
    let pendingCount: Int

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Syncing \(pendingCount) item\(pendingCount == 1 ? "" : "s")...")
                .font(.caption.weight(.medium))
            Spacer()
        }
        .foregroundColor(.nexusPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.nexusPrimary.opacity(0.1))
        .cornerRadius(10)
        .accessibilityLabel("Syncing \(pendingCount) queued item\(pendingCount == 1 ? "" : "s").")
    }
}

/// No data state for Today view
struct TodayNoDataView: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.nexusPrimary.opacity(0.5))

            VStack(spacing: 8) {
                Text("Waiting for data")
                    .font(.title3.weight(.semibold))

                Text("Pull down to refresh, or check Settings to verify your sync sources are connected.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                onRefresh()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.nexusPrimary)
                .cornerRadius(12)
            }

            Spacer().frame(height: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No data available. Tap Sync Now to refresh.")
    }
}

#Preview("Offline - No Queue") {
    TodayOfflineBanner(pendingCount: 0)
        .padding()
}

#Preview("Offline - With Queue") {
    TodayOfflineBanner(pendingCount: 3)
        .padding()
}

#Preview("Syncing") {
    TodaySyncingBanner(pendingCount: 2)
        .padding()
}

#Preview("Stale") {
    TodayStaleBanner(text: "Health & Finance data delayed", onRefresh: {})
        .padding()
}

#Preview("No Data") {
    TodayNoDataView(onRefresh: {})
        .padding()
}
