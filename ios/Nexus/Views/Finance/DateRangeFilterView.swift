import SwiftUI

struct DateRangeFilterView: View {
    @Binding var selectedRange: DateRange
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(DateRange.allCases, id: \.self) { range in
                        Button(action: {
                            selectedRange = range
                            if range != .custom {
                                isPresented = false
                            }
                        }) {
                            HStack {
                                Text(range.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedRange == range {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(NexusTheme.Colors.accent)
                                }
                            }
                        }
                    }
                }

                if selectedRange == .custom {
                    Section("Custom Range") {
                        DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)

                        Button("Apply") {
                            isPresented = false
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

enum DateRange: String, CaseIterable {
    case today = "today"
    case yesterday = "yesterday"
    case thisWeek = "this_week"
    case lastWeek = "last_week"
    case thisMonth = "this_month"
    case lastMonth = "last_month"
    case last30Days = "last_30_days"
    case last90Days = "last_90_days"
    case thisYear = "this_year"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .lastWeek: return "Last Week"
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .last30Days: return "Last 30 Days"
        case .last90Days: return "Last 90 Days"
        case .thisYear: return "This Year"
        case .custom: return "Custom Range"
        }
    }

    func getDateRange() -> (start: Date, end: Date) {
        let calendar = Constants.Dubai.calendar
        let now = Date()

        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)

        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            let start = calendar.startOfDay(for: yesterday)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)

        case .thisWeek:
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            return (start, end)

        case .lastWeek:
            let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let start = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
            let end = thisWeekStart
            return (start, end)

        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return (start, end)

        case .lastMonth:
            let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
            let end = thisMonthStart
            return (start, end)

        case .last30Days:
            let end = now
            let start = calendar.date(byAdding: .day, value: -30, to: end)!
            return (start, end)

        case .last90Days:
            let end = now
            let start = calendar.date(byAdding: .day, value: -90, to: end)!
            return (start, end)

        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now))!
            let end = calendar.date(byAdding: .year, value: 1, to: start)!
            return (start, end)

        case .custom:
            // Will be handled separately with custom dates
            return (now, now)
        }
    }
}
