import SwiftUI

// MARK: - Today View (Confidence Screen)

struct HealthTodayView: View {
    @ObservedObject var viewModel: HealthViewModel

    var body: some View {
        ScrollView {
            HealthTodayContent(viewModel: viewModel)
        }
        .background(Color.nexusBackground)
        .refreshable {
            await viewModel.fetchLocalHealthKit()
            SyncCoordinator.shared.syncAll(force: true)
            await viewModel.loadData()
        }
    }
}

// MARK: - Supporting Components

struct HealthMetricCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }
}

struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let source: DataSourceType

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)

            SourceBadgeSmall(source: source)
        }
    }
}

enum DataSourceType {
    case whoop, healthkit

    var icon: String {
        switch self {
        case .whoop: return "w.circle.fill"
        case .healthkit: return "heart.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .whoop: return .nexusWarning
        case .healthkit: return .nexusProtein
        }
    }
}

struct SourceBadgeSmall: View {
    let source: DataSourceType

    var body: some View {
        Image(systemName: source.icon)
            .font(.system(size: 10))
            .foregroundColor(source.color)
    }
}

struct SleepStagesBar: View {
    let deep: Int
    let rem: Int
    let light: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color.nexusMood)
                    .frame(width: geo.size.width * CGFloat(deep) / CGFloat(total))

                Rectangle()
                    .fill(Color.nexusPrimary)
                    .frame(width: geo.size.width * CGFloat(rem) / CGFloat(total))

                Rectangle()
                    .fill(Color.cyan.opacity(0.5))
                    .frame(width: geo.size.width * CGFloat(light) / CGFloat(total))
            }
            .cornerRadius(3)
        }
        .frame(height: 6)

        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(Color.nexusMood).frame(width: 8, height: 8)
                Text("Deep").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.nexusPrimary).frame(width: 8, height: 8)
                Text("REM").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                Circle().fill(Color.cyan.opacity(0.5)).frame(width: 8, height: 8)
                Text("Light").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

struct ComparisonBadge: View {
    let value: Double
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2)
                .foregroundColor(value >= 0 ? .nexusSuccess : .nexusWarning)

            Text("\(value >= 0 ? "+" : "")\(Int(value))% \(label)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Shimmer Effect

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.3), .clear]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = UIScreen.main.bounds.width
                }
            }
    }
}
