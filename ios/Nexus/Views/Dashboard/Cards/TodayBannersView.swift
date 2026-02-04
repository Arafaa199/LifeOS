import SwiftUI

/// Offline banner for Today view (minimal style)
struct TodayOfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)
            Text("Offline")
                .font(.caption.weight(.medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(8)
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
            .foregroundColor(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.12))
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
            Image(systemName: "externaldrive")
                .font(.caption)
            Text("Using cached data")
                .font(.caption.weight(.medium))
            if let age = cacheAge {
                Text("(\(age))")
                    .font(.caption)
            }
        }
        .foregroundColor(.blue)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

/// No data state for Today view
struct TodayNoDataView: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Waiting for data")
                .font(.headline)

            Text("Pull down to refresh, or check Settings > Sync Center")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onRefresh()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .cornerRadius(10)
            }
        }
        .padding(.vertical, 60)
    }
}

#Preview("Offline") {
    TodayOfflineBanner()
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
