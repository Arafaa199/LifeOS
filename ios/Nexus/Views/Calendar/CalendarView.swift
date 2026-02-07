import SwiftUI

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var displayedMonth = Date()
    @State private var showingNewEventSheet = false
    @State private var selectedEventForDetail: CalendarDisplayEvent?

    private var year: Int { Calendar.current.component(.year, from: displayedMonth) }
    private var month: Int { Calendar.current.component(.month, from: displayedMonth) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    monthHeader
                        .padding(.horizontal)
                        .padding(.top, 8)

                    weekdayHeader
                        .padding(.horizontal)
                        .padding(.top, 12)

                    monthGrid
                        .padding(.horizontal)
                        .padding(.top, 4)

                    Divider()
                        .padding(.vertical, 12)

                    selectedDayDetail
                        .padding(.horizontal)

                    Spacer(minLength: 40)
                }
            }
            .background(Color.nexusBackground)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingNewEventSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Today") {
                        withAnimation {
                            displayedMonth = Date()
                            viewModel.selectedDate = Date()
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.nexusPrimary)
                }
            }
            .sheet(isPresented: $showingNewEventSheet) {
                EventEditSheet(viewModel: viewModel, isPresented: $showingNewEventSheet, existingEvent: nil)
            }
            .sheet(item: $selectedEventForDetail) { event in
                NavigationView {
                    EventDetailView(viewModel: viewModel, event: event)
                }
            }
        }
        .task {
            viewModel.selectedDate = Date()
            await loadMonth()
        }
        .onChange(of: displayedMonth) { _ in
            Task { await loadMonth() }
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.nexusPrimary)
            }

            Spacer()

            Text(monthYearLabel)
                .font(.title3.weight(.semibold))

            Spacer()

            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.nexusPrimary)
            }
        }
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(height: 20)
            }
        }
    }

    // MARK: - Month Grid

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(daysInMonth(), id: \.self) { day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    // MARK: - Day Cell

    private func dayCell(_ date: Date) -> some View {
        let dayNum = Calendar.current.component(.day, from: date)
        let isToday = Calendar.current.isDateInToday(date)
        let isSelected = isSameDay(date, viewModel.selectedDate)
        let key = dayKey(date)
        let eventCount = viewModel.monthEvents[key]?.count ?? 0
        let reminderCount = viewModel.monthReminders[key]?.count ?? 0

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedDate = date
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(dayNum)")
                    .font(.subheadline)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(
                        isSelected ? .white :
                        isToday ? .nexusPrimary :
                        .primary
                    )
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.nexusPrimary : Color.clear)
                    )

                HStack(spacing: 3) {
                    if eventCount > 0 {
                        Circle()
                            .fill(isSelected ? Color.white : Color.nexusPrimary)
                            .frame(width: 5, height: 5)
                    }
                    if reminderCount > 0 {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.7) : Color.nexusWarning)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(height: 46)
    }

    // MARK: - Selected Day Detail

    @ViewBuilder
    private var selectedDayDetail: some View {
        if let date = viewModel.selectedDate {
            let events = viewModel.eventsForDate(date)
            let reminders = viewModel.remindersForDate(date)
            let allDay = events.filter { $0.isAllDay }
            let timed = events.filter { !$0.isAllDay }

            VStack(alignment: .leading, spacing: 12) {
                Text(selectedDateLabel(date))
                    .font(.headline)
                    .foregroundColor(.primary)

                if viewModel.isLoadingEvents {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 20)
                } else if allDay.isEmpty && timed.isEmpty && reminders.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.title2)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No events")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else {
                    if !allDay.isEmpty {
                        Text("ALL DAY")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        ForEach(allDay) { event in
                            Button {
                                selectedEventForDetail = event
                            } label: {
                                Text(event.title)
                                    .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.plain)
                            .nexusChip(color: .nexusPrimary)
                        }
                    }

                    if !timed.isEmpty {
                        if !allDay.isEmpty {
                            Text("EVENTS")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }

                        ForEach(timed) { event in
                            inlineEventRow(event)
                        }
                    }

                    if !reminders.isEmpty {
                        Text("REMINDERS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        ForEach(reminders) { reminder in
                            inlineReminderRow(reminder)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Inline Event Row

    private func inlineEventRow(_ event: CalendarDisplayEvent) -> some View {
        Button {
            selectedEventForDetail = event
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text("\(event.startTime) – \(event.endTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !event.durationLabel.isEmpty {
                        Text(event.durationLabel)
                            .font(.caption2)
                            .foregroundColor(.nexusPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.nexusPrimary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.caption2)
                        Text(location)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                if let calendarName = event.calendarName, !calendarName.isEmpty {
                    Text(calendarName)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .nexusCard()
    }

    // MARK: - Inline Reminder Row

    private func inlineReminderRow(_ reminder: ReminderDisplayItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundColor(reminder.isCompleted ? .nexusSuccess : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(reminder.title ?? "Untitled")
                        .font(.subheadline.weight(.medium))
                        .strikethrough(reminder.isCompleted)
                        .foregroundColor(reminder.isCompleted ? .secondary : .primary)

                    if let priority = reminder.priorityLabel {
                        Text(priority)
                            .font(.caption2)
                            .foregroundColor(.nexusWarning)
                    }
                }

                HStack(spacing: 8) {
                    if let time = reminder.dueTime {
                        Text(time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let listName = reminder.listName {
                        Text(listName)
                            .font(.caption2)
                            .foregroundColor(.nexusWarning.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.nexusWarning.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()
        }
        .nexusCard()
    }

    // MARK: - Helpers

    private func changeMonth(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if let next = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
                displayedMonth = next
            }
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

    private func selectedDateLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            fmt.dateFormat = "'Today,' MMM d"
        } else if Calendar.current.isDateInTomorrow(date) {
            fmt.dateFormat = "'Tomorrow,' MMM d"
        } else {
            fmt.dateFormat = "EEEE, MMM d"
        }
        return fmt.string(from: date)
    }

    private func isSameDay(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }
}

#Preview {
    CalendarView()
}
