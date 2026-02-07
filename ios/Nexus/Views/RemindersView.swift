import SwiftUI
import os

struct RemindersView: View {
    @ObservedObject private var syncService = ReminderSyncService.shared
    @State private var reminders: [ReminderDisplayItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddSheet = false
    @State private var showCompleted = false

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "reminders")

    var body: some View {
        Group {
            if isLoading && reminders.isEmpty {
                ProgressView("Loading reminders...")
            } else if let error = errorMessage, reminders.isEmpty {
                errorView(error)
            } else {
                remindersList
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showCompleted.toggle()
                    } label: {
                        Image(systemName: showCompleted ? "eye.fill" : "eye.slash")
                    }
                    .accessibilityLabel(showCompleted ? "Hide completed" : "Show completed")

                    Button {
                        Task { await syncReminders() }
                    } label: {
                        Image(systemName: syncService.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                            .rotationEffect(.degrees(syncService.isSyncing ? 360 : 0))
                            .animation(syncService.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: syncService.isSyncing)
                    }
                    .disabled(syncService.isSyncing)
                    .accessibilityLabel("Sync reminders")

                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add reminder")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddReminderSheet { _ in
                Task { await loadReminders() }
            }
        }
        .refreshable {
            await loadReminders()
        }
        .task {
            await loadReminders()
        }
    }

    // MARK: - Reminders List

    private var remindersList: some View {
        List {
            // Sync status
            if let lastSync = syncService.lastSyncDate {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(syncService.lastSyncReminderCount) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Group by list
            ForEach(groupedReminders.keys.sorted(), id: \.self) { listName in
                Section(listName) {
                    ForEach(groupedReminders[listName] ?? []) { reminder in
                        ReminderRow(
                            reminder: reminder,
                            onToggle: { toggleCompletion(reminder) },
                            onDelete: { deleteReminder(reminder) }
                        )
                    }
                }
            }

            if displayedReminders.isEmpty {
                Section {
                    ContentUnavailableView(
                        showCompleted ? "No Reminders" : "No Pending Reminders",
                        systemImage: "checkmark.circle",
                        description: Text(showCompleted ? "Add a reminder to get started" : "All caught up! Tap the eye to show completed.")
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var displayedReminders: [ReminderDisplayItem] {
        if showCompleted {
            return reminders
        }
        return reminders.filter { !$0.isCompleted }
    }

    private var groupedReminders: [String: [ReminderDisplayItem]] {
        Dictionary(grouping: displayedReminders) { $0.listName ?? "Reminders" }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry") {
                Task { await loadReminders() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - API

    private func loadReminders() async {
        isLoading = true
        errorMessage = nil

        // Load upcoming 30 days + past 7 days
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
        let end = formatter.string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())

        do {
            let response = try await NexusAPI.shared.fetchReminders(start: start, end: end)
            if response.success {
                reminders = response.reminders ?? []
                logger.info("Loaded \(self.reminders.count) reminders")
            } else {
                errorMessage = "Failed to load reminders"
            }
        } catch {
            if reminders.isEmpty {
                errorMessage = error.localizedDescription
            }
            logger.error("Failed to load reminders: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func syncReminders() async {
        do {
            try await syncService.syncAllData()
            await loadReminders()
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
        }
    }

    private func toggleCompletion(_ reminder: ReminderDisplayItem) {
        Task {
            do {
                let response = try await NexusAPI.shared.toggleReminderCompletion(
                    reminderId: reminder.reminderId,
                    isCompleted: !reminder.isCompleted
                )
                if response.success {
                    logger.info("Toggled reminder: \(reminder.reminderId)")
                    await loadReminders()
                    // Trigger sync to push to EventKit
                    do {
                        try await syncService.syncAllData()
                    } catch {
                        logger.warning("Sync after toggle failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                logger.error("Failed to toggle reminder: \(error.localizedDescription)")
            }
        }
    }

    private func deleteReminder(_ reminder: ReminderDisplayItem) {
        Task {
            do {
                let response = try await NexusAPI.shared.deleteReminder(reminderId: reminder.reminderId)
                if response.success {
                    logger.info("Deleted reminder: \(reminder.reminderId)")
                    await loadReminders()
                    // Trigger sync to delete from EventKit
                    do {
                        try await syncService.syncAllData()
                    } catch {
                        logger.warning("Sync after delete failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                logger.error("Failed to delete reminder: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Reminder Row

struct ReminderRow: View {
    let reminder: ReminderDisplayItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Completion button
            Button(action: onToggle) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(reminder.isCompleted ? .nexusSuccess : .secondary)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(reminder.title ?? "Untitled")
                        .font(.body)
                        .strikethrough(reminder.isCompleted)
                        .foregroundColor(reminder.isCompleted ? .secondary : .primary)

                    if let priorityLabel = reminder.priorityLabel {
                        Text(priorityLabel)
                            .font(.caption)
                            .foregroundColor(.nexusWarning)
                    }
                }

                HStack(spacing: 8) {
                    if let dueTime = reminder.dueTime {
                        Label(dueTime, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let dueDate = reminder.dueDate {
                        Text(formatDueDate(dueDate))
                            .font(.caption)
                            .foregroundColor(isOverdue(dueDate) && !reminder.isCompleted ? .red : .secondary)
                    }
                }

                if let notes = reminder.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onToggle) {
                Label(
                    reminder.isCompleted ? "Undo" : "Complete",
                    systemImage: reminder.isCompleted ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(reminder.isCompleted ? .orange : .green)
        }
    }

    private func formatDueDate(_ dateStr: String) -> String {
        let dayStr = String(dateStr.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayStr) else { return dayStr }

        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func isOverdue(_ dateStr: String) -> Bool {
        let dayStr = String(dateStr.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayStr) else { return false }
        return date < Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - Add Reminder Sheet

struct AddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ReminderDisplayItem) -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var hasDueTime = false
    @State private var priority = 0
    @State private var listName = "Reminders"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "reminders")

    private let lists = ["Reminders", "Work", "Personal", "Shopping", "Health"]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $title)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Due Date") {
                    Toggle("Set Due Date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)

                        Toggle("Set Time", isOn: $hasDueTime)

                        if hasDueTime {
                            DatePicker("Time", selection: $dueDate, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("None").tag(0)
                        Text("Low (!)").tag(9)
                        Text("Medium (!!)").tag(5)
                        Text("High (!!!)").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                Section("List") {
                    Picker("List", selection: $listName) {
                        ForEach(lists, id: \.self) { list in
                            Text(list).tag(list)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        var dueDateStr: String?
        if hasDueDate {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = Constants.Dubai.timeZone
            if hasDueTime {
                dueDateStr = formatter.string(from: dueDate)
            } else {
                // Set time to start of day
                let startOfDay = Calendar.current.startOfDay(for: dueDate)
                dueDateStr = formatter.string(from: startOfDay)
            }
        }

        let request = ReminderCreateRequest(
            title: title,
            notes: notes.isEmpty ? nil : notes,
            dueDate: dueDateStr,
            priority: priority,
            listName: listName
        )

        do {
            let response = try await NexusAPI.shared.createReminder(request)
            if response.success {
                logger.info("Created reminder: \(title)")
                // Create a display item to pass back
                let item = ReminderDisplayItem(
                    reminderId: response.reminder?.reminderId ?? UUID().uuidString,
                    title: title,
                    notes: notes.isEmpty ? nil : notes,
                    dueDate: dueDateStr,
                    isCompleted: false,
                    completedDate: nil,
                    priority: priority,
                    listName: listName
                )
                onSave(item)
                dismiss()
            } else {
                errorMessage = "Failed to create reminder"
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to create reminder: \(error.localizedDescription)")
        }

        isSaving = false
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        RemindersView()
    }
}
