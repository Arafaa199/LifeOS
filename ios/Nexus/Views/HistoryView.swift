import SwiftUI

struct HistoryView: View {
    @State private var selectedDate = Date()
    @State private var summary: DailySummaryData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var goals = SharedStorage.shared.getGoals()
    @State private var searchText = ""
    @State private var selectedLogType: LogType? = nil

    private let calendar = Calendar.current

    private func filteredLogs(_ logs: [LogEntryData]) -> [LogEntryData] {
        logs.filter { log in
            let matchesSearch = searchText.isEmpty ||
                log.description.localizedCaseInsensitiveContains(searchText)

            let matchesType = selectedLogType == nil ||
                LogType(rawValue: log.type.capitalized) == selectedLogType

            return matchesSearch && matchesType
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Date Navigation Header
                dateNavigationHeader

                ScrollView {
                    VStack(spacing: 20) {
                        // Daily Stats Summary
                        if isLoading {
                            NexusLoadingView(message: "Loading history...")
                                .frame(height: 200)
                        } else if let error = errorMessage {
                            errorView(error)
                        } else if let summary = summary {
                            dailySummarySection(summary)
                            logsSection(summary.logs ?? [])
                        } else {
                            emptyStateView
                        }
                    }
                    .padding(.top, 16)
                }
                .background(NexusTheme.Colors.background)
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Today") {
                        withAnimation {
                            selectedDate = Date()
                        }
                    }
                    .disabled(calendar.isDateInToday(selectedDate))
                }
            }
            .onChange(of: selectedDate) { _, _ in
                Task {
                    await loadSummary()
                }
            }
            .task {
                await loadSummary()
            }
        }
    }

    // MARK: - Date Navigation

    private var dateNavigationHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: previousDay) {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(NexusTheme.Colors.accent)
                        .frame(width: 44, height: 44)
                        .background(NexusTheme.Colors.accent.opacity(0.12))
                        .cornerRadius(12)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(formattedDate)
                        .font(.headline)

                    Text(relativeDateText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: nextDay) {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(canGoForward ? NexusTheme.Colors.accent : .secondary)
                        .frame(width: 44, height: 44)
                        .background((canGoForward ? NexusTheme.Colors.accent : Color.secondary).opacity(0.12))
                        .cornerRadius(12)
                }
                .disabled(!canGoForward)
            }
            .padding(.horizontal)

            // Week View
            weekStrip
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(-3...3, id: \.self) { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: selectedDate)!
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(date)
                let isFuture = date > Date()

                Button(action: {
                    if !isFuture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = date
                        }
                    }
                }) {
                    VStack(spacing: 4) {
                        Text(dayOfWeek(date))
                            .font(.caption2)
                            .foregroundColor(isSelected ? .white : .secondary)

                        Text(dayNumber(date))
                            .font(.subheadline.weight(isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : (isFuture ? .secondary.opacity(0.5) : .primary))

                        if isToday {
                            Circle()
                                .fill(isSelected ? .white : NexusTheme.Colors.accent)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(width: 40, height: 56)
                    .background(isSelected ? NexusTheme.Colors.accent : Color.clear)
                    .cornerRadius(10)
                }
                .disabled(isFuture)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Daily Summary Section

    private func dailySummarySection(_ data: DailySummaryData) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Daily Summary")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                HistoryStatCard(
                    title: "Calories",
                    value: "\(data.calories)",
                    unit: "kcal",
                    icon: "flame.fill",
                    color: NexusTheme.Colors.Semantic.amber,
                    goal: Double(goals.calories),
                    current: Double(data.calories)
                )

                HistoryStatCard(
                    title: "Protein",
                    value: String(format: "%.1f", data.protein),
                    unit: "g",
                    icon: "bolt.fill",
                    color: NexusTheme.Colors.Semantic.purple,
                    goal: goals.protein,
                    current: data.protein
                )

                HistoryStatCard(
                    title: "Water",
                    value: "\(data.water)",
                    unit: "ml",
                    icon: "drop.fill",
                    color: NexusTheme.Colors.Semantic.blue,
                    goal: Double(goals.water),
                    current: Double(data.water)
                )

                HistoryStatCard(
                    title: "Weight",
                    value: data.weight != nil ? String(format: "%.1f", data.weight!) : "--",
                    unit: "kg",
                    icon: "scalemass.fill",
                    color: NexusTheme.Colors.Semantic.purple,
                    goal: goals.weight,
                    current: data.weight
                )
            }
            .padding(.horizontal)

            if let mood = data.mood {
                HStack {
                    HistoryStatCard(
                        title: "Mood",
                        value: "\(mood)",
                        unit: "/ 10",
                        icon: "face.smiling.fill",
                        color: NexusTheme.Colors.accent,
                        goal: 10,
                        current: Double(mood)
                    )

                    if let energy = data.energy {
                        HistoryStatCard(
                            title: "Energy",
                            value: "\(energy)",
                            unit: "/ 10",
                            icon: "bolt.heart.fill",
                            color: NexusTheme.Colors.accent,
                            goal: 10,
                            current: Double(energy)
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Logs Section

    private func logsSection(_ logs: [LogEntryData]) -> some View {
        let filtered = filteredLogs(logs)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity Log")
                    .font(.headline)

                Spacer()

                Text("\(filtered.count) of \(logs.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .padding(.horizontal)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All",
                        isSelected: selectedLogType == nil,
                        action: { selectedLogType = nil }
                    )
                    ForEach([LogType.food, .water, .weight, .mood], id: \.self) { type in
                        FilterChip(
                            title: type.rawValue,
                            isSelected: selectedLogType == type,
                            action: { selectedLogType = selectedLogType == type ? nil : type }
                        )
                    }
                }
                .padding(.horizontal)
            }

            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty && selectedLogType == nil ? "list.bullet.clipboard" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(searchText.isEmpty && selectedLogType == nil ? "No activity logged" : "No matching logs")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if !searchText.isEmpty || selectedLogType != nil {
                        Button(action: {
                            searchText = ""
                            selectedLogType = nil
                        }) {
                            Text("Clear filters")
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(NexusTheme.Colors.card)
                .cornerRadius(16)
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { index, log in
                        HistoryLogRow(log: log)

                        if index < filtered.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(NexusTheme.Colors.card)
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Supporting Views

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Data")
                .font(.headline)

            Text("Select a date to view your history")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(NexusTheme.Colors.Semantic.amber)

            Text("Couldn't Load Data")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                Task { await loadSummary() }
            }) {
                Text("Try Again")
            }
            .nexusSecondaryButton()
            .frame(width: 140)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    private var relativeDateText: String {
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            return formatter.string(from: selectedDate)
        }
    }

    private var canGoForward: Bool {
        !calendar.isDateInToday(selectedDate)
    }

    private func previousDay() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        }
    }

    private func nextDay() {
        guard canGoForward else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        }
    }

    private func dayOfWeek(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func loadSummary() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await NexusAPI.shared.fetchDailySummary(for: selectedDate)
            await MainActor.run {
                if response.success {
                    summary = response.data
                } else {
                    summary = nil
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                summary = nil
                isLoading = false
            }
        }
    }
}

// MARK: - History Stat Card

struct HistoryStatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    var goal: Double? = nil
    var current: Double? = nil

    private var progress: Double? {
        guard let goal = goal, let current = current, goal > 0 else { return nil }
        return min(current / goal, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let progress = progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(0.15))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geometry.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(12)
        .background(NexusTheme.Colors.card)
        .cornerRadius(12)
    }
}

// MARK: - History Log Row

struct HistoryLogRow: View {
    let log: LogEntryData

    private var logType: LogType {
        LogType(rawValue: log.type.capitalized) ?? .other
    }

    private var timestamp: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: log.timestamp) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: log.timestamp)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(colorForType.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: logType.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorForType)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(log.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let time = timestamp {
                    Text(time, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let calories = log.calories, calories > 0 {
                    Text("\(calories) cal")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(NexusTheme.Colors.Semantic.amber.opacity(0.15))
                        .foregroundColor(NexusTheme.Colors.Semantic.amber)
                        .cornerRadius(12)
                }

                if let protein = log.protein, protein > 0 {
                    Text(String(format: "%.0fg", protein))
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(NexusTheme.Colors.Semantic.purple.opacity(0.15))
                        .foregroundColor(NexusTheme.Colors.Semantic.purple)
                        .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var colorForType: Color {
        ColorHelper.color(for: logType)
    }
}

#Preview {
    HistoryView()
}
