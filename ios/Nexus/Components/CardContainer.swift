import SwiftUI

// MARK: - Card Container

/// A standardized card container that handles loading, empty, partial, and fresh states
/// Uses native iOS styling: system font, Dynamic Type, SF Symbols, subtle shadows
struct CardContainer<Content: View, EmptyContent: View>: View {
    let title: String?
    let icon: String?
    let iconColor: Color
    let isLoading: Bool
    let isEmpty: Bool
    let staleMinutes: Int?
    let emptyMessage: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let emptyContent: () -> EmptyContent

    init(
        title: String? = nil,
        icon: String? = nil,
        iconColor: Color = .secondary,
        isLoading: Bool = false,
        isEmpty: Bool = false,
        staleMinutes: Int? = nil,
        emptyMessage: String = "No data available",
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder emptyContent: @escaping () -> EmptyContent = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.isLoading = isLoading
        self.isEmpty = isEmpty
        self.staleMinutes = staleMinutes
        self.emptyMessage = emptyMessage
        self.content = content
        self.emptyContent = emptyContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header (optional)
            if let title = title {
                HStack(spacing: 8) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(iconColor)
                    }

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Stale indicator
                    if let minutes = staleMinutes {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                            Text("\(minutes)m ago")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }
                }
            }

            // Content based on state
            if isLoading {
                loadingContent
            } else if isEmpty {
                if EmptyContent.self == EmptyView.self {
                    defaultEmptyContent
                } else {
                    emptyContent()
                }
            } else {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    private var loadingContent: some View {
        HStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Spacer()
        }
        .frame(minHeight: 60)
    }

    private var defaultEmptyContent: some View {
        HStack {
            Image(systemName: "tray")
                .foregroundColor(.secondary.opacity(0.5))
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(minHeight: 40)
    }
}

// MARK: - Simple Card (no state management)

/// A simple card without state management - just styled container
struct SimpleCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    init(padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
    }
}

// MARK: - Hero Card

/// A larger hero card for primary metrics
struct HeroCard<Content: View>: View {
    let accentColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .shadow(color: accentColor.opacity(0.1), radius: 8, x: 0, y: 4)
            )
    }
}

// MARK: - Freshness Badge

struct FreshnessBadge: View {
    let lastUpdated: Date?
    let isOffline: Bool

    init(lastUpdated: Date?, isOffline: Bool = false) {
        self.lastUpdated = lastUpdated
        self.isOffline = isOffline
    }

    private var freshness: Freshness {
        Freshness(from: lastUpdated)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            if let date = lastUpdated {
                Text("Updated \(date, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Never synced")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isOffline {
                Text("• Offline")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var dotColor: Color {
        if isOffline { return .orange }

        switch freshness {
        case .fresh, .recent: return .green
        case .stale: return .orange
        case .old: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Mini Sparkline

struct MiniSparkline: View {
    let data: [Double]
    let color: Color
    let height: CGFloat

    init(data: [Double], color: Color = .blue, height: CGFloat = 30) {
        self.data = data
        self.color = color
        self.height = height
    }

    var body: some View {
        GeometryReader { geo in
            if data.count >= 2 {
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = max(maxVal - minVal, 1)

                Path { path in
                    let stepX = geo.size.width / CGFloat(data.count - 1)

                    for (index, value) in data.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = geo.size.height - (CGFloat(value - minVal) / CGFloat(range)) * geo.size.height

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Delta Badge

struct DeltaBadge: View {
    let value: Double
    let suffix: String
    let invertColors: Bool

    init(_ value: Double, suffix: String = "%", invertColors: Bool = false) {
        self.value = value
        self.suffix = suffix
        self.invertColors = invertColors
    }

    private var isPositive: Bool {
        invertColors ? value < 0 : value >= 0
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.semibold))

            Text("\(value >= 0 ? "+" : "")\(String(format: "%.0f", value))\(suffix)")
                .font(.caption.weight(.medium))
        }
        .foregroundColor(isPositive ? .green : .orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isPositive ? Color.green : Color.orange).opacity(0.12))
        .cornerRadius(8)
    }
}

// MARK: - Progress Ring

struct ProgressRing: View {
    let progress: Double  // 0.0 to 1.0
    let color: Color
    let lineWidth: CGFloat
    let size: CGFloat

    init(progress: Double, color: Color, lineWidth: CGFloat = 8, size: CGFloat = 70) {
        self.progress = min(max(progress, 0), 1)
        self.color = color
        self.lineWidth = lineWidth
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Horizontal Progress Bar

struct HorizontalProgressBar: View {
    let progress: Double
    let color: Color
    let height: CGFloat

    init(progress: Double, color: Color, height: CGFloat = 6) {
        self.progress = min(max(progress, 0), 1)
        self.color = color
        self.height = height
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.tertiarySystemFill))

                Rectangle()
                    .fill(color)
                    .frame(width: geo.size.width * progress)
            }
            .cornerRadius(height / 2)
        }
        .frame(height: height)
    }
}

// MARK: - Category Row

struct CardCategoryRow: View {
    let name: String
    let amount: Double
    let progress: Double
    let color: Color
    let currency: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Text(formatCurrency(amount, currency: currency))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
            }

            HorizontalProgressBar(progress: progress, color: color)
        }
    }
}

// MARK: - Preview Helpers

#Preview("Card States") {
    ScrollView {
        VStack(spacing: 16) {
            CardContainer(
                title: "Loading State",
                icon: "chart.bar",
                iconColor: .blue,
                isLoading: true,
                emptyMessage: "No data"
            ) {
                Text("Content")
            }

            CardContainer(
                title: "Empty State",
                icon: "chart.bar",
                iconColor: .blue,
                isEmpty: true,
                emptyMessage: "No transactions yet"
            ) {
                Text("Content")
            }

            CardContainer(
                title: "Partial State",
                icon: "chart.bar",
                iconColor: .blue,
                staleMinutes: 15,
                emptyMessage: "No data"
            ) {
                Text("Stale content from 15 min ago")
            }

            CardContainer(
                title: "Fresh State",
                icon: "chart.bar",
                iconColor: .blue,
                emptyMessage: "No data"
            ) {
                Text("Fresh content!")
            }

            HeroCard(accentColor: .blue) {
                VStack(alignment: .leading) {
                    Text("Hero Card")
                        .font(.headline)
                    Text("1,234 AED")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }
            }

            SimpleCard {
                HStack {
                    Text("Simple Card")
                    Spacer()
                    DeltaBadge(12.5)
                }
            }

            FreshnessBadge(lastUpdated: Date().addingTimeInterval(-300))

            MiniSparkline(data: [65, 72, 58, 80, 75, 82, 78], color: .green)
                .frame(height: 40)
                .padding()
        }
        .padding()
    }
}
