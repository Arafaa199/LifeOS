import SwiftUI

struct CalendarMonthView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var switchToMonth: Int?

    @State private var displayedMonth = Date()
    @State private var showDayDetail = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    private var year: Int { Calendar.current.component(.year, from: displayedMonth) }
    private var month: Int { Calendar.current.component(.month, from: displayedMonth) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader

                weekdayHeader

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(daysInMonth(), id: \.self) { day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear
                                .frame(height: 44)
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
            await loadMonth()
        }
        .onChange(of: displayedMonth) { _ in
            Task { await loadMonth() }
        }
        .onChange(of: switchToMonth) { newMonth in
            if let m = newMonth {
                var comps = Calendar.current.dateComponents([.year], from: displayedMonth)
                comps.month = m
                comps.day = 1
                if let date = Calendar.current.date(from: comps) {
                    displayedMonth = date
                }
                switchToMonth = nil
            }
        }
        .sheet(isPresented: $showDayDetail) {
            if let selected = viewModel.selectedDate {
                CalendarDayDetailView(
                    date: selected,
                    events: viewModel.eventsForDate(selected),
                    reminders: viewModel.remindersForDate(selected)
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.nexusPrimary)
            }

            Spacer()

            Text(monthYearLabel)
                .font(.title3)
                .fontWeight(.semibold)

            Spacer()

            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(.nexusPrimary)
            }
        }
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(height: 24)
            }
        }
    }

    // MARK: - Day Cell

    private func dayCell(_ date: Date) -> some View {
        let dayNum = Calendar.current.component(.day, from: date)
        let isToday = Calendar.current.isDateInToday(date)
        let key = dayKey(date)
        let eventCount = viewModel.monthEvents[key]?.count ?? 0
        let reminderCount = viewModel.monthReminders[key]?.count ?? 0

        return Button {
            viewModel.selectedDate = date
            showDayDetail = true
        } label: {
            VStack(spacing: 2) {
                Text("\(dayNum)")
                    .font(.subheadline)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(isToday ? .white : .primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isToday ? Color.nexusPrimary : Color.clear)
                    )

                HStack(spacing: 3) {
                    if eventCount > 0 {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 5, height: 5)
                    }
                    if reminderCount > 0 {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(height: 44)
    }

    // MARK: - Helpers

    private func changeMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func loadMonth() async {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let startDate = Calendar.current.date(from: comps) ?? Date()
        let endDate = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? startDate

        let startStr = fmt.string(from: startDate)
        let endStr = fmt.string(from: endDate)

        await viewModel.fetchMonthEvents(year: year, month: month)
        await viewModel.fetchReminders(start: startStr, end: endStr)
    }

    private func daysInMonth() -> [Date?] {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1

        guard let firstDay = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstDay) else {
            return []
        }

        let firstWeekday = cal.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday - cal.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)

        for day in range {
            comps.day = day
            days.append(cal.date(from: comps))
        }

        return days
    }

    private func dayKey(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    private var monthYearLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: displayedMonth)
    }
}
