import SwiftUI
import UIKit

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var displayedMonth = Date()
    @State private var showingNewEventSheet = false
    @State private var selectedEventForDetail: CalendarDisplayEvent?

    private var year: Int { Calendar.current.component(.year, from: displayedMonth) }
    private var month: Int { Calendar.current.component(.month, from: displayedMonth) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    // Static DateFormatters to avoid repeated instantiation
    private static let dayKeyFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private static let monthYearFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt
    }()

    private static let todayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "'Today,' MMM d"
        return fmt
    }()

    private static let tomorrowFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "'Tomorrow,' MMM d"
        return fmt
    }()

    private static let weekdayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt
    }()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    monthHeader
                        .padding(.horizontal)
                        .padding(.top, NexusTheme.Spacing.xs)

                    weekdayHeader
                        .padding(.horizontal)
                        .padding(.top, NexusTheme.Spacing.md)

                    monthGrid
                        .padding(.horizontal)
                        .padding(.top, NexusTheme.Spacing.xxxs)

                    Rectangle()
                        .fill(NexusTheme.Colors.divider)
                        .frame(height: 1)
                        .padding(.vertical, NexusTheme.Spacing.md)

                    selectedDayDetail
                        .padding(.horizontal)

                    Spacer(minLength: 40)
                }
            }
            .background(NexusTheme.Colors.background)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        NexusTheme.Haptics.light()
                        showingNewEventSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel("Add event")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Today") {
                        NexusTheme.Haptics.light()
                        withAnimation {
                            displayedMonth = Date()
                            viewModel.selectedDate = Date()
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.accent)
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
        .onChange(of: displayedMonth) {
            Task { await loadMonth() }
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundColor(NexusTheme.Colors.accent)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(monthYearLabel)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(NexusTheme.Colors.textPrimary)

            Spacer()

            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundColor(NexusTheme.Colors.accent)
            }
            .accessibilityLabel("Next month")
        }
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textSecondary)
                    .frame(height: 20)
            }
        }
    }

    // MARK: - Month Grid

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: NexusTheme.Spacing.xs) {
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
        let medCount = viewModel.monthMedications[key]?.count ?? 0

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedDate = date
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(dayNum)")
                    .font(.system(size: 14))
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(
                        isSelected ? .white :
                        isToday ? NexusTheme.Colors.accent :
                        NexusTheme.Colors.textPrimary
                    )
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(isSelected ? NexusTheme.Colors.accent : Color.clear)
                    )

                HStack(spacing: 3) {
                    if eventCount > 0 {
                        Circle()
                            .fill(isSelected ? Color.white : NexusTheme.Colors.accent)
                            .frame(width: 5, height: 5)
                    }
                    if reminderCount > 0 {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.7) : NexusTheme.Colors.Semantic.amber)
                            .frame(width: 5, height: 5)
                    }
                    if medCount > 0 {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.7) : NexusTheme.Colors.Semantic.green)
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
            let medications = viewModel.medicationsForDate(date)
            let allDay = events.filter { $0.isAllDay }
            let timed = events.filter { !$0.isAllDay }

            VStack(alignment: .leading, spacing: NexusTheme.Spacing.md) {
                Text(selectedDateLabel(date))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(NexusTheme.Colors.textPrimary)

                if viewModel.isLoadingEvents {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, NexusTheme.Spacing.xxl)
                } else if allDay.isEmpty && timed.isEmpty && reminders.isEmpty && medications.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: NexusTheme.Spacing.xs) {
                            Image(systemName: "calendar")
                                .font(.system(size: 24))
                                .foregroundColor(NexusTheme.Colors.textMuted)
                            Text("No events")
                                .font(.system(size: 14))
                                .foregroundColor(NexusTheme.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, NexusTheme.Spacing.xxl)
                } else {
                    if !allDay.isEmpty {
                        Text("ALL DAY")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(NexusTheme.Colors.textSecondary)

                        ForEach(allDay) { event in
                            Button {
                                selectedEventForDetail = event
                            } label: {
                                Text(event.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, NexusTheme.Spacing.md)
                                    .padding(.vertical, NexusTheme.Spacing.xs)
                                    .background(NexusTheme.Colors.accent)
                                    .cornerRadius(NexusTheme.Radius.xs)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !timed.isEmpty {
                        if !allDay.isEmpty {
                            Text("EVENTS")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(NexusTheme.Colors.textSecondary)
                                .padding(.top, NexusTheme.Spacing.xxxs)
                        }

                        ForEach(timed) { event in
                            inlineEventRow(event)
                        }
                    }

                    // MEDICATIONS SECTION
                    if !medications.isEmpty {
                        Text("MEDICATIONS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                            .padding(.top, NexusTheme.Spacing.xxxs)

                        ForEach(medications) { med in
                            inlineMedicationRow(med)
                        }
                    }

                    // REMINDERS SECTION (now interactive)
                    if !reminders.isEmpty {
                        Text("REMINDERS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(NexusTheme.Colors.textSecondary)
                            .padding(.top, NexusTheme.Spacing.xxxs)

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
            VStack(alignment: .leading, spacing: NexusTheme.Spacing.xxxs) {
                Text(event.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textPrimary)

                HStack(spacing: NexusTheme.Spacing.xs) {
                    Text("\(event.startTime) – \(event.endTime)")
                        .font(.system(size: 11))
                        .foregroundColor(NexusTheme.Colors.textSecondary)

                    if !event.durationLabel.isEmpty {
                        Text(event.durationLabel)
                            .font(.system(size: 9))
                            .foregroundColor(NexusTheme.Colors.accent)
                            .padding(.horizontal, NexusTheme.Spacing.xxs)
                            .padding(.vertical, 2)
                            .background(NexusTheme.Colors.accent.opacity(0.10))
                            .cornerRadius(NexusTheme.Radius.xs)
                    }
                }

                if let location = event.location, !location.isEmpty {
                    HStack(spacing: NexusTheme.Spacing.xxxs) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9))
                        Text(location)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(NexusTheme.Colors.textSecondary)
                }

                if let calendarName = event.calendarName, !calendarName.isEmpty {
                    Text(calendarName)
                        .font(.system(size: 9))
                        .foregroundColor(NexusTheme.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NexusTheme.Spacing.md)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline Reminder Row (Interactive — tap to toggle completion)

    private func inlineReminderRow(_ reminder: ReminderDisplayItem) -> some View {
        Button {
            NexusTheme.Haptics.light()
            Task {
                try? await viewModel.toggleReminderCompletion(reminderId: reminder.reminderId)
            }
        } label: {
            HStack(spacing: NexusTheme.Spacing.sm) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(reminder.isCompleted ? NexusTheme.Colors.Semantic.green : NexusTheme.Colors.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: NexusTheme.Spacing.xxxs) {
                        Text(reminder.title ?? "Untitled")
                            .font(.system(size: 14, weight: .medium))
                            .strikethrough(reminder.isCompleted)
                            .foregroundColor(reminder.isCompleted ? NexusTheme.Colors.textSecondary : NexusTheme.Colors.textPrimary)

                        if let priority = reminder.priorityLabel {
                            Text(priority)
                                .font(.system(size: 9))
                                .foregroundColor(NexusTheme.Colors.Semantic.amber)
                        }
                    }

                    HStack(spacing: NexusTheme.Spacing.xs) {
                        if let time = reminder.dueTime {
                            Text(time)
                                .font(.system(size: 11))
                                .foregroundColor(NexusTheme.Colors.textSecondary)
                        }

                        if let listName = reminder.listName {
                            Text(listName)
                                .font(.system(size: 9))
                                .foregroundColor(NexusTheme.Colors.Semantic.amber)
                                .padding(.horizontal, NexusTheme.Spacing.xxs)
                                .padding(.vertical, 1)
                                .background(NexusTheme.Colors.Semantic.amber.opacity(0.10))
                                .cornerRadius(NexusTheme.Radius.xs)
                        }
                    }
                }

                Spacer()
            }
            .padding(NexusTheme.Spacing.md)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline Medication Row (Interactive — tap to cycle status)

    private func inlineMedicationRow(_ med: MedicationCalendarEntry) -> some View {
        Button {
            NexusTheme.Haptics.light()
            let nextStatus: String
            switch med.status {
            case "scheduled", "pending": nextStatus = "taken"
            case "taken": nextStatus = "skipped"
            case "skipped": nextStatus = "scheduled"
            default: nextStatus = "taken"
            }
            Task {
                try? await viewModel.toggleDoseStatus(
                    medicationId: med.medicationId,
                    scheduledDate: med.scheduledDate,
                    scheduledTime: med.scheduledTime,
                    newStatus: nextStatus
                )
            }
        } label: {
            HStack(spacing: NexusTheme.Spacing.sm) {
                Image(systemName: medStatusIcon(med.status))
                    .font(.body)
                    .foregroundColor(medStatusColor(med.status))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(med.medicationName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(NexusTheme.Colors.textPrimary)

                    HStack(spacing: NexusTheme.Spacing.xs) {
                        if let time = med.timeLabel {
                            Text(time)
                                .font(.system(size: 11))
                                .foregroundColor(NexusTheme.Colors.textSecondary)
                        }

                        Text(med.dosageLabel)
                            .font(.system(size: 9))
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                            .padding(.horizontal, NexusTheme.Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(NexusTheme.Colors.Semantic.green.opacity(0.10))
                            .cornerRadius(NexusTheme.Radius.xs)
                    }
                }

                Spacer()

                Text(med.status.capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(medStatusColor(med.status))
            }
            .padding(NexusTheme.Spacing.md)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.Semantic.green.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func medStatusIcon(_ status: String) -> String {
        switch status {
        case "taken": return "checkmark.circle.fill"
        case "skipped": return "xmark.circle.fill"
        case "missed": return "exclamationmark.circle.fill"
        default: return "clock.fill"
        }
    }

    private func medStatusColor(_ status: String) -> Color {
        switch status {
        case "taken": return NexusTheme.Colors.Semantic.green
        case "skipped": return .red
        case "missed": return .orange
        default: return NexusTheme.Colors.textSecondary
        }
    }

    // MARK: - Helpers

    private func changeMonth(_ delta: Int) {
        NexusTheme.Haptics.light()
        withAnimation(.easeInOut(duration: 0.3)) {
            if let next = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
                displayedMonth = next
            }
        }
    }

    private func loadMonth() async {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let startDate = Calendar.current.date(from: comps) ?? Date()
        let endDate = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? startDate

        let startStr = Self.dayKeyFormatter.string(from: startDate)
        let endStr = Self.dayKeyFormatter.string(from: endDate)

        // Fetch events, reminders, and medications in parallel
        async let eventsTask: Void = viewModel.fetchMonthEvents(year: year, month: month)
        async let remindersTask: Void = viewModel.fetchReminders(start: startStr, end: endStr)
        async let medsTask: Void = viewModel.fetchMedications(start: startStr, end: endStr)
        _ = await (eventsTask, remindersTask, medsTask)
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
        Self.dayKeyFormatter.string(from: date)
    }

    private var monthYearLabel: String {
        Self.monthYearFormatter.string(from: displayedMonth)
    }

    private func selectedDateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.todayFormatter.string(from: date)
        } else if Calendar.current.isDateInTomorrow(date) {
            return Self.tomorrowFormatter.string(from: date)
        } else {
            return Self.weekdayFormatter.string(from: date)
        }
    }

    private func isSameDay(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }
}

#Preview {
    CalendarView()
}
