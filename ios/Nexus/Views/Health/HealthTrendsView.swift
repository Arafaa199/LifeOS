import SwiftUI
import Combine

// MARK: - Trends View

struct HealthTrendsView: View {
    @ObservedObject var viewModel: HealthViewModel
    @State private var selectedPeriod: String = "7d"

    var body: some View {
        ScrollView {
            HealthTrendsContent(viewModel: viewModel, selectedPeriod: $selectedPeriod)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            SyncCoordinator.shared.syncAll(force: true)
            await viewModel.loadData()
        }
    }
}

// MARK: - Trend Card

struct TrendCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nexusCardBackground)
        .cornerRadius(16)
    }
}

// MARK: - Sparkline View

struct SparklineView: View {
    let data: [Double]
    let color: Color
    var height: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            if data.count >= 2 {
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = maxVal - minVal
                let effectiveRange = range > 0 ? range : 1

                Path { path in
                    let stepX = geo.size.width / CGFloat(data.count - 1)

                    for (index, value) in data.enumerated() {
                        let x = stepX * CGFloat(index)
                        let normalizedY = (value - minVal) / effectiveRange
                        let y = geo.size.height * (1 - normalizedY)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { path in
                    let stepX = geo.size.width / CGFloat(data.count - 1)

                    path.move(to: CGPoint(x: 0, y: geo.size.height))

                    for (index, value) in data.enumerated() {
                        let x = stepX * CGFloat(index)
                        let normalizedY = (value - minVal) / effectiveRange
                        let y = geo.size.height * (1 - normalizedY)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [color.opacity(0.3), color.opacity(0.05)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(height: height)
    }
}
