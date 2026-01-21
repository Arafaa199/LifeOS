import SwiftUI
import Charts

struct WeightDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
}

struct WeightHistoryChart: View {
    let weightData: [(date: Date, weight: Double)]

    private var chartData: [WeightDataPoint] {
        // Group by day and take the latest reading per day, limit to 30 days
        let calendar = Calendar.current
        var dailyWeights: [Date: Double] = [:]

        for (date, weight) in weightData {
            let day = calendar.startOfDay(for: date)
            // Keep the latest weight for each day
            if dailyWeights[day] == nil || date > day {
                dailyWeights[day] = weight
            }
        }

        return dailyWeights
            .map { WeightDataPoint(date: $0.key, weight: $0.value) }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }

    private var weightRange: (min: Double, max: Double) {
        let weights = chartData.map { $0.weight }
        let minW = (weights.min() ?? 0) - 1
        let maxW = (weights.max() ?? 100) + 1
        return (minW, maxW)
    }

    private var weightChange: Double? {
        guard chartData.count >= 2 else { return nil }
        let first = chartData.first!.weight
        let last = chartData.last!.weight
        return last - first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weight Trend")
                    .font(.subheadline.weight(.medium))

                Spacer()

                if let change = weightChange {
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption)
                        Text(String(format: "%+.1f kg", change))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(change >= 0 ? .orange : .green)
                }

                Text("30 days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if #available(iOS 16.0, *) {
                Chart(chartData) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(Color.nexusWeight.gradient)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.nexusWeight.opacity(0.3), Color.nexusWeight.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(Color.nexusWeight)
                    .symbolSize(20)
                }
                .chartYScale(domain: weightRange.min...weightRange.max)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let weight = value.as(Double.self) {
                                Text(String(format: "%.0f", weight))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 150)
            } else {
                // Fallback for iOS 15
                Text("Chart requires iOS 16+")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color.nexusWeight.opacity(0.08))
        .cornerRadius(12)
    }
}

#Preview {
    let sampleData: [(date: Date, weight: Double)] = (0..<14).map { dayOffset in
        let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date())!
        let weight = 108.0 + Double.random(in: -1...1)
        return (date, weight)
    }

    return WeightHistoryChart(weightData: sampleData)
        .padding()
}
