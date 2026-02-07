import SwiftUI

/// Offline banner for Today view with queue indicator
struct TodayOfflineBanner: View {
    let pendingCount: Int

    init(pendingCount: Int = 0) {
        self.pendingCount = pendingCount
    }

    var body: some View {
        HStack(spacing: NexusTheme.Spacing.xs) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11))
            Text(bannerText)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            if pendingCount > 0 {
                queueBadge
            }
        }
        .foregroundColor(NexusTheme.Colors.Semantic.amber)
        .padding(.horizontal, NexusTheme.Spacing.md)
        .padding(.vertical, NexusTheme.Spacing.xs)
        .background(NexusTheme.Colors.Semantic.amber.opacity(0.10))
        .cornerRadius(NexusTheme.Radius.sm)
        .accessibilityLabel(accessibilityText)
    }

    private var bannerText: String {
        if pendingCount > 0 {
            return "Offline — \(pendingCount) item\(pendingCount == 1 ? "" : "s") queued"
        }
        return "Offline — showing saved data"
    }

    private var queueBadge: some View {
        HStack(spacing: NexusTheme.Spacing.xxxs) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9))
            Text("\(pendingCount)")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, NexusTheme.Spacing.xs)
        .padding(.vertical, NexusTheme.Spacing.xxxs)
        .background(NexusTheme.Colors.Semantic.amber)
        .cornerRadius(NexusTheme.Radius.md)
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
            HStack(spacing: NexusTheme.Spacing.xs) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9))
            }
            .foregroundColor(NexusTheme.Colors.Semantic.amber)
            .padding(.horizontal, NexusTheme.Spacing.md)
            .padding(.vertical, NexusTheme.Spacing.xxs)
            .background(NexusTheme.Colors.Semantic.amber.opacity(0.10))
            .cornerRadius(NexusTheme.Radius.xs)
        }
        .buttonStyle(.plain)
    }
}

/// Cached data banner for Today view
struct TodayCachedBanner: View {
    let cacheAge: String?

    var body: some View {
        HStack(spacing: NexusTheme.Spacing.xs) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
            Text("Showing cached data")
                .font(.system(size: 11, weight: .medium))
            if let age = cacheAge {
                Text("(\(age))")
                    .font(.system(size: 11))
            }
            Spacer()
        }
        .foregroundColor(NexusTheme.Colors.textSecondary)
        .padding(.horizontal, NexusTheme.Spacing.md)
        .padding(.vertical, NexusTheme.Spacing.xs)
        .background(NexusTheme.Colors.cardAlt)
        .cornerRadius(NexusTheme.Radius.sm)
        .accessibilityLabel("Showing cached data\(cacheAge.map { ", \($0) old" } ?? "")")
    }
}

/// Syncing queue banner (online but has pending items)
struct TodaySyncingBanner: View {
    let pendingCount: Int

    var body: some View {
        HStack(spacing: NexusTheme.Spacing.xs) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Syncing \(pendingCount) item\(pendingCount == 1 ? "" : "s")...")
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .foregroundColor(NexusTheme.Colors.accent)
        .padding(.horizontal, NexusTheme.Spacing.md)
        .padding(.vertical, NexusTheme.Spacing.xs)
        .background(NexusTheme.Colors.accent.opacity(0.08))
        .cornerRadius(NexusTheme.Radius.sm)
        .accessibilityLabel("Syncing \(pendingCount) queued item\(pendingCount == 1 ? "" : "s").")
    }
}

/// No data state for Today view
struct TodayNoDataView: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: NexusTheme.Spacing.xxl) {
            Spacer().frame(height: 40)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(NexusTheme.Colors.accent.opacity(0.5))

            VStack(spacing: NexusTheme.Spacing.xs) {
                Text("Waiting for data")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(NexusTheme.Colors.textPrimary)

                Text("Pull down to refresh, or check Settings to verify your sync sources are connected.")
                    .font(.system(size: 14))
                    .foregroundColor(NexusTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, NexusTheme.Spacing.xxxl)
            }

            Button {
                onRefresh()
            } label: {
                HStack(spacing: NexusTheme.Spacing.xxs) {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, NexusTheme.Spacing.xxxl)
                .padding(.vertical, NexusTheme.Spacing.md)
                .background(NexusTheme.Colors.accent)
                .cornerRadius(NexusTheme.Radius.md)
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
        .background(NexusTheme.Colors.background)
}

#Preview("Offline - With Queue") {
    TodayOfflineBanner(pendingCount: 3)
        .padding()
        .background(NexusTheme.Colors.background)
}

#Preview("Syncing") {
    TodaySyncingBanner(pendingCount: 2)
        .padding()
        .background(NexusTheme.Colors.background)
}

#Preview("Stale") {
    TodayStaleBanner(text: "Health & Finance data delayed", onRefresh: {})
        .padding()
        .background(NexusTheme.Colors.background)
}

#Preview("No Data") {
    TodayNoDataView(onRefresh: {})
        .padding()
        .background(NexusTheme.Colors.background)
}
