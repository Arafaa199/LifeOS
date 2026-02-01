import SwiftUI

struct CalendarYearView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var selectedSegment: Int
    @Binding var switchToMonth: Int?

    @State private var displayedYear = Calendar.current.component(.year, from: Date())

    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                yearHeader

                LazyVGrid(columns: monthColumns, spacing: 16) {
                    ForEach(1...12, id: \.self) { month in
                        miniMonthCard(month: month)
                            .onTapGesture {
                                switchToMonth = month
                                selectedSegment = 2
                            }
                    }
                }

                if viewModel.isLoadingEvents {
                    ProgressView()
                        .padding(.top, 8)
                }
            }
            .padding()
        }
        .task {
            await viewModel.fetchYearEvents(year: displayedYear)
        }
        .onChange(of: displayedYear) { newYear in
            Task { await viewModel.fetchYearEvents(year: newYear) }
        }
    }

    // MARK: - Year Header

    private var yearHeader: some View {
        HStack {
            Button { displayedYear -= 1 } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.nexusPrimary)
            }

            Spacer()

            Text(String(displayedYear))
                .font(.title3)
                .fontWeight(.semibold)

            Spacer()

            Button { displayedYear += 1 } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(.nexusPrimary)
            }
        }
    }

    // MARK: - Mini Month Card

    private func miniMonthCard(month: Int) -> some View {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = displayedYear
        comps.month = month
        comps.day = 1

        let firstDay = cal.date(from: comps)!
        let daysRange = cal.range(of: .day, in: .month, for: firstDay)!
        let firstWeekday = cal.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday - cal.firstWeekday + 7) % 7

        let monthName = DateFormatter().monthSymbols[month - 1]
        let today = Date()
        let todayComps = cal.dateComponents([.year, .month, .day], from: today)

        let miniColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return VStack(spacing: 4) {
            Text(monthName.prefix(3).uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            LazyVGrid(columns: miniColumns, spacing: 1) {
                ForEach(0..<(leadingBlanks + daysRange.count), id: \.self) { index in
                    if index < leadingBlanks {
                        Color.clear.frame(height: 10)
                    } else {
                        let day = index - leadingBlanks + 1
                        let dayKey = String(format: "%04d-%02d-%02d", displayedYear, month, day)
                        let count = viewModel.yearEventCounts[dayKey] ?? 0
                        let isToday = todayComps.year == displayedYear && todayComps.month == month && todayComps.day == day

                        let reminderCount = viewModel.yearReminderCounts[dayKey] ?? 0
                        miniDayCircle(day: day, eventCount: count, reminderCount: reminderCount, isToday: isToday)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.nexusCardBackground)
        .cornerRadius(12)
    }

    private func miniDayCircle(day: Int, eventCount: Int, reminderCount: Int, isToday: Bool) -> some View {
        let hasEvents = eventCount > 0
        let hasReminders = reminderCount > 0
        let eventOpacity = min(Double(eventCount) * 0.25, 1.0)
        let reminderOpacity = min(Double(reminderCount) * 0.3, 1.0)

        return VStack(spacing: 1) {
            ZStack {
                if isToday {
                    Circle()
                        .stroke(Color.nexusPrimary, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(height: 10)

            HStack(spacing: 1) {
                if hasEvents {
                    Circle()
                        .fill(Color.nexusPrimary.opacity(eventOpacity))
                        .frame(width: 4, height: 4)
                }
                if hasReminders {
                    Circle()
                        .fill(Color.orange.opacity(reminderOpacity))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(height: 16)
    }
}
